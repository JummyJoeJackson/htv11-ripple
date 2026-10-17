import Foundation
import Observation
import RippleKit
import WatchKit

struct WatchFeedback: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let ok: Bool
}

/// Watch state: the circle display from the iPhone, the last configuration
/// received (kept across launches), and actions in flight. Countdown and
/// haptics are display only.
@MainActor
@Observable
final class WatchStore {
    /// App Intents and the visible app must share one connection and matcher.
    static let shared = WatchStore()

    private(set) var display: WatchDisplay
    private(set) var config: WatchConfig
    private(set) var phoneReachable = false
    private(set) var sending = false
    var feedback: WatchFeedback?
    /// Monitoring on: a tap shows "Hold to stop." and nothing else.
    var showHoldHint = false
    var confirmStop = false
    /// The microphone is listening for the voice phrase.
    private(set) var listening = false
    /// What the iPhone heard while listening.
    private(set) var heardText = ""
    private(set) var handGestureCount = 0
    private(set) var lastHandGesture: String?
    private(set) var handGestureStatus = ""
    /// A walk session is on: a stop in steps starts a check-in.
    private(set) var walking = false
    /// Steps since the walk session started.
    private(set) var walkSteps = 0
    /// When the wearer last stepped, once they've walked enough for a stop to count.
    private(set) var walkStillSince: Date?

    private let link = WatchLink()
    @ObservationIgnored private let microphone = WatchMicrophone()
    @ObservationIgnored private let runtime = WatchRuntime()
    @ObservationIgnored private let pedometer = WatchPedometer()
    @ObservationIgnored private var walkMonitor = WalkMonitor(stopAfter: TimeInterval(RippleConfig.defaultWalkStopSeconds))
    /// Steps stopped and the iPhone hasn't opened a check-in yet.
    @ObservationIgnored private var walkCheckInPending = false
    @ObservationIgnored private var hapticTask: Task<Void, Never>?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pendingActionId: String?
    @ObservationIgnored private var pendingCompletion: ((WatchActionReply?) -> Void)?
    @ObservationIgnored private var combos = ComboRecognizer()
    @ObservationIgnored private var handGestures = HandGestureRecognizer(preset: .pinchClench)
    @ObservationIgnored private var handGestureExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var voiceSessionId: String?
    @ObservationIgnored private var micHeldUntil = Date.distantPast
    /// The alarm the iPhone said it can't listen for. The dictation button takes over.
    @ObservationIgnored private var voiceOffForAlarm: String?

    private enum Keys {
        static let config = "ripple.watch.config"
        static let display = "ripple.watch.display"
        static let gestureCount = "ripple.watch.handGestureCount"
        static let lastGesture = "ripple.watch.lastHandGesture"
    }

