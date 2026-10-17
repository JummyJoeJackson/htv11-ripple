import Foundation
import KazeKit
import Observation
import UIKit

struct Banner: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var ok: Bool
}

enum ServerConnection: Equatable {
    case unknown
    case online
    case offline(String)

    var isOnline: Bool { self == .online }

    var offlineReason: String? {
        if case .offline(let reason) = self { return reason }
        return nil
    }
}

/// The wearer app's state. Polls the backend once a second, sends heartbeats,
/// and relays commands from the watch. Nothing is shown as confirmed until
/// the backend accepts it.
@MainActor
@Observable
final class WearerStore {
    private(set) var serverAddress: String
    private(set) var deviceToken: String?
    private(set) var state: WearerState?
    private(set) var connection: ServerConnection = .unknown
    /// Text for the command currently in flight, such as "Starting session…".
    private(set) var pending: String?
    var banner: Banner?
    private(set) var serverOffset: TimeInterval = 0

    let connectivity = PhoneConnectivity()
    let location = LocationProvider()
    @ObservationIgnored private var api: KazeAPI?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

    private enum Keys {
        static let server = "kaze.serverAddress"
        static let token = "kaze.deviceToken"
    }

    var isSetUp: Bool { deviceToken != nil }

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        deviceToken = UserDefaults.standard.string(forKey: Keys.token)
        rebuildAPI()
        connectivity.onCommand = { [weak self] command, reply in
            Task { @MainActor in
                guard let self else {
                    reply(WatchCommandReply(id: command.id, ok: false, message: "The iPhone app isn't ready."))
                    return
                }
                reply(await self.handleWatch(command))
            }
        }
        connectivity.onReachable = { [weak self] in
            Task { @MainActor in self?.pushToWatch(force: true) }
        }
    }

    private func rebuildAPI() {
        if let token = deviceToken, let url = KazeAPI.normalizedURL(from: serverAddress) {
            api = KazeAPI(baseURL: url, token: token)
        } else {
            api = nil
        }
    }

    // MARK: Setup

    func setUp(serverAddress address: String, name: String) async -> Bool {
        guard let url = KazeAPI.normalizedURL(from: address) else {
            banner = Banner(text: "Enter the server address printed in the server console, like 192.168.1.20:8080.", ok: false)
            return false
        }
        pending = "Connecting…"
        defer { pending = nil }
        do {
            let response = try await KazeAPI(baseURL: url, token: nil).setup(SetupRequest(displayName: name))
            serverAddress = url.absoluteString
            deviceToken = response.deviceToken
            UserDefaults.standard.set(serverAddress, forKey: Keys.server)
            UserDefaults.standard.set(response.deviceToken, forKey: Keys.token)
            rebuildAPI()
            banner = nil
            await refresh()
            start()
            return true
        } catch {
            banner = Banner(text: describe(error), ok: false)
            return false
        }
    }

    /// Removes this iPhone's registration so it can be set up again.
    func forgetDevice() {
        pollTask?.cancel()
        heartbeatTask?.cancel()
        pollTask = nil
        heartbeatTask = nil
        deviceToken = nil
        state = nil
        connection = .unknown
        UserDefaults.standard.removeObject(forKey: Keys.token)
        rebuildAPI()
        UIApplication.shared.isIdleTimerDisabled = false
        location.setActive(false)
        pushToWatch(force: true)
    }

    // MARK: Loops

    func start() {
        guard isSetUp else {
            pushToWatch(force: true)
            return
        }
        if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        if heartbeatTask == nil {
            heartbeatTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.sendHeartbeat()
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    func refresh() async {
        guard let api else { return }
        do {
            let fresh = try await api.wearerState()
            apply(fresh)
            connection = .online
        } catch let error as KazeAPIError where error.isUnauthorized {
            connection = .offline("The server doesn't recognize this iPhone. Use Settings → Set up again.")
        } catch {
            connection = .offline(describe(error))
        }
        pushToWatch()
    }

    private func apply(_ fresh: WearerState) {
        serverOffset = fresh.serverTime.timeIntervalSince(Date())
        state = fresh
        let monitoring = fresh.session?.monitoring == .active
        // Keep the screen on during a session so polling and heartbeats keep running.
        UIApplication.shared.isIdleTimerDisabled = monitoring
        location.setActive(monitoring)
    }

    private func sendHeartbeat() async {
        guard let api, state?.session?.monitoring == .active else { return }
        let body = HeartbeatRequest(
            watchReachable: connectivity.isReachable,
            lastWatchContactAt: connectivity.lastContact,
            location: location.lastFix
        )
        do {
            _ = try await api.heartbeat(body)
        } catch {
            connection = .offline(describe(error))
        }
    }

    // MARK: Commands

    /// Runs a backend command, shows it as pending, and reports whether the
    /// backend confirmed it.
    @discardableResult
    func perform(_ pendingText: String, success: String, _ action: @escaping (KazeAPI) async throws -> WearerState?) async -> Bool {
        guard let api else {
            banner = Banner(text: "Set up KAZE first.", ok: false)
            return false
        }
        pending = pendingText
        defer { pending = nil }
        do {
            if let fresh = try await action(api) {
                apply(fresh)
            }
            banner = Banner(text: success, ok: true)
            await refresh()
            return true
        } catch {
            banner = Banner(text: "Not confirmed. \(describe(error))", ok: false)
            await refresh()
            return false
        }
    }

    func startSession(venue: String, durationSeconds: Int) async -> Bool {
        await perform("Starting session…", success: "Session started. The backend has your deadline.") { api in
            try await api.startSession(StartSessionRequest(venue: venue, durationSeconds: durationSeconds))
        }
    }

    func extendSession(by seconds: Int) async -> Bool {
        await perform("Extending…", success: "Session extended.") { api in
            try await api.extendSession(ExtendSessionRequest(additionalSeconds: seconds))
        }
    }

    func endSession() async -> Bool {
        await perform("Ending session…", success: "Session ended.") { api in
            try await api.endSession()
        }
    }

    func confirmFromPhone() async -> Bool {
        let checkInId = state?.checkIn?.state == .awaitingResponse ? state?.checkIn?.id : nil
        return await perform("Sending I'm okay…", success: "Checked in.") { api in
            _ = try await api.confirm(ConfirmRequest(checkInId: checkInId, source: .phone))
            return nil
        }
    }

    func helpFromPhone() async -> Bool {
        await perform("Requesting help…", success: "Help requested. Contacting your responders.") { api in
            _ = try await api.help(HelpRequest(source: .phone))
            return nil
        }
    }

    /// Same call and same result screen for the safety PIN and the duress PIN.
    func cancelWithPin(_ pin: String) async -> Bool {
        await perform("Checking PIN…", success: "Cancelled.") { api in
            _ = try await api.cancel(CancelRequest(pin: pin))
            return nil
        }
    }

    func saveConfig(_ request: ConfigRequest) async -> Bool {
        await perform("Saving…", success: "Settings saved.") { api in
            try await api.updateConfig(request)
        }
    }

    func saveContacts(_ contacts: [ContactInput]) async -> Bool {
        await perform("Saving contacts…", success: "Trusted contacts saved.") { api in
            try await api.replaceContacts(ContactsRequest(contacts: contacts))
        }
    }

    func savePins(safety: String, duress: String) async -> Bool {
        await perform("Saving PINs…", success: "PINs saved.") { api in
            try await api.setPins(PinsRequest(safetyPin: safety, duressPin: duress))
        }
    }

    func inviteHelper(_ request: InviteHelperRequest) async -> InviteHelperResponse? {
        guard let api else { return nil }
        pending = "Creating invitation…"
        defer { pending = nil }
        do {
            let response = try await api.inviteHelper(request)
            banner = Banner(text: "Invitation created. Coverage isn't active until the helper verifies and accepts.", ok: true)
            await refresh()
            return response
        } catch {
            banner = Banner(text: "Not confirmed. \(describe(error))", ok: false)
            return nil
        }
    }

    func revokeCoverage(id: String) async -> Bool {
        await perform("Revoking…", success: "Helper access revoked.") { api in
            try await api.revokeCoverage(id: id)
        }
    }

    // MARK: Watch

    private func handleWatch(_ command: WatchCommand) async -> WatchCommandReply {
        guard let api else {
            return WatchCommandReply(id: command.id, ok: false, message: "Set up KAZE on your iPhone first.")
        }
        do {
            let message: String
            switch command.kind {
            case .confirm:
                message = try await api.confirm(ConfirmRequest(checkInId: command.checkInId, source: .watch), key: command.id).message
            case .help:
                message = try await api.help(HelpRequest(source: .watch), key: command.id).message
            }
            await refresh()
            return WatchCommandReply(id: command.id, ok: true, message: message)
        } catch {
            await refresh()
            return WatchCommandReply(id: command.id, ok: false, message: "Not confirmed. \(describe(error))")
        }
    }

    func makeWatchState() -> WatchState {
        guard isSetUp, let state else {
            var notReady = WatchState.notSetUp
            notReady.phoneOnline = connection.isOnline
            if isSetUp {
                notReady.headline = "Connecting…"
                notReady.detail = "Your iPhone is reaching the KAZE server."
            }
            notReady.updatedAt = Date()
            return notReady
        }
        let awaiting = state.checkIn?.state == .awaitingResponse ? state.checkIn : nil
        var responderLine: String?
        if let incident = state.incident, let name = incident.responderName {
            responderLine = incident.progress == .assistanceArranged ? "\(name) is arranging help" : "\(name) acknowledged"
        }
        return WatchState(
            tone: state.tone,
            headline: state.headline,
            detail: state.detail,
            sessionActive: state.session?.monitoring == .active,
            checkInId: awaiting?.id,
            respondBy: awaiting?.respondBy,
            serverOffset: serverOffset,
            responderLine: responderLine,
            phoneOnline: connection.isOnline,
            updatedAt: Date()
        )
    }

    func pushToWatch(force: Bool = false) {
        connectivity.push(makeWatchState(), force: force)
    }

    // MARK: Helpers

    func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
