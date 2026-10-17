import Foundation
import RippleKit
import UIKit

/// Sends alarm texts, invitations and setup tests through the existing
/// Ripple Alert shortcut. Each message goes to one recipient.
@MainActor
final class ShortcutSender {
    var shortcutName = "Ripple Alert"
    var statusOf: ((String) -> OutMessage?)?
    var onLaunched: (([String]) -> Void)?
    var onResult: (([String], MessageStatus, String?) -> Void)?
    var onInvitationResult: ((String, MessageStatus, String?) -> Void)?
    var canLaunch: () -> Bool = { true }

    private enum Purpose: Equatable {
        case alarm, test, invitation(String)
    }

    private struct Batch {
        let id: String
        let messageIds: [String]
        let startedAt: Date
        let purpose: Purpose
    }

    private struct OneOff {
        let phone: String
        let text: String
        let purpose: Purpose
    }

    private var queue: [OutMessage] = []
    private var oneOffs: [OneOff] = []
    private var inFlight: Batch?
    private(set) var lastTestResult: String?
    var onTestResult: ((String) -> Void)?

    func enqueue(_ messages: [OutMessage]) {
        for message in messages where !queue.contains(where: { $0.id == message.id }) {
            queue.append(message)
        }
        launchIfPossible()
    }

    func sendTest(to phone: String, text: String) {
        oneOffs.removeAll { $0.purpose == .test }
        oneOffs.append(OneOff(phone: phone, text: text, purpose: .test))
        launchIfPossible()
    }

    func sendInvitation(id: String, to phone: String, text: String) {
        let purpose = Purpose.invitation(id)
        guard inFlight?.purpose != purpose, !oneOffs.contains(where: { $0.purpose == purpose }) else { return }
        oneOffs.append(OneOff(phone: phone, text: text, purpose: purpose))
        launchIfPossible()
    }

    func cancelInvitation(id: String) {
        oneOffs.removeAll { $0.purpose == .invitation(id) }
    }

    func cancelAll() {
        queue.removeAll()
        oneOffs.removeAll()
    }

    func launchIfPossible() {
        guard inFlight == nil, canLaunch() else { return }
        // Emergency messages take priority over invitations and setup tests.
        let ready = queue.filter { message in
            guard let current = statusOf?(message.id) else { return false }
            return current.isCancellable && current.path == .phone
        }
        queue.removeAll()
        if !ready.isEmpty {
            launch(items: ready.map { ($0.phone, $0.text) }, messageIds: ready.map(\.id), purpose: .alarm)
        } else if !oneOffs.isEmpty {
            let next = oneOffs.removeFirst()
            launch(items: [(next.phone, next.text)], messageIds: [], purpose: next.purpose)
        }
    }

    private func launch(items: [(String, String)], messageIds: [String], purpose: Purpose) {
        let batchId = RippleID.make(bytes: 6)
        guard let url = ShortcutURL.make(name: shortcutName, items: items, batchId: batchId) else {
            report(messageIds: messageIds, purpose: purpose, status: .failed, detail: "Couldn't build the Shortcuts link.")
            return
        }
        inFlight = Batch(id: batchId, messageIds: messageIds, startedAt: Date(), purpose: purpose)
        if !messageIds.isEmpty { onLaunched?(messageIds) }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.finish(batchId: batchId, status: .failed, detail: "The Shortcuts app couldn't be opened.")
            }
        }
    }

    func handle(url: URL) -> Bool {
        guard url.scheme == "ripple", url.host == "shortcut" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let batchId = value("batch") else { return true }
        switch value("result") {
        case "success": finish(batchId: batchId, status: .submitted, detail: "Shortcut finished")
        case "cancel": finish(batchId: batchId, status: .failed, detail: "The shortcut was cancelled")
        default: finish(batchId: batchId, status: .failed, detail: value("errorMessage") ?? "The shortcut reported an error")
        }
        return true
    }

    func tick() {
        if let batch = inFlight, Date().timeIntervalSince(batch.startedAt) > 60 {
            finish(batchId: batch.id, status: .unknown, detail: "No confirmation from Shortcuts")
        }
        launchIfPossible()
    }

    private func finish(batchId: String, status: MessageStatus, detail: String?) {
        guard let batch = inFlight, batch.id == batchId else { return }
        inFlight = nil
        report(messageIds: batch.messageIds, purpose: batch.purpose, status: status, detail: detail)
        launchIfPossible()
    }

    private func report(messageIds: [String], purpose: Purpose, status: MessageStatus, detail: String?) {
        switch purpose {
        case .test:
            let text = status == .submitted
                ? "Test shortcut finished. Check the recipient's phone to confirm it arrived."
                : "Test failed: \(detail ?? status.label)"
            lastTestResult = text
            onTestResult?(text)
        case .invitation(let id):
            onInvitationResult?(id, status, detail)
        case .alarm:
            if !messageIds.isEmpty { onResult?(messageIds, status, detail) }
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
