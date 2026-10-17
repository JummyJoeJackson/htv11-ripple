import Foundation
import KazeKit
import WatchConnectivity

/// The watch side of WatchConnectivity. Receives display state from the
/// iPhone and sends I'm okay / Get help. The watch app must be open and
/// connected for the controlled demo (PRD §3).
final class WatchLink: NSObject, WCSessionDelegate {
    /// Called on the main thread.
    var onState: ((WatchState) -> Void)?
    /// Called on the main thread.
    var onReachability: ((Bool) -> Void)?

    var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The completion runs on the main thread with nil if the iPhone never answered.
    func send(_ command: WatchCommand, completion: @escaping (WatchCommandReply?) -> Void) {
        guard isReachable else {
            completion(nil)
            return
        }
        WCSession.default.sendMessage(
            WatchEnvelope.make(WatchEnvelope.command, command),
            replyHandler: { reply in
                let decoded = WatchEnvelope.decode(WatchCommandReply.self, from: reply)
                DispatchQueue.main.async { completion(decoded) }
            },
            errorHandler: { _ in
                DispatchQueue.main.async { completion(nil) }
            }
        )
    }

    /// Lets the iPhone know the watch app is alive.
    func ping() {
        guard isReachable else { return }
        WCSession.default.sendMessage([WatchEnvelope.typeKey: WatchEnvelope.ping], replyHandler: nil, errorHandler: nil)
    }

    /// Asks the iPhone for the current state, for example after reconnecting.
    func requestState() {
        guard isReachable else { return }
        WCSession.default.sendMessage(
            [WatchEnvelope.typeKey: WatchEnvelope.hello],
            replyHandler: { [weak self] reply in
                guard let state = WatchEnvelope.decode(WatchState.self, from: reply) else { return }
                DispatchQueue.main.async { self?.onState?(state) }
            },
            errorHandler: nil
        )
    }

    private func deliver(_ message: [String: Any]) {
        guard WatchEnvelope.type(of: message) == WatchEnvelope.state,
              let state = WatchEnvelope.decode(WatchState.self, from: message)
        else { return }
        DispatchQueue.main.async { self.onState?(state) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        deliver(session.receivedApplicationContext)
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
        deliver(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }
}
