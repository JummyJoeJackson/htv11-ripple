import Foundation
import KazeKit
import WatchConnectivity

/// The iPhone side of WatchConnectivity. Sends display state to the watch and
/// receives I'm okay / Get help commands, which the store forwards to the
/// backend. A connected phone never implies the wearer or the watch responded.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    /// Called on the main thread. The reply must be called exactly once.
    var onCommand: ((WatchCommand, @escaping (WatchCommandReply) -> Void) -> Void)?
    /// Called on the main thread when the watch app becomes reachable.
    var onReachable: (() -> Void)?

    // Updated on the main thread.
    private(set) var isReachable = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    /// Last time any message arrived from the watch.
    private(set) var lastContact: Date?

    private let lock = NSLock()
    private var latestState: WatchState = .notSetUp
    private var lastPushed: WatchState?
    private var lastPushedAt = Date.distantPast

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Call on the main thread.
    func push(_ state: WatchState, force: Bool = false) {
        lock.lock()
        latestState = state
        lock.unlock()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let unchanged = state.sameContent(as: lastPushed)
        if unchanged && !force && Date().timeIntervalSince(lastPushedAt) < 10 { return }
        lastPushed = state
        lastPushedAt = Date()

        let message = WatchEnvelope.make(WatchEnvelope.state, state)
        try? session.updateApplicationContext(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
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
        // Needed when the user switches to another watch.
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
                self.onReachable?()
            }
        }
    }

    /// Pings from the watch.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.lastContact = Date()
            self.isReachable = true
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let type = WatchEnvelope.type(of: message)

        if type == WatchEnvelope.hello {
            lock.lock()
            let current = latestState
            lock.unlock()
            replyHandler(WatchEnvelope.make(WatchEnvelope.state, current))
            DispatchQueue.main.async { self.lastContact = Date() }
            return
        }

        guard type == WatchEnvelope.command, let command = WatchEnvelope.decode(WatchCommand.self, from: message) else {
            replyHandler([:])
            return
        }
        DispatchQueue.main.async {
            self.lastContact = Date()
            guard let onCommand = self.onCommand else {
                let reply = WatchCommandReply(id: command.id, ok: false, message: "The iPhone app isn't ready.")
                replyHandler(WatchEnvelope.make(WatchEnvelope.reply, reply))
                return
            }
            onCommand(command) { reply in
                replyHandler(WatchEnvelope.make(WatchEnvelope.reply, reply))
            }
        }
    }
}
