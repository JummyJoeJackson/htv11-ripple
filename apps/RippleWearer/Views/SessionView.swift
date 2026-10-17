import RippleKit
import SwiftUI

/// Details moved off the home screen: every text for the latest alarm, the
/// location sent with it, and how the Watch, server and settings are connected.
struct SessionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                MessagesCard()
                SentLocationCard()
                ConnectionsCard()
            }
            .padding(Theme.spacing)
        }
        .rippleScreen()
        .navigationTitle("Session")
    }
}

// MARK: - Messages

/// Per-person status for the latest alarm, with which path sent each text.
private struct MessagesCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let _ = store.revision
        let alarm = store.coordinator.lastVisibleAlarm
        Card("Texts") {
            if let alarm {
                let started = alarm.helpRequestedAt.map { "Help requested at \($0.shortTime)" } ?? "Alarm at \(alarm.startedAt.shortTime)"
                let state = alarm.isOpen ? "still open" : (alarm.closeReason?.label ?? "closed")
                Text("\(started) · \(state)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
                if alarm.messages.isEmpty {
                    FormNote("No texts sent.")
                }
                ForEach(alarm.messages) { message in
                    Divider().overlay(Theme.divider)
                    MessageRow(message: message)
                }
                if let ack = alarm.acknowledgment {
                    Divider().overlay(Theme.divider)
                    Label("\(ack.name) is checking on you (since \(ack.at.shortTime))", systemImage: "figure.walk")
                        .font(Theme.label.weight(.semibold))
                        .foregroundStyle(Theme.responding)
                }
            } else {
                FormNote("No alarms yet.")
            }
        }
    }
}

private struct MessageRow: View {
    let message: OutMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.recipientName)
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text("\(kindText) · \(pathText)")
                .font(Theme.label)
                .foregroundStyle(Theme.secondaryText)
            if let detail = message.detail {
                Text(detail)
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
            }
            Label(statusText, systemImage: statusSymbol)
                .font(Theme.labelBold)
                .foregroundStyle(statusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var kindText: String {
        switch message.kind {
        case .alert: return "Alert"
        case .escalation: return "Second alert"
        case .responding: return "Someone is checking"
        case .okayNow: return "I'm okay"
        }
    }

    private var pathText: String {
        message.path == .phone ? "From your iPhone" : "Backup from the server"
    }

    private var statusText: String {
        switch message.status {
        case .pending: return message.launchedAt != nil ? "Sending" : "Waiting"
        case .submitted: return "Sent"
        case .failed: return "Couldn't send"
        case .unknown: return "May have been sent"
        case .cancelled: return "Not sent"
        }
    }

    private var statusSymbol: String {
        switch message.status {
        case .submitted: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .pending: return "ellipsis.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch message.status {
        case .submitted: return Theme.safe
        case .failed, .unknown: return Theme.checkIn
        case .pending, .cancelled: return Theme.secondaryText
        }
    }
}

// MARK: - Connections

private struct ConnectionsCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let link = store.connectivity
        // WatchConnectivity flags aren't observable, so re-read them every few seconds.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Card("Connections") {
                StatusRow(label: "Apple Watch", value: watchText(link), ok: link.isReachable)
                StatusRow(label: "Watch settings", value: syncText, ok: store.watchConfigVersion == store.config.version)
                StatusRow(label: "Server", value: backendText, ok: store.backend.isOnline)
                if let reason = store.backend.offlineReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.label)
                        .foregroundStyle(Theme.checkIn)
                }
            }
        }
    }

    private func watchText(_ link: PhoneConnectivity) -> String {
        if !link.isPaired { return "Not paired" }
        if !link.isWatchAppInstalled { return "Install Ripple on the Watch" }
        return link.isReachable ? "Connected" : "Open Ripple on the Watch"
    }

    private var syncText: String {
        guard let version = store.watchConfigVersion else { return "Not sent yet" }
        if version == store.config.version {
            return "Up to date"
        }
        return "Sending the latest…"
    }

    private var backendText: String {
        switch store.backend {
        case .online:
            return store.lastSyncAt.map { "Online · \($0.shortTime)" } ?? "Online"
        case .offline:
            return "Can't reach it"
        case .unknown:
            return "Connecting…"
        }
    }
}

#Preview("Session") {
    NavigationStack { SessionView() }.environment(WearerStore())
}

#Preview("Session, largest text") {
    NavigationStack { SessionView() }.environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
