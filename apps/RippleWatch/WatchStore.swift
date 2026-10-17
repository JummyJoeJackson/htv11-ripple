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
    private(set) var display: WatchDisplay
    private(set) var config: WatchConfig
    private(set) var phoneReachable = false
    private(set) var sending = false
    var feedback: WatchFeedback?
    /// Monitoring on: a tap shows "Hold to stop." and nothing else.
    var showHoldHint = false
    var confirmStop = false

    private let link = WatchLink()
    @ObservationIgnored private var hapticTask: Task<Void, Never>?
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var pendingActionId: String?
    @ObservationIgnored private var combos = ComboRecognizer()

    private enum Keys {
        static let config = "ripple.watch.config"
        static let display = "ripple.watch.display"
    }

    init() {
        let defaults = UserDefaults.standard
        config = defaults.data(forKey: Keys.config).flatMap { try? RippleJSON.decoder.decode(WatchConfig.self, from: $0) } ?? .fallback
        display = defaults.data(forKey: Keys.display).flatMap { try? RippleJSON.decoder.decode(WatchDisplay.self, from: $0) } ?? .off
        link.onDisplay = { [weak self] display in
            self?.apply(display)
        }
        link.onConfig = { [weak self] config in
            self?.store(config)
        }
        link.onReachability = { [weak self] reachable in
            self?.phoneReachable = reachable
        }
        link.activate()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.link.ping()
                if let self {
                    self.phoneReachable = self.link.isReachable
                    if self.config.version > 0 { self.link.acknowledgeConfig(self.config.version) }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    // MARK: Incoming

    private func apply(_ newDisplay: WatchDisplay) {
        let previousAlarm = display.mode == .checkIn ? display.alarmId : nil
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
    }

    /// Keeps the last configuration it received and confirms it to the iPhone.
    private func store(_ newConfig: WatchConfig) {
        guard newConfig.version >= config.version else { return }
        config = newConfig
        if let data = try? RippleJSON.encoder.encode(newConfig) {
            UserDefaults.standard.set(data, forKey: Keys.config)
        }
        link.acknowledgeConfig(newConfig.version)
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

    /// The voice phrase is a dismissal, never duress.
    func voiceInput(_ text: String) {
        guard config.voiceEnabled, display.mode.isAlarm else { return }
        if Self.matches(text, phrase: config.voicePhrase) {
            send(.dismiss, method: .voice)
        } else {
            feedback = WatchFeedback(text: "Didn't catch that. Tap the circle instead.", ok: false)
            WKInterfaceDevice.current().play(.failure)
        }
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

    static func matches(_ text: String, phrase: String) -> Bool {
        func normalize(_ value: String) -> String {
            value.lowercased()
                .replacingOccurrences(of: "’", with: "'")
                .filter { $0.isLetter || $0.isNumber || $0 == " " }
                .trimmingCharacters(in: .whitespaces)
        }
        let spoken = normalize(text)
        let wanted = normalize(phrase)
        return !wanted.isEmpty && spoken.contains(wanted)
    }

    private func send(_ kind: WatchActionKind, method: DismissMethod = .touch) {
        guard !sending else { return }
        guard link.isReachable, display.phoneAvailable else {
            feedback = WatchFeedback(text: "Not sent. iPhone isn't available.", ok: false)
            WKInterfaceDevice.current().play(.failure)
            return
        }
        let action = WatchAction(kind: kind, method: method, alarmId: display.alarmId)
        pendingActionId = action.id
        sending = true
        link.send(action) { [weak self] reply in
            self?.finish(action.id, reply: reply)
        }
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(action.id, reply: nil)
        }
    }

    private func finish(_ actionId: String, reply: WatchActionReply?) {
        guard pendingActionId == actionId else { return }
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
