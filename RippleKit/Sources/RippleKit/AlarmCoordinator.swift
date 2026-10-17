import Foundation

public protocol AlarmCoordinatorDelegate: AnyObject {
    /// Hand these to the phone's messaging path (the Ripple Alert shortcut).
    func coordinator(_ coordinator: AlarmCoordinator, send messages: [OutMessage])
    /// Something changed: update the Watch, the screen and the backend mirror.
    func coordinatorDidChange(_ coordinator: AlarmCoordinator)
}

/// The alarm state machine. It runs on the wearer's iPhone, which sends every
/// message first; the backend only mirrors it and steps in as a declared
/// backup. Pure logic with an injected clock, so it is unit tested.
public final class AlarmCoordinator {
    public private(set) var monitoring = false
    /// The current alarm, or the most recent one.
    public private(set) var alarm: Alarm?
    /// Recent alarms, newest first.
    public private(set) var history: [Alarm] = []
    public private(set) var nextCheckInAt: Date?
    public private(set) var runId: String
    /// The dose time the wearer is being asked about, until "Took my meds" or
    /// the grace period runs out.
    public private(set) var pendingDoseAt: Date?
    /// The last time the wearer tapped "Took my meds".
    public private(set) var lastMedsTakenAt: Date?
    /// The latest dose time already asked about, so each dose is asked once.
    private var lastPromptedDoseAt: Date?

    public var config: RippleConfig {
        didSet { configChanged(from: oldValue) }
    }
    /// Latest list from the backend. Only active, unexpired contacts are texted.
    public var temporaryContacts: [TemporaryContactView] = []
    public var timeZone: TimeZone = .current
    public weak var delegate: AlarmCoordinatorDelegate?

    private let clock: () -> Date
    private var handled: [String: ActionResult] = [:]
    private var handledOrder: [String] = []

    public struct Snapshot: Codable {
        public var monitoring: Bool
        public var alarm: Alarm?
        public var history: [Alarm]
        public var nextCheckInAt: Date?
        public var runId: String
        // Optional, so snapshots saved before medication timing still load.
        public var pendingDoseAt: Date?
        public var lastMedsTakenAt: Date?
        public var lastPromptedDoseAt: Date?
    }

    public init(config: RippleConfig, snapshot: Snapshot? = nil, clock: @escaping () -> Date = { Date() }) {
        self.config = config
        self.clock = clock
        self.runId = snapshot?.runId ?? ""
        if let snapshot {
            monitoring = snapshot.monitoring
            alarm = snapshot.alarm
            history = snapshot.history
            nextCheckInAt = snapshot.nextCheckInAt
            pendingDoseAt = snapshot.pendingDoseAt
            lastMedsTakenAt = snapshot.lastMedsTakenAt
            lastPromptedDoseAt = snapshot.lastPromptedDoseAt
        }
    }

    public var snapshot: Snapshot {
        Snapshot(monitoring: monitoring, alarm: alarm, history: history, nextCheckInAt: nextCheckInAt, runId: runId,
                 pendingDoseAt: pendingDoseAt, lastMedsTakenAt: lastMedsTakenAt, lastPromptedDoseAt: lastPromptedDoseAt)
    }

    func now() -> Date { clock() }

    /// The open alarm the wearer can see. A duress alarm is never visible.
    public var visibleAlarm: Alarm? {
        guard let alarm, alarm.isOpen, !alarm.duress else { return nil }
        return alarm
    }

    /// The most recent alarm the wearer may see, open or closed.
    public var lastVisibleAlarm: Alarm? {
        history.first { !$0.duress }
    }

    public func setRunId(_ newRunId: String) {
        runId = newRunId
    }

    // MARK: Watch and phone actions

    /// Handles a Watch action once, even if the same tap arrives twice.
    @discardableResult
    public func handle(_ action: WatchAction) -> ActionResult {
        if let cached = handled[action.id] { return cached }
        let result: ActionResult
        switch action.kind {
        case .start: result = startMonitoring()
        case .stop: result = stopMonitoring()
        case .dismiss: result = dismiss(alarmId: action.alarmId)
        case .hold: result = hold(alarmId: action.alarmId)
        case .help: result = requestHelp()
        case .tookMeds: result = recordMedsTaken()
        }
        remember(action.id, result)
        return result
    }

