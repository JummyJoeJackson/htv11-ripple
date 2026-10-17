import Foundation
import Observation
import RippleKit
import UIKit

struct Banner: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var ok: Bool
}

enum BackendStatus: Equatable {
    case unknown
    case online
    case offline(String)

    var isOnline: Bool { self == .online }

    var offlineReason: String? {
        if case .offline(let reason) = self { return reason }
        return nil
    }
}

/// Forwards coordinator callbacks to closures, so the main-actor store
/// doesn't have to conform to the protocol itself.
final class CoordinatorBridge: AlarmCoordinatorDelegate {
    var onSend: (([OutMessage]) -> Void)?
    var onChange: (() -> Void)?

    func coordinator(_ coordinator: AlarmCoordinator, send messages: [OutMessage]) { onSend?(messages) }
    func coordinatorDidChange(_ coordinator: AlarmCoordinator) { onChange?() }
}

/// The wearer's iPhone. It owns the alarm (through AlarmCoordinator), sends
/// every text first through the Ripple Alert shortcut, keeps the Watch in
/// sync, and heartbeats the backend so the backup sender knows it's alive.
@MainActor
@Observable
final class WearerStore {
    private(set) var serverAddress: String
    private(set) var deviceToken: String?
    private(set) var pairingCode: String
    private(set) var config: RippleConfig
    private(set) var backend: BackendStatus = .unknown
    private(set) var lastSyncAt: Date?
    private(set) var temporaryContacts: [TemporaryContactView] = []
    /// Set while the demo admin's "Cut phone connection" is in effect.
    private(set) var outageUntil: Date?
    private(set) var watchConfigVersion: Int?
    private(set) var watchConfigSyncedAt: Date?
    private(set) var pending: String?
    private(set) var testResult: String?
    var banner: Banner?
    /// Bumped whenever the coordinator changes, so views refresh.
    private(set) var revision = 0

    let coordinator: AlarmCoordinator
    let sender = ShortcutSender()
    let connectivity = PhoneConnectivity()
    let location = LocationProvider()
    let speech = SpeechListener()
    let health = HealthAlerts()
    private let bridge = CoordinatorBridge()

    @ObservationIgnored private var api: RippleAPI?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var commandResults: [CommandResult] = []
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var resyncRequested = false
    @ObservationIgnored private var waitingForSyncAfterOutage = false
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private var locatedAlarmId: String?
    @ObservationIgnored private var pendingJoinReplies: [JoinTemporaryRequest] = []

    private enum Keys {
        static let server = "ripple.serverAddress"
        static let token = "ripple.deviceToken"
        static let pairing = "ripple.pairingCode"
        static let config = "ripple.config"
        static let coordinator = "ripple.coordinator"
        static let watchVersion = "ripple.watchConfigVersion"
        static let joinReplies = "ripple.pendingJoinReplies"
    }

    var isSetUp: Bool { deviceToken != nil }

    var inOutage: Bool {
        guard let outageUntil else { return false }
        return outageUntil > Date()
    }

    init() {
        let defaults = UserDefaults.standard
        let savedConfig = defaults.data(forKey: Keys.config).flatMap { try? RippleJSON.decoder.decode(RippleConfig.self, from: $0) }
        let snapshot = defaults.data(forKey: Keys.coordinator).flatMap { try? RippleJSON.decoder.decode(AlarmCoordinator.Snapshot.self, from: $0) }
        let initialConfig = savedConfig ?? RippleConfig.makeDefault(wearerName: "")
        serverAddress = defaults.string(forKey: Keys.server) ?? ""
        deviceToken = defaults.string(forKey: Keys.token)
        pairingCode = defaults.string(forKey: Keys.pairing) ?? ""
        config = initialConfig
        let storedWatchVersion = defaults.integer(forKey: Keys.watchVersion)
        watchConfigVersion = storedWatchVersion > 0 ? storedWatchVersion : nil
        coordinator = AlarmCoordinator(config: initialConfig, snapshot: snapshot)
        pendingJoinReplies = defaults.data(forKey: Keys.joinReplies)
            .flatMap { try? RippleJSON.decoder.decode([JoinTemporaryRequest].self, from: $0) }?
            .filter { $0.runId == coordinator.runId } ?? []
        coordinator.delegate = bridge
        sender.shortcutName = initialConfig.shortcutName
        rebuildAPI()
        wire()
        // Registered at launch, so Apple Health can wake Ripple for new alerts.
        Task { [health = self.health, kinds = initialConfig.healthAlerts] in
            await health.update(kinds, askPermission: false)
        }
    }

