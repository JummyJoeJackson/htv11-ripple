import Foundation
import RippleKit
import WatchConnectivity

/// The iPhone side of WatchConnectivity: sends the circle display and the
/// configuration to the Watch, and receives circle actions.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    /// Called on the main thread. The reply must be called exactly once.
    var onAction: ((WatchAction, @escaping (WatchActionReply) -> Void) -> Void)?
    /// Called on the main thread when the Watch confirms it stored a configuration version.
    var onConfigAck: ((Int) -> Void)?
    /// Called on the main thread when the Watch app becomes reachable.
    var onReachable: (() -> Void)?
    /// Called on the main thread with microphone audio from the Watch, by listening session.
    var onVoiceAudio: ((String, Data) -> Void)?
    /// Called on the main thread when the Watch stops listening.
    var onVoiceStop: ((String) -> Void)?

    // Updated on the main thread.
    private(set) var isReachable = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var lastContact: Date?

    private let lock = NSLock()
    private var latestDisplay = WatchDisplay.off
    private var latestConfig = WatchConfig.fallback
    private var lastSentDisplay: WatchDisplay?
    private var lastSentConfigVersion: Int?
    private var lastContextAt = Date.distantPast

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call on the main thread whenever the display or configuration may have changed.
    func push(display: WatchDisplay, config: WatchConfig, force: Bool = false) {
        lock.lock()
        latestDisplay = display
        latestConfig = config
        lock.unlock()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }

        let displayChanged = !display.sameContent(as: lastSentDisplay)
        let configChanged = lastSentConfigVersion != config.version
        let stale = Date().timeIntervalSince(lastContextAt) > 10
        guard force || displayChanged || configChanged || stale else { return }

        // The application context survives while the Watch app isn't running.
        try? session.updateApplicationContext(WatchEnvelope.context(display: display, config: config))
        lastContextAt = Date()

        if session.isReachable {
            if force || displayChanged {
                session.sendMessage(WatchEnvelope.make(WatchEnvelope.display, display), replyHandler: nil, errorHandler: nil)
            }
            if force || configChanged {
                session.sendMessage(WatchEnvelope.make(WatchEnvelope.config, config), replyHandler: nil, errorHandler: nil)
            }
        }
        lastSentDisplay = display
        lastSentConfigVersion = config.version
    }

    /// What speech recognition heard, for the Watch that's listening.
    func send(_ heard: VoiceHeard) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(WatchEnvelope.make(WatchEnvelope.voiceHeard, heard), replyHandler: nil, errorHandler: nil)
    }

    private func refreshFlags(_ session: WCSession) {
        isReachable = session.isReachable
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.refreshFlags(session) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.refreshFlags(session) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.refreshFlags(session)
            if session.isReachable {
                self.lastContact = Date()
                self.lastSentDisplay = nil
                self.onReachable?()
            }
        }
    }

    /// Pings, configuration confirmations and microphone audio.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = WatchEnvelope.type(of: message)
        let ack = type == WatchEnvelope.configAck ? WatchEnvelope.decode(WatchConfigAck.self, from: message) : nil
        let voice = type == WatchEnvelope.voiceAudio ? WatchEnvelope.decodeVoiceAudio(from: message) : nil
        let voiceStopped = type == WatchEnvelope.voiceStop ? message[WatchEnvelope.sessionKey] as? String : nil
        DispatchQueue.main.async {
            self.lastContact = Date()
            self.isReachable = true
            if let ack { self.onConfigAck?(ack.version) }
            if let voice { self.onVoiceAudio?(voice.session, voice.audio) }
            if let voiceStopped { self.onVoiceStop?(voiceStopped) }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let type = WatchEnvelope.type(of: message)

        if type == WatchEnvelope.hello {
            lock.lock()
            let context = WatchEnvelope.context(display: latestDisplay, config: latestConfig)
            lock.unlock()
            replyHandler(context)
            DispatchQueue.main.async { self.lastContact = Date() }
            return
        }

        guard type == WatchEnvelope.action, let action = WatchEnvelope.decode(WatchAction.self, from: message) else {
            replyHandler([:])
            return
        }
        DispatchQueue.main.async {
            self.lastContact = Date()
            guard let onAction = self.onAction else {
                let reply = WatchActionReply(actionId: action.id, result: ActionResult(ok: false, feedback: "iPhone app isn't ready"), display: self.latestDisplay)
                replyHandler(WatchEnvelope.make(WatchEnvelope.reply, reply))
                return
            }
            onAction(action) { reply in
                replyHandler(WatchEnvelope.make(WatchEnvelope.reply, reply))
            }
        }
    }
}