    /// Runs any keyed command once (used for admin commands too).
    public func once(_ key: String, _ body: () -> ActionResult) -> ActionResult {
        if let cached = handled[key] { return cached }
        let result = body()
        remember(key, result)
        return result
    }

    private func remember(_ key: String, _ result: ActionResult) {
        handled[key] = result
        handledOrder.append(key)
        if handledOrder.count > 200 {
            handled[handledOrder.removeFirst()] = nil
        }
    }

    @discardableResult
    public func startMonitoring() -> ActionResult {
        if !monitoring {
            monitoring = true
            scheduleNextCheckIn(from: now())
            changed()
        }
        return ActionResult(ok: true, feedback: "Monitoring on")
    }

    @discardableResult
    public func stopMonitoring() -> ActionResult {
        if visibleAlarm != nil {
            return ActionResult(ok: false, feedback: "Answer the alarm first")
        }
        if monitoring {
            monitoring = false
            nextCheckInAt = nil
            pendingDoseAt = nil
            changed()
        }
        return ActionResult(ok: true, feedback: "Monitoring off")
    }

    @discardableResult
    public func startAlarm(source: AlarmSource, countdownSeconds: Int? = nil) -> ActionResult {
        guard monitoring else {
            return ActionResult(ok: false, feedback: "Monitoring is off. Start it on the Watch first.")
        }
        if let alarm, alarm.isOpen {
            return ActionResult(ok: false, feedback: "An alarm is already open.")
        }
        let countdown = max(5, countdownSeconds ?? config.countdownSeconds)
        var newAlarm = makeAlarm(source: source, countdownSeconds: countdown, at: now())
        rebuildTexts(&newAlarm)
        store(newAlarm)
        changed()
        return ActionResult(ok: true, feedback: "Alarm started")
    }

    /// The swipe-up combo. Works whether or not monitoring is on. With no
    /// alarm open it texts Tier 1 straight away; during a countdown it stops
    /// waiting; after the alert it texts Tier 2 without waiting for the
    /// acknowledge window. A stale request is still a request, so the alarm
    /// the Watch saw doesn't matter.
    @discardableResult
    public func requestHelp() -> ActionResult {
        let requested = ActionResult(ok: true, feedback: "Help requested")
        let t = now()
        guard var current = alarm, current.isOpen else {
            var newAlarm = makeAlarm(source: .help, countdownSeconds: 0, at: t)
            newAlarm.helpRequestedAt = t
            rebuildTexts(&newAlarm)
            store(newAlarm)
            sendAlert()
            return requested
        }
        if let ack = current.acknowledgment {
            // A duress alarm stays out of sight, so don't name the responder.
            return current.duress ? requested : ActionResult(ok: true, feedback: "\(ack.name) is responding")
        }
        if current.helpRequestedAt == nil {
            current.helpRequestedAt = t
            rebuildTexts(&current)
            store(current)
        }
        switch current.phase {
        case .countdown: sendAlert()
        case .alerted: sendEscalation()
        case .escalated, .closed: changed()
        }
        return requested
    }

    /// Apple Watch recorded a fall or a heart alert in Apple Health. A normal
    /// check-in: the wearer can answer it, and only no answer sends texts,
    /// which then say which Apple alert it was. An open alarm is enough, so a
    /// second alert while one is open changes nothing. During a duress alarm
    /// the feedback is empty, so nothing on screen hints that it's open.
    @discardableResult
    public func healthAlert(_ kind: HealthAlertKind) -> ActionResult {
        if let alarm, alarm.isOpen {
            return ActionResult(ok: true, feedback: alarm.duress ? "" : "Already checking in")
        }
        let result = startAlarm(source: kind.source)
        return result.ok ? ActionResult(ok: true, feedback: "\(kind.label) from Apple Watch. Checking in.") : result
    }

