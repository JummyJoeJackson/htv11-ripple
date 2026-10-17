import RippleKit
import SwiftUI
import UIKit

/// Basic monitoring, alarm, connection, backend and message status. The
/// iPhone is mainly for setup; the Watch circle is the everyday control.
struct HomeView: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        // Read the revision so the screen refreshes when the coordinator changes.
        let _ = store.revision
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.outageUntil != nil {
                        OutageCard()
                    }
                    CircleStatusCard()
                    MessagesCard()
                    ConnectionsCard()
                    SetupLinks()
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ripple")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                FeedbackBar()
            }
        }
    }
}

// MARK: - Circle status

/// Mirrors the Watch circle, with phone fallbacks for every action.
private struct CircleStatusCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let _ = store.revision
        let display = store.coordinator.display(phoneAvailable: !store.inOutage)
        Card {
            HStack(spacing: 14) {
                Circle()
                    .fill(display.mode.color)
                    .frame(width: 54, height: 54)
                    .overlay { Image(systemName: display.mode.symbol).font(.title2.weight(.bold)).foregroundStyle(.white) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.status)
                        .font(.title2.weight(.bold))
                    Text(display.mode.explanation)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let deadline = display.deadline {
                    CountdownText(deadline: deadline)
                        .font(.title2.weight(.bold))
                }
            }
            .accessibilityElement(children: .combine)

            switch display.mode {
            case .off:
                BigButton(title: "Start monitoring", systemImage: "play.circle.fill", tint: .green) {
                    store.startMonitoring()
                }
            case .monitoring:
                Button(role: .destructive) {
                    store.stopMonitoring()
                } label: {
                    Text("Stop monitoring").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                if let next = store.coordinator.nextCheckInAt {
                    Text("Next check-in at \(next.timeWithSeconds)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .checkIn:
                BigButton(title: "I'm okay", systemImage: "checkmark.circle.fill", tint: .green) {
                    store.dismissFromPhone()
                }
            case .alertSent, .responding:
                BigButton(title: "I'm okay now", systemImage: "hand.thumbsup.fill", tint: .green) {
                    store.dismissFromPhone()
                }
                Text("Everyone already texted gets an \"okay now\" text. Messages already sent can't be recalled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Simulated phone failure

private struct OutageCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        Card {
            Label("Simulated phone failure", systemImage: "iphone.slash")
                .font(.headline)
                .foregroundStyle(.orange)
            if let until = store.outageUntil {
                HStack {
                    Text("This iPhone is ignoring the Watch and the backend until \(until.timeWithSeconds).")
                    Spacer()
                    CountdownText(deadline: until)
                }
                .font(.subheadline)
            }
            Text("The backend sends any overdue alert by SMS as a declared backup.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Restore now") { store.restoreConnection() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Messages

/// Per-recipient status for the latest alarm, with which path sent each one.
private struct MessagesCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let _ = store.revision
        let alarm = store.coordinator.lastVisibleAlarm
        Card("Messages") {
            if let alarm {
                Text("Alarm at \(alarm.startedAt.timeWithSeconds) · \(alarm.isOpen ? "open" : (alarm.closeReason?.label ?? "closed"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if alarm.messages.isEmpty {
                    Text("No texts sent.")
                        .foregroundStyle(.secondary)
                }
                ForEach(alarm.messages) { message in
                    MessageRow(message: message)
                }
                if let ack = alarm.acknowledgment {
                    Label("\(ack.name) is responding (since \(ack.at.timeWithSeconds))", systemImage: "person.fill.checkmark")
                        .foregroundStyle(.blue)
                }
            } else {
                Text("No alarms yet.").foregroundStyle(.secondary)
            }
        }
    }
}

private struct MessageRow: View {
    let message: OutMessage

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(message.recipientName) · \(message.kind.label)")
                    .font(.subheadline.weight(.semibold))
                Text(message.path.label + (message.detail.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(statusColor)
        }
    }

    private var statusText: String {
        if message.status == .pending && message.launchedAt != nil { return "Sending" }
        return message.status.label
    }

    private var statusColor: Color {
        switch message.status {
        case .submitted: return .green
        case .failed: return .red
        case .unknown: return .orange
        case .pending, .cancelled: return .secondary
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
                StatusRow(label: "Backend", value: backendText, ok: store.backend.isOnline)
                if let reason = store.backend.offlineReason {
                    Text(reason).font(.footnote).foregroundStyle(.red)
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
        guard let version = store.watchConfigVersion else { return "Not synced yet" }
        if version == store.config.version {
            return "Up to date (v\(version))"
        }
        return "Watch has v\(version), sending v\(store.config.version)…"
    }

    private var backendText: String {
        switch store.backend {
        case .online:
            return store.lastSyncAt.map { "Online · \($0.timeWithSeconds)" } ?? "Online"
        case .offline:
            return "Unreachable"
        case .unknown:
            return "Connecting…"
        }
    }
}

private struct SetupLinks: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        Card("Setup") {
            NavigationLink {
                ContactsView()
            } label: {
                StatusRow(label: "Contacts", value: contactsSummary)
            }
            NavigationLink {
                ShortcutSetupView()
            } label: {
                StatusRow(label: "Messaging shortcut", value: store.config.shortcutName)
            }
        }
    }

    private var contactsSummary: String {
        let tierOne = store.config.contacts.filter { $0.tier == .one }.count
        let tierTwo = store.config.contacts.filter { $0.tier == .two }.count
        let temporary = store.temporaryContacts.filter { $0.isEligible(at: Date()) }.count
        var text = "\(tierOne) in Tier 1, \(tierTwo) in Tier 2"
        if temporary > 0 { text += ", \(temporary) temporary" }
        return text
    }
}

// MARK: - Feedback

struct FeedbackBar: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        if let pending = store.pending {
            HStack(spacing: 10) {
                ProgressView()
                Text(pending)
                Spacer()
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        } else if let banner = store.banner {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: banner.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(banner.ok ? Color.green : Color.red)
                Text(banner.text)
                Spacer()
                Button {
                    store.banner = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .task(id: banner.id) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if store.banner?.id == banner.id { store.banner = nil }
            }
        }
    }
}

extension CircleMode {
    var explanation: String {
        switch self {
        case .off: return "Monitoring is off."
        case .monitoring: return "Your Watch will check in with you."
        case .checkIn: return "Answer on your Watch."
        case .alertSent: return "Your contacts were texted."
        case .responding: return "A contact is checking on you."
        }
    }
}
