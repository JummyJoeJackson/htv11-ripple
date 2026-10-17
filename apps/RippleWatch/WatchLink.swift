import Foundation
import RippleKit
import WatchConnectivity

/// The Watch side of WatchConnectivity. Receives the circle display and the
/// configuration from the iPhone and sends circle actions. The Watch never
/// decides whether texts go out; the iPhone does.
final class WatchLink: NSObject, WCSessionDelegate {
    /// Called on the main thread.
    var onDisplay: ((WatchDisplay) -> Void)?
    /// Called on the main thread.
    var onConfig: ((WatchConfig) -> Void)?
    /// Called on the main thread.
    var onReachability: ((Bool) -> Void)?
    /// Called on the main thread with what the iPhone heard from the microphone.
    var onHeard: ((VoiceHeard) -> Void)?

    var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The completion runs on the main thread, with nil if the iPhone never answered.
    func send(_ action: WatchAction, completion: @escaping (WatchActionReply?) -> Void) {
        guard isReachable else {
            completion(nil)
            return
        }
        WCSession.default.sendMessage(
            WatchEnvelope.make(WatchEnvelope.action, action),
            replyHandler: { reply in
                let decoded = WatchEnvelope.decode(WatchActionReply.self, from: reply)
                DispatchQueue.main.async { completion(decoded) }
            },
            errorHandler: { _ in
                DispatchQueue.main.async { completion(nil) }
            }
        )
    }

    func ping() {
        guard isReachable else { return }
        WCSession.default.sendMessage([WatchEnvelope.typeKey: WatchEnvelope.ping], replyHandler: nil, errorHandler: nil)
    }

    /// Tells the iPhone which configuration version is stored here.
    func acknowledgeConfig(_ version: Int) {
        guard isReachable else { return }
        WCSession.default.sendMessage(WatchEnvelope.make(WatchEnvelope.configAck, WatchConfigAck(version: version)), replyHandler: nil, errorHandler: nil)
    }

    /// Microphone audio for the iPhone to recognize. Dropped while it isn't reachable.
    func sendVoiceAudio(session: String, audio: Data) {
        guard isReachable else { return }
        WCSession.default.sendMessage(WatchEnvelope.makeVoiceAudio(session: session, audio: audio), replyHandler: nil, errorHandler: nil)
    }

    func stopVoice(session: String) {
        guard isReachable else { return }
        WCSession.default.sendMessage(WatchEnvelope.makeVoiceStop(session: session), replyHandler: nil, errorHandler: nil)
    }

    /// Asks the iPhone for the current display and configuration.
    func requestState() {
        guard isReachable else { return }
        WCSession.default.sendMessage(
            [WatchEnvelope.typeKey: WatchEnvelope.hello],
            replyHandler: { [weak self] reply in self?.deliverContext(reply) },
            errorHandler: nil
        )
    }

    private func deliverContext(_ context: [String: Any]) {
        let display = WatchEnvelope.decode(WatchDisplay.self, from: context, key: WatchEnvelope.display)
        let config = WatchEnvelope.decode(WatchConfig.self, from: context, key: WatchEnvelope.config)
        DispatchQueue.main.async {
            if let config { self.onConfig?(config) }
            if let display { self.onDisplay?(display) }
        }
    }

    private func deliverMessage(_ message: [String: Any]) {
        switch WatchEnvelope.type(of: message) {
        case WatchEnvelope.display:
            if let display = WatchEnvelope.decode(WatchDisplay.self, from: message) {
                DispatchQueue.main.async { self.onDisplay?(display) }
            }
        case WatchEnvelope.config:
            if let config = WatchEnvelope.decode(WatchConfig.self, from: message) {
                DispatchQueue.main.async { self.onConfig?(config) }
            }
        case WatchEnvelope.voiceHeard:
            if let heard = WatchEnvelope.decode(VoiceHeard.self, from: message) {
                DispatchQueue.main.async { self.onHeard?(heard) }
            }
        default:
            deliverContext(message)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        deliverContext(session.receivedApplicationContext)
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.onReachability?(reachable)
            self.requestState()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.onReachability?(reachable)
            if reachable { self.requestState() }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliverContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliverMessage(message)
    }
}