    private func wire() {
        bridge.onSend = { [weak self] messages in
            self?.sender.enqueue(messages)
        }
        bridge.onChange = { [weak self] in
            self?.coordinatorChanged()
        }
        sender.statusOf = { [weak self] id in
            self?.coordinator.message(id)
        }
        sender.onLaunched = { [weak self] ids in
            self?.coordinator.markLaunched(ids: ids)
        }
        sender.onResult = { [weak self] ids, status, detail in
            self?.coordinator.recordResults(ids: ids, status: status, detail: detail)
        }
        sender.onTestResult = { [weak self] text in
            self?.testResult = text
        }
        sender.onInvitationResult = { [weak self] id, status, detail in
            guard let self, self.temporaryContacts.first(where: { $0.id == id })?.state == .invited else { return }
            self.banner = Banner(
                text: status == .submitted
                    ? "Invitation shortcut finished. Check Messages to confirm it was sent."
                    : "Invitation wasn't confirmed. You can send it again. \(detail ?? status.label)",
                ok: status == .submitted
            )
        }
        sender.canLaunch = { [weak self] in
            guard let self else { return false }
            return self.appActive && !self.inOutage
        }
        connectivity.onAction = { [weak self] action, reply in
            guard let self else { return }
            reply(self.handleWatch(action))
        }
        connectivity.onConfigAck = { [weak self] version in
            self?.watchConfirmed(version)
        }
        connectivity.onReachable = { [weak self] in
            self?.pushToWatch(force: true)
        }
        // The Watch listens for the voice phrase; this iPhone recognizes the speech.
        connectivity.onVoiceAudio = { [weak self] session, audio in
            guard let self, self.config.voiceEnabled, !self.inOutage else { return }
            self.speech.receive(sessionId: session, audio: audio, phrase: self.config.voicePhrase)
        }
        connectivity.onVoiceStop = { [weak self] session in
            self?.speech.stop(sessionId: session)
        }
        speech.onHeard = { [weak self] heard in
            self?.connectivity.send(heard)
        }
        health.onAlert = { [weak self] kind in
            self?.healthAlertArrived(kind)
        }
    }

    private func rebuildAPI() {
        if let deviceToken, let url = RippleAPI.normalizedURL(from: serverAddress) {
            api = RippleAPI(baseURL: url, token: deviceToken)
        } else {
            api = nil
        }
    }

    // MARK: Setup

