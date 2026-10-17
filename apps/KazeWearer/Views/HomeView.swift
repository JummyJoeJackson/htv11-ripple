import KazeKit
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(WearerStore.self) private var store
    @State private var showPinPad = false
    @State private var showInvite = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    StatusCard()

                    if let checkIn = store.state?.checkIn, checkIn.state == .awaitingResponse {
                        CheckInCard(checkIn: checkIn, showPinPad: $showPinPad)
                    }

                    if let incident = store.state?.incident {
                        IncidentCard(incident: incident, showPinPad: $showPinPad)
                    }

                    SessionCard()

                    BigButton(title: "Get help now", systemImage: "sos", tint: .red) {
                        Task { await store.helpFromPhone() }
                    }
                    .accessibilityHint("Immediately alerts your responders.")

                    CoverageCard(showInvite: $showInvite)

                    WatchCard()

                    ActivityCard()
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("KAZE")
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
            .sheet(isPresented: $showPinPad) {
                PinPadView()
            }
            .sheet(isPresented: $showInvite) {
                InviteHelperView()
            }
            .refreshable { await store.refresh() }
        }
    }
}

// MARK: - Status

private struct StatusCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let state = store.state
        Card {
            HStack {
                ToneBadge(tone: state?.tone ?? .neutral)
                Spacer()
                ConnectionLabel(connection: store.connection)
            }
            Text(state?.headline ?? "Connecting…")
                .font(.title2.weight(.bold))
            Text(state?.detail ?? "Reaching the KAZE server.")
                .foregroundStyle(.secondary)
            if let reason = store.connection.offlineReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionLabel: View {
    let connection: ServerConnection

    var body: some View {
        switch connection {
        case .online:
            Label("Server connected", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.green)
        case .offline:
            Label("Server unreachable", systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.red)
        case .unknown:
            Label("Connecting", systemImage: "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Check-in

private struct CheckInCard: View {
    @Environment(WearerStore.self) private var store
    let checkIn: CheckInView
    @Binding var showPinPad: Bool

    var body: some View {
        Card("Check-in") {
            HStack {
                Text(checkIn.kind == .demo ? "Demo check-in" : "Planned check-in")
                    .font(.headline)
                Spacer()
                CountdownText(deadline: checkIn.respondBy, serverOffset: store.serverOffset)
                    .font(.title3.weight(.semibold))
            }
            Text("Answer on your watch, or here if you can't reach it.")
                .foregroundStyle(.secondary)
            BigButton(title: "I'm okay", systemImage: "checkmark.circle.fill", tint: .green) {
                Task { await store.confirmFromPhone() }
            }
            Button("Cancel with PIN") { showPinPad = true }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

// MARK: - Incident

private struct IncidentCard: View {
    @Environment(WearerStore.self) private var store
    let incident: IncidentView
    @Binding var showPinPad: Bool

    var body: some View {
        Card("Alert") {
            Text(incident.triggers.map(\.label).joined(separator: " · "))
                .font(.headline)
            Text("Opened \(incident.openedAt.timeWithSeconds)")
                .foregroundStyle(.secondary)
            if incident.simulated {
                Label("Simulated demo event", systemImage: "theatermasks")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(incident.steps) { step in
                    HStack {
                        Text("\(step.position + 1).")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(step.name).font(.body.weight(.semibold))
                            Text(step.recipientKind.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(step.state.label)
                            .font(.subheadline)
                            .foregroundStyle(step.state == .acknowledged ? Color.blue : Color.primary)
                    }
                }
            }

            if incident.noResponderConfirmed {
                Label("No responder confirmed yet.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let report = incident.wearerSafetyReportAt {
                Label("You reported you're okay at \(report.timeWithSeconds). Your responders were told.", systemImage: "checkmark.bubble")
                    .foregroundStyle(.secondary)
            }

            if incident.wearerSafetyReportAt == nil {
                BigButton(title: "I'm okay now", systemImage: "hand.thumbsup.fill", tint: .green) {
                    Task { await store.confirmFromPhone() }
                }
            }
            Button("Cancel alert with PIN") { showPinPad = true }
                .frame(maxWidth: .infinity, minHeight: 44)
            Text("Messages already sent can't be recalled. Responders get an update when you cancel or report you're okay.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Session

private struct SessionCard: View {
    @Environment(WearerStore.self) private var store
    @State private var venue = ""
    @State private var duration = 60 * 60
    @State private var confirmEnd = false

    private struct DurationOption: Hashable {
        let label: String
        let seconds: Int
    }

    private let durations: [DurationOption] = [
        DurationOption(label: "30 seconds (demo)", seconds: 30),
        DurationOption(label: "1 minute", seconds: 60),
        DurationOption(label: "2 minutes", seconds: 120),
        DurationOption(label: "5 minutes", seconds: 300),
        DurationOption(label: "15 minutes", seconds: 900),
        DurationOption(label: "30 minutes", seconds: 1800),
        DurationOption(label: "1 hour", seconds: 3600),
        DurationOption(label: "2 hours", seconds: 7200),
        DurationOption(label: "4 hours", seconds: 14400),
    ]

    var body: some View {
        let state = store.state
        Card("Session") {
            if let session = state?.session, session.monitoring == .active {
                if !session.venue.isEmpty {
                    Label(session.venue, systemImage: "mappin.and.ellipse")
                }
                if let end = session.expectedEndAt {
                    Text("Expected back by \(end.shortTime)")
                        .font(.headline)
                    if let checkIn = state?.checkIn, checkIn.state == .scheduled {
                        HStack {
                            Text("Check-in at \(checkIn.promptAt.timeWithSeconds)")
                            Spacer()
                            CountdownText(deadline: checkIn.promptAt, serverOffset: store.serverOffset, prefix: "in ")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No planned end").font(.headline)
                }
                HStack(spacing: 12) {
                    Menu {
                        Button("+30 seconds (demo)") { extend(30) }
                        Button("+15 minutes") { extend(900) }
                        Button("+30 minutes") { extend(1800) }
                        Button("+1 hour") { extend(3600) }
                    } label: {
                        Label("Extend", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        confirmEnd = true
                    } label: {
                        Label("End", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
                    Button("End session", role: .destructive) {
                        Task { await store.endSession() }
                    }
                } message: {
                    Text("Future check-ins stop. An open alert stays open.")
                }
            } else {
                TextField("Where are you going? (optional)", text: $venue)
                    .textFieldStyle(.roundedBorder)
                Picker("Check in after", selection: $duration) {
                    ForEach(durations, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.menu)
                let hasContacts = !(state?.profile.contacts.isEmpty ?? true)
                BigButton(title: "Start session", systemImage: "play.circle.fill", tint: .green) {
                    Task { await store.startSession(venue: venue, durationSeconds: duration) }
                }
                .disabled(!hasContacts || store.pending != nil)
                if !hasContacts {
                    Text("Add a trusted contact in Settings first. Monitoring doesn't start without someone to alert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !(state?.profile.hasPins ?? false) {
                    Text("Set your safety and duress PINs in Settings so you can cancel false alarms.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func extend(_ seconds: Int) {
        Task { await store.extendSession(by: seconds) }
    }
}

// MARK: - Coverage

private struct CoverageCard: View {
    @Environment(WearerStore.self) private var store
    @Binding var showInvite: Bool

    var body: some View {
        let state = store.state
        Card("Who gets alerted") {
            Text(state?.coverageSummary ?? "")
                .foregroundStyle(.secondary)
            if let order = state?.routingOrder, !order.isEmpty {
                ForEach(Array(order.enumerated()), id: \.offset) { item in
                    Text("\(item.offset + 1). \(item.element)")
                }
            }
            ForEach(state?.coverages ?? []) { coverage in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(coverage.helperName, systemImage: "person.badge.shield.checkmark")
                            .font(.headline)
                        Spacer()
                        Text(coverage.isActive ? "Active" : coverage.state.label)
                            .foregroundStyle(coverage.isActive ? Color.green : Color.secondary)
                    }
                    Text("\(coverage.venue) · until \(coverage.endsAt.shortTime) · \(coverage.helperPhoneHint)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !coverage.isActive {
                        Text("Not counted as coverage until they verify their phone and accept.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Revoke helper access", role: .destructive) {
                        Task { await store.revokeCoverage(id: coverage.id) }
                    }
                }
                .padding(.top, 4)
            }
            if (state?.coverages ?? []).isEmpty {
                Button {
                    showInvite = true
                } label: {
                    Label("Invite a temporary helper", systemImage: "qrcode")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Watch

private struct WatchCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let link = store.connectivity
        // Re-read every few seconds; WatchConnectivity flags aren't observable.
        TimelineView(.periodic(from: .now, by: 3)) { _ in
            Card("Apple Watch") {
                if !link.isPaired {
                    Label("No paired Apple Watch", systemImage: "applewatch.slash")
                } else if !link.isWatchAppInstalled {
                    Label("Install KAZE on your watch from the Watch app", systemImage: "applewatch")
                } else if link.isReachable {
                    Label("Watch app connected", systemImage: "applewatch.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                } else {
                    Label("Watch app not open", systemImage: "applewatch")
                        .foregroundStyle(.orange)
                    Text("Open KAZE on your watch. For the demo it stays open and connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let last = link.lastContact {
                    Text("Last contact \(last.timeWithSeconds)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Activity

private struct ActivityCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        Card("Activity") {
            let events = store.state?.events ?? []
            if events.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
            ForEach(events.prefix(15)) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.at.timeWithSeconds + (event.simulated ? " · demo" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(event.text)
                        .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Feedback

/// Shows commands as pending until the backend confirms them.
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
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if store.banner?.id == banner.id { store.banner = nil }
            }
        }
    }
}