    /// The confirmed iPhone help action notifies both tiers immediately, using
    /// the normal alert and escalation paths so reply codes and backup agree.
    @discardableResult
    public func requestHelpForAllContacts() -> ActionResult {
        let result = requestHelp()
        if alarm?.phase == .alerted, alarm?.acknowledgment == nil {
            sendEscalation()
        }
        return result
    }

    private func makeAlarm(source: AlarmSource, countdownSeconds countdown: Int, at t: Date) -> Alarm {
        var recipients: [AlarmRecipient] = config.contacts.compactMap { contact in
            guard let phone = Phone.normalize(contact.phone) else { return nil }
            return AlarmRecipient(
                id: contact.id, name: contact.name, phone: phone, tier: contact.tier,
                shareLocation: contact.shareLocation, temporary: false,
                alertText: "", escalationText: ""
            )
        }
        // Temporary contacts join Tier 1 while active.
        for contact in temporaryContacts where contact.isEligible(at: t) {
            recipients.append(AlarmRecipient(
                id: contact.id, name: contact.name, phone: contact.phone, tier: .one,
                shareLocation: contact.shareLocation, temporary: true,
                alertText: "", escalationText: ""
            ))
        }
        // Each person gets their own reply code, so a reply also says who it's from.
        for (index, code) in ReplyCode.makeCodes(count: recipients.count).enumerated() {
            recipients[index].acceptCode = code
        }
        return Alarm(
            id: RippleID.make(bytes: 8), runId: runId, source: source, startedAt: t,
            deadline: t.addingTimeInterval(TimeInterval(countdown)), countdownSeconds: countdown,
            ackWindowSeconds: max(5, config.ackWindowSeconds), phase: .countdown, closeReason: nil, closedAt: nil,
            duress: false, alertedAt: nil, escalatedAt: nil, acknowledgment: nil, wearerName: config.wearerName,
            recipients: recipients, location: nil, messages: []
        )
    }

    /// Tap, double tap or voice. Before texts go out it cancels the alarm and
    /// keeps monitoring; after, it is "I'm okay now".
    @discardableResult
    public func dismiss(alarmId: String?) -> ActionResult {
        let dismissed = ActionResult(ok: true, feedback: "Dismissed")
        guard let current = visibleAlarm else { return dismissed }
        if let alarmId, alarmId != current.id { return dismissed }
        if current.phase == .countdown {
            close(.dismissed)
        } else {
            sendOkayNow()
            close(.okayNow)
        }
        return dismissed
    }

    /// The 2-second hold: duress. The screen shows exactly what a dismissal
    /// shows, while the alert still sends and escalation continues.
    @discardableResult
    public func hold(alarmId: String?) -> ActionResult {
        let dismissed = ActionResult(ok: true, feedback: "Dismissed")
        guard var current = alarm, current.isOpen else { return dismissed }
        if let alarmId, alarmId != current.id { return dismissed }
        if !current.duress {
            current.duress = true
            store(current)
            if current.phase == .countdown {
                sendAlert()
            }
            changed()
        }
        return dismissed
    }

    @discardableResult
    public func disableAlarm() -> ActionResult {
        guard let current = alarm, current.isOpen else {
            return ActionResult(ok: true, feedback: "No open alarm")
        }
        close(.disabled)
        return ActionResult(ok: true, feedback: "Alarm disabled")
    }

    /// Clears every pending countdown and message so nothing from the old run fires.
    public func reset(runId newRunId: String) {
        if let current = alarm, current.isOpen {
            close(.reset)
        }
        alarm = nil
        history = []
        runId = newRunId
        pendingDoseAt = nil
        if monitoring {
            scheduleNextCheckIn(from: now())
        }
        changed()
    }

    @discardableResult
    public func setTimers(countdownSeconds: Int?, ackWindowSeconds: Int?) -> ActionResult {
        var updated = config
        if let countdownSeconds { updated.countdownSeconds = min(max(countdownSeconds, 5), 600) }
        if let ackWindowSeconds { updated.ackWindowSeconds = min(max(ackWindowSeconds, 5), 1800) }
        updated.version += 1
        config = updated
        return ActionResult(ok: true, feedback: "Countdown \(updated.countdownSeconds) s, acknowledge window \(updated.ackWindowSeconds) s")
    }

