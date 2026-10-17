import Foundation
import RippleKit
import UIKit

/// Sends texts from the wearer's iPhone by running the user-installed
/// "Ripple Alert" shortcut through Apple's Shortcuts URL scheme.
///
/// The shortcut receives JSON like {"messages":[{"to":"+1416…","text":"…"}]}
/// and repeats Send Message once per recipient, so nobody gets a group text.
/// Shortcuts calls back ripple://shortcut?batch=…&result=success when it
/// finishes. Opening the URL, or even that callback, is not proof that a
/// message was delivered, so the best status is "submitted".
@MainActor
final class ShortcutSender {
    var shortcutName = "Ripple Alert"
    /// Current state of a message, so cancelled or backup-sent texts are dropped before launch.
    var statusOf: ((String) -> OutMessage?)?
    var onLaunched: (([String]) -> Void)?
    var onResult: (([String], MessageStatus, String?) -> Void)?
    /// Shortcuts can only be opened while the app is in the foreground.
    var canLaunch: () -> Bool = { true }

    private struct Batch {
        let id: String
        let messageIds: [String]
        let startedAt: Date
        let isTest: Bool
    }

    private var queue: [OutMessage] = []
    private var pendingTest: (phone: String, text: String)?
    private var inFlight: Batch?
    private(set) var lastTestResult: String?
    var onTestResult: ((String) -> Void)?

    func enqueue(_ messages: [OutMessage]) {
        for message in messages where !queue.contains(where: { $0.id == message.id }) {
            queue.append(message)
        }
        launchIfPossible()
    }

    /// A one-off test message, for setting up and approving the shortcut.
    func sendTest(to phone: String, text: String) {
        pendingTest = (phone, text)
        launchIfPossible()
    }

    func cancelAll() {
        queue.removeAll()
        pendingTest = nil
    }

    func launchIfPossible() {
        guard inFlight == nil, canLaunch() else { return }

        if let test = pendingTest {
            pendingTest = nil
            launch(items: [(test.phone, test.text)], messageIds: [], isTest: true)
            return
        }

        let ready = queue.filter { message in
            guard let current = statusOf?(message.id) else { return false }
            return current.isCancellable && current.path == .phone
        }
        queue.removeAll()
        guard !ready.isEmpty else { return }
        launch(items: ready.map { ($0.phone, $0.text) }, messageIds: ready.map(\.id), isTest: false)
    }

    private func launch(items: [(String, String)], messageIds: [String], isTest: Bool) {
        let batchId = RippleID.make(bytes: 6)
        guard let url = ShortcutURL.make(name: shortcutName, items: items, batchId: batchId) else {
            report(messageIds: messageIds, isTest: isTest, status: .failed, detail: "Couldn't build the Shortcuts link.")
            return
        }
        inFlight = Batch(id: batchId, messageIds: messageIds, startedAt: Date(), isTest: isTest)
        if !messageIds.isEmpty {
            onLaunched?(messageIds)
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.finish(batchId: batchId, status: .failed, detail: "The Shortcuts app couldn't be opened.")
            }
        }
    }

    /// Handles ripple://shortcut?batch=…&result=success|error|cancel.
    func handle(url: URL) -> Bool {
        guard url.scheme == "ripple", url.host == "shortcut" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let batchId = value("batch") else { return true }
        switch value("result") {
        case "success":
            finish(batchId: batchId, status: .submitted, detail: "Shortcut finished")
        case "cancel":
            finish(batchId: batchId, status: .failed, detail: "The shortcut was cancelled")
        default:
            finish(batchId: batchId, status: .failed, detail: value("errorMessage") ?? "The shortcut reported an error")
        }
        return true
    }

    /// Call about once a second. A shortcut that never calls back is "unknown".
    func tick() {
        if let batch = inFlight, Date().timeIntervalSince(batch.startedAt) > 60 {
            finish(batchId: batch.id, status: .unknown, detail: "No confirmation from Shortcuts")
        }
        launchIfPossible()
    }

    private func finish(batchId: String, status: MessageStatus, detail: String?) {
        guard let batch = inFlight, batch.id == batchId else { return }
        inFlight = nil
        report(messageIds: batch.messageIds, isTest: batch.isTest, status: status, detail: detail)
        launchIfPossible()
    }

    private func report(messageIds: [String], isTest: Bool, status: MessageStatus, detail: String?) {
        if isTest {
            let text = status == .submitted
                ? "Test shortcut finished. Check the recipient's phone to confirm it arrived."
                : "Test failed: \(detail ?? status.label)"
            lastTestResult = text
            onTestResult?(text)
        } else if !messageIds.isEmpty {
            onResult?(messageIds, status, detail)
        }
    }
}

enum ShortcutURL {
    private struct Item: Encodable {
        let to: String
        let text: String
    }

    private struct Payload: Encodable {
        let messages: [Item]
    }

    static func payload(_ items: [(String, String)]) -> String? {
        let body = Payload(messages: items.map { Item(to: $0.0, text: $0.1) })
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// shortcuts://x-callback-url/run-shortcut?name=…&input=text&text=…&x-success=…
    static func make(name: String, items: [(String, String)], batchId: String) -> URL? {
        guard let text = payload(items) else { return nil }
        func callback(_ result: String) -> String { "ripple://shortcut?batch=\(batchId)&result=\(result)" }
        let query: [(String, String)] = [
            ("name", name),
            ("input", "text"),
            ("text", text),
            ("x-success", callback("success")),
            ("x-cancel", callback("cancel")),
            ("x-error", callback("error")),
        ]
        let encoded = query.map { "\($0.0)=\(strictlyEncoded($0.1))" }.joined(separator: "&")
        return URL(string: "shortcuts://x-callback-url/run-shortcut?" + encoded)
    }

    /// Percent-encodes everything except unreserved ASCII, so &, =, + and
    /// non-ASCII characters inside values survive.
    static func strictlyEncoded(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