    func setUp(serverAddress address: String, name: String) async -> Bool {
        guard let url = RippleAPI.normalizedURL(from: address) else {
            banner = Banner(text: "Enter the server address printed in the server console, like 192.168.1.20:8080.", ok: false)
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = "Connecting…"
        defer { pending = nil }
        do {
            let response = try await RippleAPI(baseURL: url, token: nil).setup(SetupRequest(displayName: trimmed))
            serverAddress = url.absoluteString
            deviceToken = response.deviceToken
            pendingJoinReplies.removeAll()
            persistJoinReplies()
            pairingCode = response.pairingCode
            UserDefaults.standard.set(serverAddress, forKey: Keys.server)
            UserDefaults.standard.set(response.deviceToken, forKey: Keys.token)
            UserDefaults.standard.set(response.pairingCode, forKey: Keys.pairing)
            coordinator.setRunId(response.runId)
            var updated = config
            updated.wearerName = trimmed
            save(updated)
            rebuildAPI()
            banner = nil
            start()
            return true
        } catch {
            banner = Banner(text: describe(error), ok: false)
            return false
        }
    }

    /// Clears this iPhone's registration so it can be set up again.
    func forgetDevice() {
        loopTask?.cancel()
        loopTask = nil
        deviceToken = nil
        backend = .unknown
        UserDefaults.standard.removeObject(forKey: Keys.token)
        coordinator.reset(runId: "")
        rebuildAPI()
    }

    // MARK: Configuration

    /// Saves the configuration, bumps its version and sends it to the Watch.
    func save(_ updated: RippleConfig) {
        var next = updated
        next.version = max(config.version, coordinator.config.version) + 1
        config = next
        sender.shortcutName = next.shortcutName
        coordinator.config = next
        persistConfig()
        if next.contacts.contains(where: \.shareLocation) {
            location.requestPermission()
        }
        if next.voiceEnabled {
            speech.requestPermission()
        }
        Task { [health = self.health, kinds = next.healthAlerts] in
            await health.update(kinds, askPermission: true)
        }
        pushToWatch(force: true)
    }

    private func persistConfig() {
        if let data = try? RippleJSON.encoder.encode(config) {
            UserDefaults.standard.set(data, forKey: Keys.config)
        }
    }

    private func watchConfirmed(_ version: Int) {
        watchConfigVersion = version
        watchConfigSyncedAt = Date()
        UserDefaults.standard.set(version, forKey: Keys.watchVersion)
    }

    // MARK: Loop

    func start() {
        if config.voiceEnabled { speech.requestPermission() }
        guard isSetUp, loopTask == nil else {
            pushToWatch(force: true)
            return
        }
        pushToWatch(force: true)
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.step()
                await self?.sync()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func setActive(_ active: Bool) {
        appActive = active
        if active {
            sender.launchIfPossible()
            Task { await sync() }
        }
    }

    private func step() {
        speech.endIfQuiet()
        if outageUntil != nil && !inOutage {
            outageUntil = nil
            waitingForSyncAfterOutage = true
            banner = Banner(text: "Simulated phone failure ended. Catching up with the backend.", ok: true)
            pushToWatch(force: true)
        }
        // A "dead" phone does nothing; after it recovers it first learns what the backup sent.
        guard !inOutage, !waitingForSyncAfterOutage else { return }
        coordinator.tick()
        sender.tick()
        health.checkNow()
    }

    func sync() async {
        guard let api, !inOutage else { return }
        guard !syncing else {
            resyncRequested = true
            return
        }
        syncing = true
        let results = commandResults
        let request = SyncRequest(runId: coordinator.runId, status: deviceStatus(), alarm: alarmForSync(), commandResults: results)
        do {
            let response = try await api.sync(request)
            commandResults.removeAll { result in results.contains { $0.commandId == result.commandId } }
            lastSyncAt = Date()
            backend = .online
            apply(response)
            waitingForSyncAfterOutage = false
            await processJoinReplies(using: api)
        } catch let error as RippleAPIError where error.isUnauthorized {
            backend = .offline("The server doesn't recognize this iPhone. Use Settings → Set up again.")
        } catch {
            backend = .offline(describe(error))
        }
        syncing = false
        if resyncRequested {
            resyncRequested = false
            Task { await sync() }
        }
    }

    private func apply(_ response: SyncResponse) {
        if response.resetRequired {
            sender.cancelAll()
            pendingJoinReplies.removeAll()
            persistJoinReplies()
            coordinator.reset(runId: response.runId)
            banner = Banner(text: "The demo was reset.", ok: true)
        }
        if pairingCode != response.pairingCode {
            pairingCode = response.pairingCode
            UserDefaults.standard.set(pairingCode, forKey: Keys.pairing)
        }
        temporaryContacts = response.temporaryContacts
        coordinator.temporaryContacts = response.temporaryContacts
        if let feedback = response.feedback {
            coordinator.applyFeedback(feedback)
        }
        for command in response.commands {
            execute(command)
        }
    }

    private func execute(_ command: DeviceCommand) {
        let result = coordinator.once(command.id) {
            switch command.kind {
            case .triggerAlarm:
                return coordinator.startAlarm(source: .admin, countdownSeconds: command.countdownSeconds)
            case .disableAlarm:
                return coordinator.disableAlarm()
            case .setTimers:
                return coordinator.setTimers(countdownSeconds: command.countdownSeconds, ackWindowSeconds: command.ackWindowSeconds)
            case .cutConnection:
                let seconds = command.durationSeconds ?? 90
                outageUntil = Date().addingTimeInterval(TimeInterval(seconds))
                pushToWatch(force: true)
                return ActionResult(ok: true, feedback: "Simulated phone failure for \(seconds) s")
            case .simulateHealthAlert:
                return healthAlertArrived(command.healthAlert ?? .fall, simulated: true)
            }
        }
        if !commandResults.contains(where: { $0.commandId == command.id }) {
            commandResults.append(CommandResult(commandId: command.id, ok: result.ok, message: result.feedback))
        }
    }

    // MARK: Apple Health alerts

    /// Apple Watch recorded a fall or a heart alert in Apple Health, or the
    /// demo admin simulated one. Starts a check-in if the wearer turned that
    /// alert on; Ripple adds the people, Apple did the detecting.
    @discardableResult
    private func healthAlertArrived(_ kind: HealthAlertKind, simulated: Bool = false) -> ActionResult {
        guard !inOutage else {
            return ActionResult(ok: false, feedback: "iPhone unavailable")
        }
        guard config.healthAlerts.contains(kind) else {
            return ActionResult(ok: false, feedback: "\(kind.label) check-ins are off in Ripple's settings.")
        }
        let result = coordinator.healthAlert(kind)
        // Empty feedback means a duress alarm is open: show nothing.
        if !simulated && !result.feedback.isEmpty {
            show(result)
        }
        return result
    }

    /// Ends the simulated phone failure early.
    func restoreConnection() {
        guard outageUntil != nil else { return }
        outageUntil = Date()
        step()
        Task { await sync() }
    }

    private func deviceStatus() -> DeviceStatus {
        DeviceStatus(
            displayName: config.wearerName,
            monitoring: coordinator.monitoring,
            watchPaired: connectivity.isPaired,
            watchReachable: connectivity.isReachable,
            configVersion: config.version,
            watchConfigVersion: watchConfigVersion,
            nextCheckInAt: coordinator.nextCheckInAt,
            appActive: appActive
        )
    }

    /// The open alarm, or the most recent one for a few minutes so the backend sees it close.
    private func alarmForSync() -> Alarm? {
        guard let alarm = coordinator.alarm else { return nil }
        if alarm.isOpen { return alarm }
        if let closedAt = alarm.closedAt, Date().timeIntervalSince(closedAt) < 300 { return alarm }
        return nil
    }

    // MARK: Coordinator changes

    private func coordinatorChanged() {
        revision += 1
        if let data = try? RippleJSON.encoder.encode(coordinator.snapshot) {
            UserDefaults.standard.set(data, forKey: Keys.coordinator)
        }
        if coordinator.config != config {
            // The demo admin changed the timers.
            config = coordinator.config
            persistConfig()
        }
        takeLocationFixIfNeeded()
        pushToWatch()
        Task { await sync() }
    }

    /// One fix at alert time, only if some contact may receive it.
    private func takeLocationFixIfNeeded() {
        guard let alarm = coordinator.alarm, alarm.isOpen, alarm.location == nil, locatedAlarmId != alarm.id,
              alarm.recipients.contains(where: \.shareLocation)
        else { return }
        locatedAlarmId = alarm.id
        let alarmId = alarm.id
        location.requestOneFix { [weak self] fix in
            guard let fix else { return }
            self?.coordinator.updateLocation(fix, alarmId: alarmId)
        }
    }

    // MARK: Watch

    private func handleWatch(_ action: WatchAction) -> WatchActionReply {
        guard !inOutage else {
            return WatchActionReply(actionId: action.id, result: ActionResult(ok: false, feedback: "iPhone unavailable"), display: coordinator.display(phoneAvailable: false))
        }
        let result = coordinator.handle(action)
        return WatchActionReply(actionId: action.id, result: result, display: coordinator.display(phoneAvailable: true))
    }

    func pushToWatch(force: Bool = false) {
        connectivity.push(display: coordinator.display(phoneAvailable: !inOutage), config: config.watchConfig, force: force)
    }

    // MARK: Phone-side controls (fallbacks for the Watch circle)

    func startMonitoring() {
        show(coordinator.startMonitoring())
    }

    func stopMonitoring() {
        show(coordinator.stopMonitoring())
    }

    /// "I took them" on the iPhone: the same as "Took my meds" on the Watch.
    func tookMedsFromPhone() {
        show(coordinator.recordMedsTaken())
    }

    func dismissFromPhone() {
        show(coordinator.dismiss(alarmId: coordinator.visibleAlarm?.id))
    }

    /// The confirmed iPhone help action texts both tiers and active one-hour
    /// contacts straight away, even with monitoring off.
    func requestHelpFromPhone() {
        let hasContact = !config.contacts.isEmpty || temporaryContacts.contains { $0.isEligible(at: Date()) }
        guard hasContact else {
            banner = Banner(text: "Add a contact first, so Ripple has someone to text.", ok: false)
            return
        }
        show(coordinator.requestHelpForAllContacts())
    }

    func sendTestMessage(to contact: PermanentContact) {
        guard let phone = Phone.normalize(contact.phone) else {
            testResult = "\(contact.name)'s number doesn't look right."
            return
        }
        testResult = "Opening Shortcuts…"
        sender.sendTest(to: phone, text: "Ripple test message from \(config.wearerName). No action needed.")
    }

    private func show(_ result: ActionResult) {
        banner = Banner(text: result.feedback, ok: result.ok)
    }

    // MARK: Temporary contacts

    func inviteTemporary(name: String, phone: String, shareLocation: Bool) async -> InviteTemporaryResponse? {
        guard let api else { return nil }
        pending = "Preparing invitation…"
        let invitationRunId = coordinator.runId
        defer { pending = nil }
        do {
            let response = try await api.inviteTemporary(InviteTemporaryRequest(name: name, phone: phone, shareLocation: shareLocation))
            if shareLocation { location.requestPermission() }
            await sync()
            guard coordinator.runId == invitationRunId else {
                banner = Banner(text: "The demo was reset. Create a new invitation.", ok: false)
                return nil
            }
            sender.sendInvitation(id: response.contact.id, to: response.contact.phone, text: response.invitationText)
            return response
        } catch RippleAPIError.decoding {
            banner = Banner(text: "The backend needs an update before it can send text invitations. Restart the Ripple server with the latest code, then try again.", ok: false)
            return nil
        } catch {
            banner = Banner(text: "Not created. \(describe(error))", ok: false)
            return nil
        }
    }

    func resendTemporaryInvitation(_ invitation: InviteTemporaryResponse) {
        guard temporaryContacts.first(where: { $0.id == invitation.contact.id })?.state == .invited else { return }
        sender.sendInvitation(id: invitation.contact.id, to: invitation.contact.phone, text: invitation.invitationText)
    }

    private func persistJoinReplies() {
        if let data = try? RippleJSON.encoder.encode(pendingJoinReplies) {
            UserDefaults.standard.set(data, forKey: Keys.joinReplies)
        }
    }

    /// Retain matching join commands until the backend accepts or rejects them.
    /// Only the parsed code and optional sender are saved, not the message body.
    private func processJoinReplies(using api: RippleAPI) async {
        while let reply = pendingJoinReplies.first, !inOutage {
            guard reply.runId == coordinator.runId else {
                pendingJoinReplies.removeFirst()
                persistJoinReplies()
                continue
            }
            do {
                let response = try await api.joinTemporary(reply)
                guard reply.runId == coordinator.runId else { continue }
                pendingJoinReplies.removeAll { $0 == reply }
                persistJoinReplies()
                temporaryContacts = response.contacts
                coordinator.temporaryContacts = response.contacts
                banner = Banner(text: "\(response.contact.name) is now a one-hour contact.", ok: true)
            } catch let error as RippleAPIError {
                if case .server(let status, _, _) = error, (400..<500).contains(status), status != 401, status != 429 {
                    pendingJoinReplies.removeAll { $0 == reply }
                    persistJoinReplies()
                    banner = Banner(text: "Not joined. \(describe(error))", ok: false)
                    continue
                }
                banner = Banner(text: "Join reply saved. It will be retried when the backend is available.", ok: false)
                break
            } catch {
                banner = Banner(text: "Join reply saved. It will be retried when the backend is available.", ok: false)
                break
            }
        }
    }

    func removeTemporary(_ contact: TemporaryContactView) async {
        guard let api else { return }
        pending = "Removing…"
        defer { pending = nil }
        do {
            let response = try await api.removeTemporary(id: contact.id)
            sender.cancelInvitation(id: contact.id)
            temporaryContacts = response.contacts
            coordinator.temporaryContacts = response.contacts
            banner = Banner(text: "\(contact.name) won't receive new alerts.", ok: true)
        } catch {
            banner = Banner(text: "Not removed. \(describe(error))", ok: false)
        }
    }

    // MARK: Callbacks

    /// ripple://shortcut?… is the Ripple Alert shortcut finishing.
    /// ripple://accept?text=…&from=… carries an accept or join reply,
    /// passed on by the Ripple Accept shortcut from a Messages automation.
    func handle(url: URL) {
        if sender.handle(url: url) { return }
        guard url.scheme == "ripple", url.host == "accept" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let text = items.first { $0.name == "text" }?.value ?? ""
        let from = items.first { $0.name == "from" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        acceptReply(text: text, from: from?.isEmpty == false ? from : nil)
    }

    /// Records a contact's text reply. The backend
    /// learns about it on the next sync, which stops its Tier 2 backup.
    func acceptReply(text: String, from sender: String?) {
        // A phone in simulated failure does nothing.
        guard !inOutage else { return }
        if let code = JoinCode.code(in: text) {
            guard isSetUp else {
                banner = Banner(text: "Set up Ripple before accepting an invitation reply.", ok: false)
                return
            }
            let reply = JoinTemporaryRequest(runId: coordinator.runId, code: code, from: sender)
            if !pendingJoinReplies.contains(reply) {
                pendingJoinReplies.append(reply)
                persistJoinReplies()
            }
            banner = Banner(text: "Join reply saved. Checking the invitation…", ok: true)
            Task { await sync() }
            return
        }
        let result = coordinator.acceptReply(text: text, from: sender)
        // Empty feedback means a duress alarm: show nothing.
        if !result.feedback.isEmpty {
            show(result)
        }
    }

    func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
