import Foundation
import WatchKit

/// Keeps the Watch app running while the screen is off, so the iPhone stays
/// reachable, haptics still play and the microphone can keep listening. It
/// uses a mindfulness extended runtime session: up to one hour, started only
/// while the app is in front, and running until the wearer leaves the app.
/// Use on the main thread.
final class WatchRuntime: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?

    /// True while a session is starting or running.
    var isActive: Bool {
        guard let session else { return false }
        return session.state != .invalid
    }

    /// Does nothing while a session is active. Sessions can only start with the
    /// app in front, so a failed start is retried later.
    func start() {
        guard !isActive, WKApplication.shared().applicationState == .active else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        session.start()
    }

    func stop() {
        session?.invalidate()
        session = nil
    }

    // MARK: WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    /// The hour is nearly up. A new session starts the next time the app is in front.
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        DispatchQueue.main.async {
            if self.session === extendedRuntimeSession { self.session = nil }
        }
    }
}