    // MARK: Inputs from the system

    /// One location fix, taken when the alarm started.
    public func updateLocation(_ fix: LocationFix, alarmId: String) {
        guard var current = alarm, current.id == alarmId, current.isOpen, current.location == nil else { return }
        current.location = fix
        rebuildTexts(&current)
        store(current)
        changed()
    }

    /// Results from the Shortcuts app callback.
    public func recordResults(ids: [String], status: MessageStatus, detail: String?) {
        let wanted = Set(ids)
        guard !wanted.isEmpty else { return }
        let t = now()
        func update(_ alarm: inout Alarm) {
            for index in alarm.messages.indices where wanted.contains(alarm.messages[index].id) {
                alarm.messages[index].status = status
                alarm.messages[index].detail = detail
                alarm.messages[index].updatedAt = t
            }
        }
        if var current = alarm {
            update(&current)
            alarm = current
        }
        for index in history.indices {
            update(&history[index])
        }
        changed()
    }

    /// Marks messages as handed to the Shortcuts app.
    public func markLaunched(ids: [String]) {
        let wanted = Set(ids)
        let t = now()
        guard var current = alarm else { return }
        for index in current.messages.indices where wanted.contains(current.messages[index].id) {
            current.messages[index].launchedAt = t
            current.messages[index].updatedAt = t
        }
        store(current)
    }

    /// Current status of a message, so queued sends can be dropped if cancelled.
    public func message(_ id: String) -> OutMessage? {
        if let found = alarm?.message(id) { return found }
        for past in history {
            if let found = past.message(id) { return found }
        }
        return nil
    }

    /// What the backend knows: an acknowledgment, backup sends, or an admin close.
    public func applyFeedback(_ feedback: AlarmFeedback) {
        guard var current = alarm, current.id == feedback.alarmId else { return }
        var changedAnything = false
        for backup in feedback.backupMessages {
            if let local = current.message(backup.id) {
                // The phone's own send stands; never replace it.
                if local.path == .phone && local.mayHaveBeenSent { continue }
                if local == backup { continue }
            }
            current.upsert(backup)
            changedAnything = true
        }
        if current.isOpen {
            let backupAlerts = feedback.backupMessages.filter { $0.kind == .alert }
            if current.phase == .countdown, let first = backupAlerts.map(\.createdAt).min() {
                current.phase = .alerted
                current.alertedAt = current.alertedAt ?? first
                changedAnything = true
            }
            if current.phase != .escalated, feedback.backupMessages.contains(where: { $0.kind == .escalation }) {
                current.phase = .escalated
                current.escalatedAt = current.escalatedAt ?? now()
                changedAnything = true
            }
        }
        store(current)

        if let ack = feedback.acknowledgment {
            applyAcknowledgment(ack)
        }
        if feedback.closedByAdmin, alarm?.isOpen == true {
            close(.disabled)
        }
        if changedAnything {
            changed()
        }
    }

    /// A contact texted back "RIPPLE ACCEPT 4821". The Ripple Accept shortcut
    /// passes the reply here to record who is responding.
    ///
    /// The code must belong to someone who was texted for the open alarm. If
    /// the sender's number is known and differs from that person's number, the
    /// reply is refused, so a forwarded code can't accept for someone else.
    /// For a duress alarm the feedback is empty, so the iPhone shows nothing.
    @discardableResult
    public func acceptReply(text: String, from sender: String? = nil) -> ActionResult {
        guard let code = ReplyCode.acceptCode(in: text) else {
            return ActionResult(ok: false, feedback: "That message has no Ripple accept code.")
        }
        guard let current = alarm, current.isOpen else {
            return ActionResult(ok: false, feedback: "No alert is open, so the reply \(code) was ignored.")
        }
        guard let recipient = current.recipients.first(where: { $0.acceptCode == code }) else {
            return ActionResult(ok: false, feedback: "The reply code \(code) doesn't match the open alert.")
        }
        guard current.textedRecipientIds.contains(recipient.id) else {
            return ActionResult(ok: false, feedback: "\(recipient.name) hasn't been texted for this alert yet.")
        }
        if let sender, let senderPhone = Phone.normalize(sender), senderPhone != recipient.phone {
            return ActionResult(ok: false, feedback: "That reply came from a different number than \(recipient.name)'s.")
        }
        let quiet = current.duress
        if let existing = current.acknowledgment {
            return ActionResult(ok: true, feedback: quiet ? "" : "\(existing.name) is already responding.")
        }
        applyAcknowledgment(Acknowledgment(recipientId: recipient.id, name: recipient.name, at: now()))
        return ActionResult(ok: true, feedback: quiet ? "" : "\(recipient.name) is responding.")
    }