    private init() {
        let defaults = UserDefaults.standard
        config = defaults.data(forKey: Keys.config).flatMap { try? RippleJSON.decoder.decode(WatchConfig.self, from: $0) } ?? .fallback
        display = defaults.data(forKey: Keys.display).flatMap { try? RippleJSON.decoder.decode(WatchDisplay.self, from: $0) } ?? .off
        handGestures.select(config.handGesturePreset)
        handGestureCount = defaults.integer(forKey: Keys.gestureCount)
        lastHandGesture = defaults.string(forKey: Keys.lastGesture)
        link.onDisplay = { [weak self] display in
            self?.apply(display)
        }
        link.onConfig = { [weak self] config in
            self?.store(config)
        }
        link.onReachability = { [weak self] reachable in
            self?.phoneReachable = reachable
        }
        link.onHeard = { [weak self] heard in
            self?.heard(heard)
        }
        microphone.onChunk = { [weak self] audio in
            guard let self, let session = self.voiceSessionId else { return }
            self.link.sendVoiceAudio(session: session, audio: audio)
        }
        pedometer.onSteps = { [weak self] steps, time in
            self?.stepsCounted(steps, at: time)
        }
        pedometer.onProblem = { [weak self] problem in
            self?.walkProblem(problem)
        }
        if config.voiceEnabled { WatchMicrophone.requestPermission() }
        link.activate()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.link.ping()
                if let self {
                    self.phoneReachable = self.link.isReachable
                    if self.config.version > 0 { self.link.acknowledgeConfig(self.config.version) }
                    self.refreshRuntime()
                    self.checkWalk()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    // MARK: Incoming

    private func apply(_ newDisplay: WatchDisplay) {
        if newDisplay.alarmId != display.alarmId || newDisplay.mode != display.mode {
            resetHandGestures()
        }
        let previousAlarm = display.mode == .checkIn ? display.alarmId : nil
        let wasAlarm = display.mode.isAlarm
        display = newDisplay
        if let data = try? RippleJSON.encoder.encode(newDisplay) {
            UserDefaults.standard.set(data, forKey: Keys.display)
        }
        if newDisplay.mode == .checkIn, newDisplay.alarmId != previousAlarm {
            startAlarmHaptics(deadline: newDisplay.deadline)
        }
        if newDisplay.mode != .checkIn {
            stopHaptics()
        }
        if !newDisplay.mode.isAlarm {
            confirmStop = false
        }
        if newDisplay.mode.isAlarm {
            // The check-in is open, whatever started it.
            walkCheckInPending = false
        } else if wasAlarm {
            // The wearer just answered, so stopping to do it doesn't count.
            walkMonitor.waitForWalking()
            updateWalkStatus()
        }
        if newDisplay.mode == .off && walking {
            endWalk()
        }
        refreshRuntime()
    }

    /// Keeps the last configuration it received and confirms it to the iPhone.
    private func store(_ newConfig: WatchConfig) {
        guard newConfig.version >= config.version else { return }
        if newConfig.handGesturesEnabled != config.handGesturesEnabled
            || newConfig.handGesturePreset != config.handGesturePreset {
            resetHandGestures()
            handGestures.select(newConfig.handGesturePreset)
        }
        config = newConfig
        if let data = try? RippleJSON.encoder.encode(newConfig) {
            UserDefaults.standard.set(data, forKey: Keys.config)
        }
        link.acknowledgeConfig(newConfig.version)
        if newConfig.voiceEnabled { WatchMicrophone.requestPermission() }
        updateListening()
        walkMonitor.stopAfter = TimeInterval(newConfig.walkStopSeconds)
        if !newConfig.walkEnabled && walking {
            endWalk()
        }
    }

    // MARK: Circle

    func tapCircle(method: DismissMethod = .touch) {
        switch display.mode {
        case .off:
            send(.start)
        case .monitoring:
            showHoldHint = true
        case .checkIn, .alertSent, .responding:
            send(.dismiss, method: method)
        }
    }

    func holdCircle() {
        switch display.mode {
        case .off:
            send(.start)
        case .monitoring:
            confirmStop = true
        case .checkIn, .alertSent, .responding:
            // Duress. Shows exactly what a dismissal shows.
            send(.hold)
        }
    }

    func confirmStopMonitoring() {
        confirmStop = false
        send(.stop)
    }

    /// From the dictation button. The voice phrase is a dismissal, never duress.
    func voiceInput(_ text: String) {
        guard config.voiceEnabled, display.mode.isAlarm else { return }
        if VoicePhrase.matches(text, phrase: config.voicePhrase) {
            send(.dismiss, method: .voice)
        } else {
            feedback = WatchFeedback(text: "Didn't catch that. Tap the circle instead.", ok: false)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    // MARK: Walk session

    /// From the button under the circle while monitoring. During a walk, if
    /// the wearer was walking and their steps stop for the set time, the
    /// iPhone starts a normal check-in. It doesn't detect falls or freezes.
    func toggleWalk() {
        if walking {
            endWalk()
            feedback = WatchFeedback(text: "Walk ended", ok: true)
            WKInterfaceDevice.current().play(.stop)
        } else {
            startWalk()
        }
    }

    private func startWalk() {
        guard config.walkEnabled, display.mode == .monitoring else { return }
        if let problem = WatchPedometer.problem {
            walkProblem(problem)
            return
        }
        walkMonitor = WalkMonitor(stopAfter: TimeInterval(config.walkStopSeconds))
        walkSteps = 0
        walkCheckInPending = false
        walking = true
        pedometer.start(from: Date())
        feedback = WatchFeedback(text: "Walk started", ok: true)
        WKInterfaceDevice.current().play(.start)
    }

    private func endWalk() {
        pedometer.stop()
        walking = false
        walkSteps = 0
        walkCheckInPending = false
        walkStillSince = nil
    }

    /// From live updates and from the direct query; the larger total wins.
    private func stepsCounted(_ steps: Int, at time: Date) {
        guard walking else { return }
        walkMonitor.update(totalSteps: steps, at: time)
        walkSteps = walkMonitor.steps
        updateWalkStatus()
    }

    private func updateWalkStatus() {
        walkStillSince = walking && walkMonitor.armed ? walkMonitor.lastStepAt : nil
    }

    private func walkProblem(_ problem: String) {
        if walking { endWalk() }
        feedback = WatchFeedback(text: problem, ok: false)
        WKInterfaceDevice.current().play(.failure)
    }

    /// Runs with every ping. Asks the iPhone again until a check-in is open,
    /// since it may be briefly out of reach when the steps stop.
    private func checkWalk() {
        guard walking else { return }
        pedometer.refresh()
        // During an alarm the wearer is already being asked.
        guard display.mode == .monitoring else { return }
        if walkMonitor.checkStopped(at: Date()) {
            walkCheckInPending = true
            updateWalkStatus()
        }
        guard walkCheckInPending, link.isReachable, display.phoneAvailable, !sending else { return }
        send(.walkStopped)
    }

    // MARK: Staying awake

    /// Keeps the app running with the screen off while monitoring, and the
    /// microphone listening during an alarm. Without this the app is suspended
    /// when the screen dims and the iPhone can't reach it. Safe to call often;
    /// it restarts whatever the system stopped.
    func refreshRuntime() {
        if display.mode == .off {
            runtime.stop()
        } else {
            runtime.start()
        }
        updateListening()
    }

    // MARK: Listening

    /// While an alarm is open, the microphone listens for the voice phrase, so
    /// nothing has to be pressed. The iPhone does the recognition, since
    /// watchOS has none.
    private func updateListening() {
        let wanted = config.voiceEnabled
            && display.mode.isAlarm
            && display.phoneAvailable
            && voiceOffForAlarm != display.alarmId
            && WatchMicrophone.allowed
        guard wanted else {
            if listening { stopListening() }
            return
        }
        if Date() < micHeldUntil {
            // Paused for an alarm buzz. Still shown as listening, and the iPhone keeps the session.
            if microphone.isRecording { microphone.stop() }
            beginListening()
            return
        }
        // Also restarts a microphone the system stopped.
        guard !microphone.isRunning else { return }
        if microphone.start() {
            beginListening()
        } else if listening {
            // Not available right now, for example in the background. Retried on the next ping.
            stopListening()
        }
    }

    private func beginListening() {
        if voiceSessionId == nil { voiceSessionId = RippleID.make(bytes: 8) }
        listening = true
    }

    private func stopListening() {
        microphone.stop()
        if let session = voiceSessionId { link.stopVoice(session: session) }
        voiceSessionId = nil
        listening = false
        heardText = ""
    }

    /// Haptics may not play while the microphone records, so it pauses for the alarm buzzes.
    private func holdMic(seconds: Double) {
        micHeldUntil = max(micHeldUntil, Date().addingTimeInterval(seconds))
        updateListening()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.updateListening()
        }
    }

    /// Anything heard that contains the phrase dismisses, like a tap. Never duress.
    private func heard(_ heard: VoiceHeard) {
        guard listening, heard.sessionId == voiceSessionId else { return }
        if let problem = heard.problem {
            voiceOffForAlarm = display.alarmId
            stopListening()
            feedback = WatchFeedback(text: problem, ok: false)
            return
        }
        heardText = heard.text
        let guesses = [heard.text] + heard.alternatives
        guard display.mode.isAlarm, guesses.contains(where: { VoicePhrase.matches($0, phrase: config.voicePhrase) }) else { return }
        // Stopped so the same words can't send twice. If the dismissal fails, listening restarts.
        stopListening()
        send(.dismiss, method: .voice)
    }

    // MARK: Swipe combos

    /// A vertical swipe on the circle. Up twice asks for help; down twice is
    /// "I'm okay". It takes two swipes, so one shaky movement can't do either.
    func swipe(_ step: GestureStep) {
        guard config.combosEnabled else { return }
        switch combos.record(step) {
        case .idle:
            break
        case .partial(.help):
            hint("Swipe up again to get help", haptic: .directionUp)
        case .partial(.okay):
            if display.mode.isAlarm { hint("Swipe down again if you're okay", haptic: .directionDown) }
        case .matched(.help):
            requestHelp()
        case .matched(.okay):
            if display.mode.isAlarm {
                send(.dismiss, method: .combo)
            } else {
                feedback = WatchFeedback(text: "No alarm to answer.", ok: true)
            }
        }
    }

    /// From the swipe combo or the VoiceOver action. Works in every state and
    /// is never duress.
    func requestHelp() {
        send(.help, method: .combo)
    }

    private func hint(_ text: String, haptic: WKHapticType) {
        feedback = WatchFeedback(text: text, ok: true)
        WKInterfaceDevice.current().play(haptic)
    }

    // MARK: AssistiveTouch shortcut inputs

    /// Called by each background intent. Every input leaves a local receipt,
    /// including when there is no alarm, so setup can be tested harmlessly.
    /// Only a complete selected sequence can enter the existing dismissal path.
    func receiveHandGesture(_ step: HandGestureStep, at time: Date = Date()) async {
        handGestureCount += 1
        lastHandGesture = step.label
        UserDefaults.standard.set(handGestureCount, forKey: Keys.gestureCount)
        UserDefaults.standard.set(step.label, forKey: Keys.lastGesture)

        guard config.handGesturesEnabled else {
            resetHandGestures(status: "Hand gestures are off")
            return
        }
        guard display.mode.isAlarm, display.alarmId != nil else {
            resetHandGestures(status: "No alarm; input recorded")
            return
        }
        guard !sending else {
            handGestureStatus = "Action already pending"
            return
        }

        switch handGestures.record(step, at: time) {
        case .idle:
            // Idle includes a suppressed duplicate after a completed sequence.
            // Preserve the recognizer's bounce history across repeated deliveries.
            handGestureExpiryTask?.cancel()
            handGestureExpiryTask = nil
            handGestureStatus = "Start: \(config.handGesturePreset.steps[0].label)"
        case .partial:
            handGestureStatus = "Next: \(config.handGesturePreset.steps[1].label)"
            expireHandGestures()
        case .matched:
            handGestureExpiryTask?.cancel()
            handGestureStatus = "Matched; confirming…"
            // Await the reply (or the existing timeout) before the intent returns,
            // so watchOS doesn't suspend the useful work after an early result.
            await withCheckedContinuation { continuation in
                send(.dismiss, method: .combo) { [weak self] reply in
                    self?.handGestureStatus = reply?.result.feedback ?? "Not confirmed; check iPhone"
                    continuation.resume()
                }
            }
        }
    }

    private func expireHandGestures() {
        handGestureExpiryTask?.cancel()
        guard let deadline = handGestures.expiresAt else { return }
        let delay = max(0, deadline.timeIntervalSinceNow)
        handGestureExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resetHandGestures(status: "Sequence timed out")
        }
    }

    private func resetHandGestures(status: String = "") {
        handGestureExpiryTask?.cancel()
        handGestureExpiryTask = nil
        handGestures.reset()
        handGestureStatus = status
    }

    private func send(_ kind: WatchActionKind, method: DismissMethod = .touch,
                      completion: ((WatchActionReply?) -> Void)? = nil) {
        guard !sending else {
            completion?(nil)
            return
        }
        guard link.isReachable, display.phoneAvailable else {
            feedback = WatchFeedback(text: "Not sent. iPhone isn't available.", ok: false)
            WKInterfaceDevice.current().play(.failure)
            completion?(nil)
            return
        }
        let action = WatchAction(kind: kind, method: method, alarmId: display.alarmId)
        pendingActionId = action.id
        pendingCompletion = completion
        sending = true
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(action.id, reply: nil)
        }
        link.send(action) { [weak self] reply in
            self?.finish(action.id, reply: reply)
        }
    }

    private func finish(_ actionId: String, reply: WatchActionReply?) {
        guard pendingActionId == actionId else { return }
        let completion = pendingCompletion
        pendingCompletion = nil
        defer { completion?(reply) }
        pendingActionId = nil
        sending = false
        timeoutTask?.cancel()
        guard let reply else {
            feedback = WatchFeedback(text: "Not confirmed. Check your iPhone.", ok: false)
            WKInterfaceDevice.current().play(.failure)
            return
        }
        apply(reply.display)
        feedback = WatchFeedback(text: reply.result.feedback, ok: reply.result.ok)
        WKInterfaceDevice.current().play(reply.result.ok ? .success : .failure)
    }

    // MARK: Haptics

    /// A strong haptic when the alarm starts, repeated at 10 seconds left.
    private func startAlarmHaptics(deadline: Date?) {
        hapticTask?.cancel()
        let device = WKInterfaceDevice.current()
        holdMic(seconds: 1)
        device.play(.notification)
        hapticTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            device.play(.notification)
            guard let deadline else { return }
            let wait = deadline.timeIntervalSinceNow - 10
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard !Task.isCancelled, self?.display.mode == .checkIn else { return }
            self?.holdMic(seconds: 1)
            device.play(.notification)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            device.play(.notification)
        }
    }

    private func stopHaptics() {
        hapticTask?.cancel()
        hapticTask = nil
    }
}
