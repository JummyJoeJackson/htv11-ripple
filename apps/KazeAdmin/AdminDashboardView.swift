import KazeKit
import SwiftUI

/// Live view of one wearer's demo run: deadline, last response, delivery
/// attempts, responder progress, pending jobs and the event history.
struct AdminDashboardView: View {
    @Environment(AdminStore.self) private var store
    let userId: String
    @State private var window = 15
    @State private var stopReason = "End of demo scenario"
    @State private var confirmReset = false

    var body: some View {
        let view = store.view
        List {
            Section {
                HStack {
                    if let reason = store.connection.offlineReason {
                        Label(reason, systemImage: "wifi.exclamationmark").foregroundStyle(.red)
                    } else {
                        Label("Connected", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.green)
                    }
                    Spacer()
                    if let run = view?.demoRunId {
                        Text("Run \(String(run.prefix(6)))").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Controls") {
                Stepper("Response window: \(window) s", value: $window, in: 5...120, step: 5)
                Button {
                    Task { await store.triggerCheckIn(window: window) }
                } label: {
                    Label("Trigger check-in (simulated event)", systemImage: "applewatch.radiowaves.left.and.right")
                }
                .disabled(view?.session?.monitoring != .active || store.pending != nil)
                Button {
                    Task { await store.triggerHelp() }
                } label: {
                    Label("Trigger help request (simulated)", systemImage: "sos")
                }
                .disabled(store.pending != nil)
                TextField("Reason for stopping", text: $stopReason)
                Button(role: .destructive) {
                    Task { await store.stop(reason: stopReason) }
                } label: {
                    Label("Stop alert", systemImage: "stop.circle")
                }
                .disabled(view?.incident?.status != .open || stopReason.trimmingCharacters(in: .whitespaces).isEmpty || store.pending != nil)
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Reset demo run", systemImage: "arrow.counterclockwise")
                }
                .disabled(store.pending != nil)
                if let pending = store.pending {
                    HStack { ProgressView(); Text(pending) }
                } else if let banner = store.banner {
                    Text(banner.text).foregroundStyle(banner.ok ? Color.green : Color.red)
                }
            }

            Section("Session") {
                if let session = view?.session {
                    LabeledContent("Monitoring", value: session.monitoring.label)
                    if !session.venue.isEmpty { LabeledContent("Venue", value: session.venue) }
                    if let end = session.expectedEndAt { LabeledContent("Expected end", value: end.adminTime) }
                    LabeledContent("Last iPhone heartbeat", value: session.lastHeartbeatAt.adminTime)
                    LabeledContent("Watch", value: session.watchReachable ? "Reachable" : "Not reachable")
                    if let watch = session.lastWatchContactAt { LabeledContent("Last watch contact", value: watch.adminTime) }
                    if session.connectionLost { Text("Connection lost").foregroundStyle(.red) }
                } else {
                    Text("No session. Start one on the wearer's iPhone.").foregroundStyle(.secondary)
                }
                if let last = view?.lastResponseAt { LabeledContent("Last response", value: last.adminTime) }
            }

            if let checkIn = view?.checkIn {
                Section("Check-in") {
                    LabeledContent("State", value: checkIn.state.label)
                    LabeledContent("Kind", value: checkIn.kind == .demo ? "Demo (simulated)" : "Planned")
                    LabeledContent("Respond by", value: checkIn.respondBy.adminTime)
                    if checkIn.state == .awaitingResponse {
                        AdminCountdown(deadline: checkIn.respondBy, serverOffset: store.serverOffset)
                    }
                    if let responded = checkIn.respondedAt { LabeledContent("Answered", value: responded.adminTime) }
                }
            }

            if let incident = view?.incident {
                IncidentSection(incident: incident, serverOffset: store.serverOffset)
            }

            if let coverages = view?.coverages, !coverages.isEmpty {
                Section("Helper coverage") {
                    ForEach(coverages) { coverage in
                        VStack(alignment: .leading) {
                            Text("\(coverage.helperName) at \(coverage.venue)").font(.headline)
                            Text("\(coverage.isActive ? "Active" : coverage.state.label) · until \(coverage.endsAt.adminTime)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let jobs = view?.jobs, !jobs.isEmpty {
                Section("Scheduled jobs") {
                    ForEach(jobs) { job in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(job.kind.label)
                                if let note = job.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(job.state.rawValue).font(.caption.weight(.semibold))
                                    .foregroundStyle(job.state == .pending ? Color.orange : Color.secondary)
                                Text(job.runAt.adminTime).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let events = view?.events, !events.isEmpty {
                Section("Events") {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(event.at.adminTime) · \(event.actor.rawValue)\(event.simulated ? " · simulated" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(event.text).font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle(view?.wearer.displayName ?? "Wearer")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { DemoModeBanner() }
        .confirmationDialog("Reset this demo run?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await store.reset() } }
        } message: {
            Text("Ends the session, revokes links and invitations, and cancels every pending timer. Reset sends no messages; use Stop first if responders should get an update.")
        }
        .onAppear {
            store.select(userId)
            if let timing = store.view?.timing { window = timing.responseWindowSeconds }
        }
        .onDisappear { store.select(nil) }
    }
}

private struct IncidentSection: View {
    let incident: IncidentView
    let serverOffset: TimeInterval

    var body: some View {
        Section("Alert") {
            Group {
                LabeledContent("Status", value: incident.status == .open ? "Open" : "Resolved")
                LabeledContent("Triggers", value: incident.triggers.map(\.label).joined(separator: ", "))
                if incident.concealed {
                    Label("Silent alert: hidden from the wearer's screens", systemImage: "eye.slash")
                        .foregroundStyle(.purple)
                }
                if incident.simulated { Label("Simulated event", systemImage: "theatermasks").foregroundStyle(.orange) }
                LabeledContent("Responder progress", value: incident.progress.label)
            }
            Group {
                if let name = incident.responderName { LabeledContent("Responder", value: name) }
                if let report = incident.wearerSafetyReportAt { LabeledContent("Wearer said okay", value: report.adminTime) }
                if incident.escalationPaused { Text("Escalation paused after the wearer's safety report").foregroundStyle(.secondary) }
                if incident.noResponderConfirmed { Text("No responder confirmed").foregroundStyle(.red) }
                if let resolution = incident.resolution {
                    LabeledContent("Resolution", value: resolutionText(resolution))
                }
            }

            ForEach(incident.steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(step.position + 1). \(step.name)").font(.headline)
                        Text(step.recipientKind.label).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(step.state.label).font(.subheadline.weight(.semibold))
                    }
                    if let deadline = step.ackDeadline, step.state == .notified {
                        HStack {
                            Text("Ack deadline")
                            Spacer()
                            AdminCountdown(deadline: deadline, serverOffset: serverOffset)
                        }
                        .font(.caption)
                    }
                    if let opened = step.firstOpenedAt {
                        Text("Observed receipt: opened the alert at \(opened.adminTime)").font(.caption).foregroundStyle(.blue)
                    }
                    ForEach(step.deliveries) { delivery in
                        Text(deliveryLine(delivery))
                            .font(.caption)
                            .foregroundStyle(delivery.state == .failed ? Color.red : Color.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Text("Submitted means the messaging service accepted the text. Only an opened page or an action shows a person received it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private extension IncidentSection {
    func resolutionText(_ resolution: ResolutionReason) -> String {
        if let note = incident.resolutionNote { return resolution.label + ": " + note }
        return resolution.label
    }

    func deliveryLine(_ delivery: DeliveryView) -> String {
        var line = "Message \(delivery.attemptNo) to \(delivery.to): \(delivery.state.label)"
        if let status = delivery.providerStatus { line += " · carrier: " + status }
        if let error = delivery.error { line += " · " + error }
        return line
    }
}

private struct AdminCountdown: View {
    let deadline: Date
    let serverOffset: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(deadline.timeIntervalSince(context.date.addingTimeInterval(serverOffset)).rounded(.up))
            Text(remaining > 0 ? "\(remaining) s left" : "Passed")
                .monospacedDigit()
                .foregroundStyle(remaining > 5 ? Color.orange : Color.red)
        }
    }
}

extension Date {
    var adminTime: String {
        formatted(.dateTime.hour().minute().second())
    }
}