    /// Records a responding contact and tells others already texted.
    public func applyAcknowledgment(_ ack: Acknowledgment) {
        guard var current = alarm, current.isOpen, current.acknowledgment == nil else { return }
        current.acknowledgment = ack
        let t = now()
        var outgoing: [OutMessage] = []
        for recipientId in current.textedRecipientIds where recipientId != ack.recipientId {
            guard let recipient = current.recipients.first(where: { $0.id == recipientId }) else { continue }
            let id = OutMessage.makeId(alarmId: current.id, recipientId: recipient.id, kind: .responding)
            if current.message(id) != nil { continue }
            let message = OutMessage(
                alarmId: current.id, recipientId: recipient.id, recipientName: recipient.name, phone: recipient.phone,
                kind: .responding, text: MessageTemplates.responding(contact: ack.name, name: current.wearerName),
                status: .pending, path: .phone, createdAt: t
            )
            current.messages.append(message)
            outgoing.append(message)
        }
        store(current)
        if !outgoing.isEmpty {
            delegate?.coordinator(self, send: outgoing)
        }
        changed()
    }

    /// Call about once a second while the app runs.
    public func tick() {
        let t = now()
        tickMedication(at: t)
        if let current = alarm, current.isOpen {
            if current.phase == .countdown && t >= current.deadline {
                sendAlert()
            } else if current.phase == .alerted, current.acknowledgment == nil, let ackDeadline = current.ackDeadline, t >= ackDeadline {
                sendEscalation()
            }
        } else if monitoring, config.checkInIntervalMinutes > 0, let next = nextCheckInAt, t >= next {
            startAlarm(source: .timer)
        }
    }

    // MARK: Medication

    /// "Took my meds", from the Watch or the iPhone. Clears the dose being
    /// asked about. Never starts or ends an alarm.
    @discardableResult
    public func recordMedsTaken() -> ActionResult {
        lastMedsTakenAt = now()
        pendingDoseAt = nil
        changed()
        return ActionResult(ok: true, feedback: "Meds recorded")
    }

    /// The next usual dose time after now, for "Next dose" on the iPhone.
    public var nextDoseAt: Date? {
        doseTimes(around: now()).filter { $0 > now() }.min()
    }

    /// While monitoring: ask about each dose once, at its time. If "Took my
    /// meds" doesn't come within the grace period, start a normal check-in.
    /// A dose that passed more than a grace period ago (the app was closed)
    /// is skipped quietly rather than asked about late.
    private func tickMedication(at t: Date) {
        guard monitoring, !config.medicationTimes.isEmpty else { return }
        let grace = TimeInterval(max(1, config.medicationGraceMinutes) * 60)
        if let latest = doseTimes(around: t).filter({ $0 <= t }).max(), latest != lastPromptedDoseAt {
            lastPromptedDoseAt = latest
            if t.timeIntervalSince(latest) < grace {
                pendingDoseAt = latest
            }
            changed()
        }
        if let dose = pendingDoseAt, t >= dose.addingTimeInterval(grace), visibleAlarm == nil, alarm?.isOpen != true {
            pendingDoseAt = nil
            startAlarm(source: .timer)
        }
    }

