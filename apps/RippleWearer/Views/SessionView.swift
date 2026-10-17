import RippleKit
import SwiftUI

/// Next check-in, what's coming (medication and appointments, coming soon),
/// recent activity from past alarms, then the texts, location and connection
/// details for the latest alarm.
struct SessionView: View {
    /// False when opened from Home, so the navigation bar keeps its Back button.
    var isTabRoot = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Sessions", subtitle: "Your check-ins, alerts and texts")
                NextCheckInCard()
                ComingSoonRow(icon: "pills.fill", title: "Medication reminders")

                SectionTitle(title: "Upcoming")
                ComingSoonRow(icon: "stethoscope", title: "Appointments")

                SectionTitle(title: "Recent activity")
                RecentActivityCard()

                SectionTitle(title: "Details")
                MessagesCard()
                SentLocationCard()
                ConnectionsCard()
            }
            .padding(Theme.spacing)
        }
        .rippleScreen(background: .three)
        .toolbar(isTabRoot ? .hidden : .visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Next check-in

private struct NextCheckInCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let _ = store.revision
        let coordinator = store.coordinator
        HStack(spacing: Theme.spacing) {
            Image(systemName: "calendar")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 60, height: 60)
                .background(Theme.iconTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next check-in")
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
                Text(nextText(coordinator))
                    .font(Theme.headline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rippleCard()
        .accessibilityElement(children: .combine)
    }

    private func nextText(_ coordinator: AlarmCoordinator) -> String {
        if !coordinator.monitoring { return "Monitoring is off" }
        if let next = coordinator.nextCheckInAt { return next.dayAndTime }
        return "Automatic check-ins are off"
    }
}

/// A feature that isn't built yet, shown as a row with a "Coming soon" tag.
private struct ComingSoonRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.iconTint, in: Circle())
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text("Coming soon")
                .font(Theme.label)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Theme.rowHeight, alignment: .leading)
        .rippleCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent activity

/// What happened in recent alarms, newest first: checked in, alert sent,
/// someone responding, said I'm okay. A duress alarm is never shown.
private struct RecentActivityCard: View {
    @Environment(WearerStore.self) private var store

    private struct Event: Identifiable {
        let id: String
        let title: String
        let at: Date
        let symbol: String
        let color: Color
    }

    var body: some View {
        let _ = store.revision
        let events = Self.events(from: store.coordinator.history)
        VStack(spacing: 0) {
            if events.isEmpty {
                FormNote("Nothing yet. Check-ins and alerts will show here.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            ForEach(Array(events.prefix(6).enumerated()), id: \.element.id) { index, event in
                if index > 0 { RowDivider() }
                HStack(spacing: 14) {
                    Image(systemName: event.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(event.color, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(Theme.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(event.at.dayAndTime)
                            .font(Theme.label)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: Theme.rowHeight)
                .accessibilityElement(children: .combine)
            }
        }
        .rippleCard()
    }

    private static func events(from history: [Alarm]) -> [Event] {
        var events: [Event] = []
        for alarm in history where !alarm.duress {
            if let closed = alarm.closedAt {
                if alarm.closeReason == .dismissed && alarm.alertedAt == nil {
                    events.append(Event(id: alarm.id + "-ok", title: "Checked in", at: closed, symbol: "checkmark", color: Theme.safe))
                } else if alarm.closeReason == .okayNow {
                    events.append(Event(id: alarm.id + "-okay", title: "Said I'm okay", at: closed, symbol: "hand.thumbsup.fill", color: Theme.safe))
                }
            }
            if let ack = alarm.acknowledgment {
                events.append(Event(id: alarm.id + "-ack", title: "\(ack.name) is responding", at: ack.at, symbol: "figure.walk", color: Theme.responding))
            }
            if let alerted = alarm.alertedAt {
                let title = alarm.helpRequestedAt == nil ? "Alert sent" : "Help requested"
                events.append(Event(id: alarm.id + "-alert", title: title, at: alerted, symbol: "exclamationmark", color: Theme.alert))
            }
        }
        return events.sorted { $0.at > $1.at }
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
