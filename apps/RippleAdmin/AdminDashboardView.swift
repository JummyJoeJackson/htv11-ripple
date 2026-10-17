import RippleKit
import SwiftUI

/// Basic current state, per-recipient message status with the sending path,
/// and whether each command reached the wearer's iPhone.
struct AdminDashboardView: View {
    @Environment(AdminStore.self) private var store
    let userId: String
    @State private var countdown = 15
    @State private var ackWindow = 15
    @State private var cutSeconds = 90
    @State private var confirmReset = false

    var body: some View {
        let view = store.view
        List {
            Section {
                if let reason = store.connection.offlineReason {
                    Label(reason, systemImage: "wifi.exclamationmark").foregroundStyle(.red)
                }
                PhoneStatusRows(view: view)
            } header: {
                Text("Wearer's iPhone")
            }

            Section("Controls") {
                Stepper("Countdown: \(countdown) s", value: $countdown, in: 5...120, step: 5)
                Button {
                    Task { await store.triggerAlarm(countdown: countdown) }
                } label: {
                    Label("Trigger alarm on the Watch", systemImage: "applewatch.radiowaves.left.and.right")
                }
                Button {
                    Task { await store.simulateHealthAlert(.fall) }
                } label: {
                    Label("Simulate Apple fall alert", systemImage: "figure.fall")
                }
                Button {
                    Task { await store.simulateHealthAlert(.heart) }
                } label: {
                    Label("Simulate Apple heart alert", systemImage: "heart.text.square")
                }
                Stepper("Cut for: \(cutSeconds) s", value: $cutSeconds, in: 30...300, step: 15)
                Button {
                    Task { await store.cutConnection(seconds: cutSeconds) }
                } label: {
                    Label("Cut phone connection", systemImage: "iphone.slash")
                }
                Button {
                    Task { await store.expireTemporary() }
                } label: {
                    Label("Expire temporary contact now", systemImage: "person.badge.clock")
                }
                .disabled(!(view?.temporaryContacts.contains { $0.state == .active || $0.state == .invited } ?? false))
                Button(role: .destructive) {
                    Task { await store.disableAlarm() }
                } label: {
                    Label("Disable current alarm", systemImage: "bell.slash")
                }
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Reset demo", systemImage: "arrow.counterclockwise")
                }
                if let pending = store.pending {
                    HStack { ProgressView(); Text(pending) }
                } else if let banner = store.banner {
                    Text(banner.text).foregroundStyle(banner.ok ? Color.green : Color.red)
                }
            }

            Section {
                Stepper("Response countdown: \(countdown) s", value: $countdown, in: 5...120, step: 5)
                Stepper("Acknowledge window: \(ackWindow) s", value: $ackWindow, in: 5...300, step: 5)
                Button("Send timers to the iPhone") {
                    Task { await store.setTimers(countdown: countdown, ackWindow: ackWindow) }
                }
            } header: {
                Text("Demo timers")
            } footer: {
                Text("PRD demo setting: 15 seconds each.")
            }

            if let alarm = view?.alarm {
                AlarmSection(alarm: alarm, view: view!)
            }

            if let messages = view?.messages, !messages.isEmpty {
                Section {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                } header: {
                    Text("Messages")
                } footer: {
                    Text("Submitted means Shortcuts or Twilio accepted the text, not that a person received it. Confirm on the recipient's phone.")
                }
            }

            if let contacts = view?.temporaryContacts, !contacts.isEmpty {
                Section("Temporary contacts") {
                    ForEach(contacts) { contact in
                        VStack(alignment: .leading) {
                            Text(contact.name).font(.headline)
                            Text(temporaryText(contact)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let commands = view?.commands, !commands.isEmpty {
                Section("Commands") {
                    ForEach(commands) { command in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(command.kind.label)
                                Spacer()
                                Text(command.state.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(commandColor(command.state))
                            }
                            if let result = command.result {
                                Text(result).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let events = view?.events, !events.isEmpty {
                Section("Events") {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.at.adminTime).font(.caption).foregroundStyle(.secondary)
                            Text(event.text).font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle(view?.wearer.displayName ?? "Wearer")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { DemoAdminBanner() }
        .confirmationDialog("Reset the demo?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await store.reset() } }
        } message: {
            Text("Deletes the current alarm, pending countdowns, acknowledge windows, backup deadlines, links and temporary contacts so nothing old fires in the next run.")
        }
        .onAppear { store.select(userId) }
        .onDisappear { store.select(nil) }
    }

    private func temporaryText(_ contact: TemporaryContactView) -> String {
        if contact.isEligible(at: Date()), let expires = contact.expiresAt {
            return "Active until \(expires.adminTime)"
        }
        return contact.state.label
    }

    private func commandColor(_ state: CommandState) -> Color {
        switch state {
        case .queued: return .orange
        case .delivered: return .blue
        case .done: return .green
        case .rejected: return .red
        }
    }
}

private struct PhoneStatusRows: View {
    let view: AdminWearerView?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                if let last = view?.lastSyncAt {
                    let age = Int(context.date.timeIntervalSince(last))
                    Row(label: "Last heartbeat", value: age <= 2 ? "just now" : "\(age) s ago", color: age > 30 ? .red : (age > 5 ? .orange : .green))
                } else {
                    Row(label: "Last heartbeat", value: "never", color: .red)
                }
                if let status = view?.status {
                    Row(label: "Monitoring", value: status.monitoring ? "On" : "Off", color: status.monitoring ? .green : .secondary)
                    Row(label: "Watch", value: status.watchReachable ? "Connected" : (status.watchPaired ? "Not reachable" : "Not paired"),
                        color: status.watchReachable ? .green : .orange)
                    Row(label: "Watch settings", value: watchSync(status), color: status.watchConfigVersion == status.configVersion ? .green : .orange)
                    Row(label: "App", value: status.appActive ? "In foreground" : "In background", color: status.appActive ? .green : .orange)
                }
            }
        }
    }

    private func watchSync(_ status: DeviceStatus) -> String {
        guard let watch = status.watchConfigVersion else { return "Not synced" }
        return watch == status.configVersion ? "v\(watch), up to date" : "v\(watch) of v\(status.configVersion)"
    }

    private struct Row: View {
        let label: String
        let value: String
        let color: Color

        var body: some View {
            HStack {
                Text(label)
                Spacer()
                Text(value).foregroundStyle(color)
            }
            .font(.subheadline)
        }
    }
}

private struct AlarmSection: View {
    let alarm: Alarm
    let view: AdminWearerView

    var body: some View {
        Section("Alarm") {
            LabeledContent("Started", value: "\(alarm.startedAt.adminTime) (\(alarm.source.rawValue))")
            LabeledContent("State", value: stateText)
            if alarm.phase == .countdown {
                LabeledContent("Countdown ends", value: alarm.deadline.adminTime)
            }
            if alarm.duress {
                Label("Duress hold: hidden from the wearer's Watch and iPhone", systemImage: "eye.slash")
                    .foregroundStyle(.purple)
            }
            if let ack = view.acknowledgment {
                Label("\(ack.name) is responding (\(ack.at.adminTime))", systemImage: "person.fill.checkmark")
                    .foregroundStyle(.blue)
            } else if let ackDeadline = alarm.ackDeadline, alarm.isOpen {
                LabeledContent("Tier 2 due", value: ackDeadline.adminTime)
            }
            if let next = view.nextBackupAt {
                LabeledContent("Backup sends at", value: "\(next.adminTime) if the phone stays quiet")
            }
            LabeledContent("Location", value: alarm.location == nil ? "No fix" : "One fix at alarm start")
        }
    }

    private var stateText: String {
        if view.closedByAdmin { return "Disabled by demo admin" }
        switch alarm.phase {
        case .countdown: return "Waiting for the wearer"
        case .alerted: return "Tier 1 texted"
        case .escalated: return "Tier 2 texted"
        case .closed: return alarm.closeReason?.label ?? "Closed"
        }
    }
}

private struct MessageRow: View {
    let message: OutMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(message.recipientName) · \(message.kind.label)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(message.status == .pending && message.launchedAt != nil ? "Sending" : message.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text("Sent by: \(message.path.label)" + (message.detail.map { " · \($0)" } ?? ""))
                .font(.caption)
                .foregroundStyle(message.path == .backup ? Color.purple : Color.secondary)
            Text(message.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var color: Color {
        switch message.status {
        case .submitted: return .green
        case .failed: return .red
        case .unknown: return .orange
        case .pending, .cancelled: return .secondary
        }
    }
}

extension Date {
    var adminTime: String {
        formatted(.dateTime.hour().minute().second())
    }
}