    /// Every dose time yesterday, today and tomorrow, in the wearer's time zone.
    private func doseTimes(around t: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: t)
        return [-1, 0, 1].flatMap { offset -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return config.medicationTimes.compactMap {
                calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day)
            }
        }
    }

    // MARK: Display

    /// What the Watch circle shows. A duress alarm is never shown.
    public func display(phoneAvailable: Bool = true) -> WatchDisplay {
        let t = now()
        if let current = visibleAlarm {
            if current.phase == .countdown {
                return WatchDisplay(mode: .checkIn, circleLabel: "I'm okay", status: current.source.checkInStatus, alarmId: current.id,
                                    deadline: current.deadline, phoneAvailable: phoneAvailable, updatedAt: t)
            }
            if let ack = current.acknowledgment {
                return WatchDisplay(mode: .responding, circleLabel: "I'm okay now", status: "\(ack.name) is responding",
                                    alarmId: current.id, deadline: nil, phoneAvailable: phoneAvailable, updatedAt: t)
            }
            let status = current.helpRequestedAt == nil ? "Alert sent" : "Help requested"
            return WatchDisplay(mode: .alertSent, circleLabel: "I'm okay now", status: status, alarmId: current.id,
                                deadline: nil, phoneAvailable: phoneAvailable, updatedAt: t)
        }
        if monitoring {
            if let dose = pendingDoseAt {
                return WatchDisplay(mode: .monitoring, circleLabel: "Took my meds", status: "Time for your meds", alarmId: nil,
                                    deadline: nil, phoneAvailable: phoneAvailable, updatedAt: t, medsDueAt: dose)
            }
            return WatchDisplay(mode: .monitoring, circleLabel: "Stop", status: "Monitoring", alarmId: nil,
                                deadline: nil, phoneAvailable: phoneAvailable, updatedAt: t)
        }
        return WatchDisplay(mode: .off, circleLabel: "Start", status: "Off", alarmId: nil, deadline: nil,
                            phoneAvailable: phoneAvailable, updatedAt: t)
    }

    // MARK: Sending

    func isEligible(_ recipient: AlarmRecipient) -> Bool {
        guard recipient.temporary else { return true }
        return temporaryContacts.first { $0.id == recipient.id }?.isEligible(at: now()) == true
    }

    func sendAlert() {
        guard var current = alarm, current.isOpen else { return }
        let t = now()
        if current.alertedAt == nil { current.alertedAt = t }
        var outgoing: [OutMessage] = []
        for recipient in RecipientRules.alertRecipients(current, isEligible: { self.isEligible($0) }) {
            let id = OutMessage.makeId(alarmId: current.id, recipientId: recipient.id, kind: .alert)
            if current.message(id) != nil { continue }
            let message = OutMessage(
                alarmId: current.id, recipientId: recipient.id, recipientName: recipient.name, phone: recipient.phone,
                kind: .alert, text: recipient.alertText, status: .pending, path: .phone, createdAt: t
            )
            current.messages.append(message)
            outgoing.append(message)
        }
        current.phase = .alerted
        // When Tier 1 was empty, Tier 2 already got the alert; there is nobody left to escalate to.
        if RecipientRules.escalationRecipients(current, isEligible: { self.isEligible($0) }).isEmpty {
            current.phase = .escalated
            current.escalatedAt = current.escalatedAt ?? t
        }
        store(current)
        if !outgoing.isEmpty {
            delegate?.coordinator(self, send: outgoing)
        }
        changed()
    }

    func sendEscalation() {
        guard var current = alarm, current.isOpen, current.acknowledgment == nil else { return }
        let t = now()
        var outgoing: [OutMessage] = []
        for recipient in RecipientRules.escalationRecipients(current, isEligible: { self.isEligible($0) }) {
            let id = OutMessage.makeId(alarmId: current.id, recipientId: recipient.id, kind: .escalation)
            if current.message(id) != nil { continue }
            let message = OutMessage(
                alarmId: current.id, recipientId: recipient.id, recipientName: recipient.name, phone: recipient.phone,
                kind: .escalation, text: recipient.escalationText, status: .pending, path: .phone, createdAt: t
            )
            current.messages.append(message)
            outgoing.append(message)
        }
        current.phase = .escalated
        current.escalatedAt = t
        store(current)
        if !outgoing.isEmpty {
            delegate?.coordinator(self, send: outgoing)
        }
        changed()
    }

    /// Texts "okay now" to everyone already texted and stops what hasn't gone out.
    func sendOkayNow() {
        guard var current = alarm, current.isOpen else { return }
        let t = now()
        for index in current.messages.indices where current.messages[index].isCancellable {
            current.messages[index].status = .cancelled
            current.messages[index].detail = "Stopped: the wearer is okay"
            current.messages[index].updatedAt = t
        }
        var outgoing: [OutMessage] = []
        let text = MessageTemplates.okayNow(name: current.wearerName, time: MessageTemplates.clockTime(t, timeZone: timeZone))
        for recipientId in current.textedRecipientIds {
            guard let recipient = current.recipients.first(where: { $0.id == recipientId }) else { continue }
            let id = OutMessage.makeId(alarmId: current.id, recipientId: recipient.id, kind: .okayNow)
            if current.message(id) != nil { continue }
            let message = OutMessage(
                alarmId: current.id, recipientId: recipient.id, recipientName: recipient.name, phone: recipient.phone,
                kind: .okayNow, text: text, status: .pending, path: .phone, createdAt: t
            )
            current.messages.append(message)
            outgoing.append(message)
        }
        store(current)
        if !outgoing.isEmpty {
            delegate?.coordinator(self, send: outgoing)
        }
    }

    func close(_ reason: CloseReason) {
        guard var current = alarm, current.isOpen else { return }
        let t = now()
        for index in current.messages.indices where current.messages[index].isCancellable && current.messages[index].kind != .okayNow {
            current.messages[index].status = .cancelled
            current.messages[index].detail = "Stopped: alarm closed"
            current.messages[index].updatedAt = t
        }
        current.phase = .closed
        current.closeReason = reason
        current.closedAt = t
        store(current)
        if monitoring {
            scheduleNextCheckIn(from: t)
        }
        changed()
    }

    // MARK: Helpers

    func rebuildTexts(_ alarm: inout Alarm) {
        let time = MessageTemplates.clockTime(alarm.startedAt, timeZone: timeZone)
        let helpTime = alarm.helpRequestedAt.map { MessageTemplates.clockTime($0, timeZone: timeZone) }
        let note = config.helpCard.trimmingCharacters(in: .whitespacesAndNewlines)
        let helpCard: String? = config.helpCardEnabled && !note.isEmpty ? note : nil
        for index in alarm.recipients.indices {
            let recipient = alarm.recipients[index]
            let location = recipient.shareLocation ? alarm.location?.mapURL : nil
            let code = recipient.acceptCode
            if let helpTime {
                alarm.recipients[index].alertText = MessageTemplates.help(
                    name: alarm.wearerName, time: helpTime, locationURL: location, helpCard: helpCard, acceptCode: code
                )
                alarm.recipients[index].escalationText = MessageTemplates.helpEscalation(
                    name: alarm.wearerName, time: helpTime, locationURL: location, acceptCode: code
                )
                continue
            }
            alarm.recipients[index].alertText = MessageTemplates.alert(
                name: alarm.wearerName, checkInTime: time, locationURL: location, helpCard: helpCard, acceptCode: code,
                reason: alarm.source.alertReason
            )
            alarm.recipients[index].escalationText = MessageTemplates.escalation(
                name: alarm.wearerName, checkInTime: time, locationURL: location, acceptCode: code,
                reason: alarm.source.alertReason
            )
        }
    }

    private func store(_ updated: Alarm) {
        alarm = updated
        if let index = history.firstIndex(where: { $0.id == updated.id }) {
            history[index] = updated
        } else {
            history.insert(updated, at: 0)
        }
        if history.count > 10 {
            history.removeLast(history.count - 10)
        }
    }

    private func scheduleNextCheckIn(from date: Date) {
        if config.checkInIntervalMinutes > 0 {
            nextCheckInAt = date.addingTimeInterval(TimeInterval(config.checkInIntervalMinutes * 60))
        } else {
            nextCheckInAt = nil
        }
    }

    private func configChanged(from old: RippleConfig) {
        if old.checkInIntervalMinutes != config.checkInIntervalMinutes && monitoring && visibleAlarm == nil {
            scheduleNextCheckIn(from: now())
        }
        changed()
    }

    private func changed() {
        delegate?.coordinatorDidChange(self)
    }
}
