import RippleKit
import SwiftUI
import UIKit

/// A greeting, one status card, then only what matters right now. During an
/// alarm that's who was texted, one big "I'm okay now" button and a short
/// note. Contacts, Session and Settings live in the bottom bar. The Watch
/// circle is still the everyday control; every action here is a phone fallback.
struct HomeView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read the revision so the screen refreshes when the coordinator changes.
        let _ = store.revision
        let display = store.coordinator.display(phoneAvailable: !store.inOutage)
        let alarm = store.coordinator.visibleAlarm
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    // The logo steps aside during an alarm so the alert card stays at the top.
                    if !display.mode.isAlarm {
                        Image("RippleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .accessibilityLabel("Ripple")
                    }

                    Text(greeting)
                        .font(Theme.screenTitle)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)

                    if store.outageUntil != nil {
                        OutageCard()
                    }

                    StatusCardView(status: HomeStatus(display: display, alarm: alarm, nextCheckIn: store.coordinator.nextCheckInAt))

                    if display.mode == .alertSent || display.mode == .responding, let alarm {
                        AlertContactsCard(rows: ContactStatus.rows(for: alarm))
                    }

                    actions(for: display.mode)

                    // The bottom bar hides during an alarm, so Session stays one tap away here.
                    if display.mode.isAlarm {
                        RowGroup {
                            NavigationLink {
                                SessionView()
                            } label: {
                                NavRow(title: "Session details", systemImage: "list.bullet.rectangle", detail: "Texts and connections")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.spacing)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: display.mode)
            }
            .rippleScreen()
            .navigationTitle("Ripple")
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
    }

    /// "Hello, *Alex*!" from the name the app already stores, with the name in
    /// italics, or "Ripple" without one.
    private var greeting: AttributedString {
        let first = store.config.wearerName.split(separator: " ").first.map(String.init) ?? ""
        guard !first.isEmpty else { return AttributedString("Ripple") }
        var name = AttributedString(first)
        name.inlinePresentationIntent = .emphasized
        return AttributedString("Hello, ") + name + AttributedString("!")
    }

    /// At most one primary and one secondary action for each state.
    @ViewBuilder
    private func actions(for mode: CircleMode) -> some View {
        switch mode {
        case .off:
            Button {
                store.startMonitoring()
            } label: {
                Label("Start monitoring", systemImage: "play.fill")
            }
            .buttonStyle(.ripplePrimary)
            .accessibilityHint("Your Watch will start checking in with you.")
        case .monitoring:
            Button {
                store.stopMonitoring()
            } label: {
                Label("Stop monitoring", systemImage: "stop.fill")
            }
            .buttonStyle(.rippleSecondary)
            .accessibilityHint("Turns off check-ins until you start again.")
        case .checkIn:
            Button {
                store.dismissFromPhone()
            } label: {
                Label("I'm okay", systemImage: "checkmark")
            }
            .buttonStyle(.ripplePrimary)
            .accessibilityHint("Answers the check-in. No one is texted.")
        case .alertSent, .responding:
            VStack(spacing: 12) {
                Button {
                    store.dismissFromPhone()
                } label: {
                    Label("I'm okay now", systemImage: "hand.thumbsup.fill")
                }
                .buttonStyle(.ripplePrimary)
                .accessibilityHint("Texts everyone already contacted that you're okay.")
                FormNote("Texts already sent can't be undone. Contacts will get an \"I'm okay\" text.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Status card

/// Everything the status card shows, worked out from the coordinator.
struct HomeStatus {
    var mode: CircleMode
    var headline: String
    var detail: String?
    var deadline: Date?

    init(mode: CircleMode, headline: String, detail: String? = nil, deadline: Date? = nil) {
        self.mode = mode
        self.headline = headline
        self.detail = detail
        self.deadline = deadline
    }

    init(display: WatchDisplay, alarm: Alarm?, nextCheckIn: Date?) {
        mode = display.mode
        deadline = display.mode == .checkIn ? display.deadline : nil
        switch display.mode {
        case .off:
            headline = "Monitoring is off."
            detail = "Start monitoring here or on your Watch."
        case .monitoring:
            headline = "Your Watch will check in with you."
            detail = nextCheckIn.map { "Next check-in at \($0.shortTime)" }
        case .checkIn:
            headline = "Answer on your Watch."
            detail = "Tap the circle, or tap \"I'm okay\" below."
        case .alertSent:
            let texted = (alarm?.alertedAt ?? alarm?.startedAt).map { "Your contacts were texted at \($0.shortTime)." }
            if alarm?.helpRequestedAt != nil {
                // The wearer swiped up for help on the Watch.
                headline = "You asked for help."
                detail = [texted, "No one has responded yet."].compactMap { $0 }.joined(separator: " ")
            } else {
                headline = "No one has responded yet."
                detail = texted
            }
        case .responding:
            let ack = alarm?.acknowledgment
            headline = "\(ack?.name ?? "A contact") is checking on you."
            detail = ack.map { "Since \($0.at.shortTime)" }
        }
    }
}

struct StatusCardView: View {
    let status: HomeStatus

    var body: some View {
        Group {
            if status.mode == .alertSent || status.mode == .responding {
                SolidStatusCard(status: status)
            } else {
                HeroStatusCard(status: status)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.mode.pillLabel). \(status.headline)")
    }
}

/// Off, monitoring and check-in: a white hero card.
private struct HeroStatusCard: View {
    let status: HomeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(spacing: Theme.spacing) {
                Image(systemName: status.mode.symbol)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(status.mode.color, in: Circle())
                    .accessibilityHidden(true)
                StatusPill(status.mode.pillLabel, systemImage: status.mode.symbol, kind: status.mode.statusKind)
                Spacer(minLength: 0)
            }

            Text(status.headline)
                .font(Theme.headline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let deadline = status.deadline {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountdownText(deadline: deadline)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.checkIn)
                    Text("left to answer")
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }

            if let detail = status.detail {
                Text(detail)
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .rippleCard()
    }
}

/// Alert sent (red) and someone responding (blue): a solid card with white text.
private struct SolidStatusCard: View {
    let status: HomeStatus
    @ScaledMetric(relativeTo: .title2) private var headlineSize: CGFloat = 22

    var body: some View {
        let color = status.mode.color
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(spacing: Theme.spacing) {
                Image(systemName: status.mode.symbol)
                    .font(.title.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 64, height: 64)
                    .background(.white, in: Circle())
                    .accessibilityHidden(true)
                Label(status.mode.pillLabel, systemImage: status.mode.symbol)
                    .font(Theme.labelBold)
                    .foregroundStyle(color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white, in: Capsule())
                Spacer(minLength: 0)
            }

            Text(status.headline)
                .font(.system(size: headlineSize, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let detail = status.detail {
                Text(detail)
                    .font(Theme.body)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(color)
                .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
        }
    }
}

// MARK: - Who was texted

/// One person texted for the current alarm, in plain words.
struct ContactStatus: Identifiable, Equatable {
    enum State: Equatable {
        case responding, noAnswer, sending, couldNotText

        var label: String {
            switch self {
            case .responding: return "Responding"
            case .noAnswer: return "No answer"
            case .sending: return "Sending"
            case .couldNotText: return "Couldn't text"
            }
        }

        var symbol: String {
            switch self {
            case .responding: return "figure.walk"
            case .noAnswer: return "clock"
            case .sending: return "ellipsis"
            case .couldNotText: return "exclamationmark.triangle.fill"
            }
        }

        var kind: StatusKind {
            switch self {
            case .responding: return .responding
            case .noAnswer: return .checkIn
            case .couldNotText: return .alert
            case .sending: return .off
            }
        }
    }

    let id: String
    let name: String
    let state: State

    /// Everyone who was sent an alert or a second alert, responder first.
    static func rows(for alarm: Alarm) -> [ContactStatus] {
        var rows: [ContactStatus] = []
        for message in alarm.messages where message.kind == .alert || message.kind == .escalation {
            guard message.status != .cancelled, !rows.contains(where: { $0.id == message.recipientId }) else { continue }
            let state: State
            if alarm.acknowledgment?.recipientId == message.recipientId {
                state = .responding
            } else if message.status == .failed {
                state = .couldNotText
            } else if message.isCancellable {
                state = .sending
            } else {
                state = .noAnswer
            }
            rows.append(ContactStatus(id: message.recipientId, name: message.recipientName, state: state))
        }
        return rows.sorted { ($0.state == .responding ? 0 : 1) < ($1.state == .responding ? 0 : 1) }
    }
}

struct AlertContactsCard: View {
    let rows: [ContactStatus]

    var body: some View {
        Card("Who was texted") {
            if rows.isEmpty {
                FormNote("Sending texts now.")
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(Theme.divider)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(row.name)
                            .font(Theme.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        StatusPill(row.state.label, systemImage: row.state.symbol, kind: row.state.kind)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.name)
                            .font(Theme.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        StatusPill(row.state.label, systemImage: row.state.symbol, kind: row.state.kind)
                    }
                }
                .frame(minHeight: 60)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name): \(row.state.label)")
            }
        }
    }
}

// MARK: - Simulated phone failure

private struct OutageCard: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        Card {
            Label("Demo: phone failure", systemImage: "iphone.slash")
                .font(Theme.labelBold)
                .foregroundStyle(Theme.checkIn)
            if let until = store.outageUntil {
                Text("This iPhone is ignoring the Watch and the server until \(until.shortTime).")
                    .font(Theme.label)
                    .foregroundStyle(Theme.text)
            }
            FormNote("The server texts any overdue alert as a backup.")
            Button("Restore now") { store.restoreConnection() }
                .font(Theme.labelBold)
                .frame(minHeight: Theme.minTarget)
        }
    }
}

// MARK: - Feedback

struct FeedbackBar: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        if let pending = store.pending {
            HStack(spacing: 12) {
                ProgressView()
                Text(pending)
                    .font(Theme.label)
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(Theme.spacing)
            .rippleCard()
            .padding(.horizontal, Theme.spacing)
        } else if let banner = store.banner {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: banner.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(banner.ok ? Theme.safe : Theme.checkIn)
                    .accessibilityHidden(true)
                Text(banner.text)
                    .font(Theme.label)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Button {
                    store.banner = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: Theme.minTarget, height: Theme.minTarget)
                }
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel("Dismiss message")
            }
            .padding(.leading, Theme.spacing)
            .rippleCard()
            .padding(.horizontal, Theme.spacing)
            .accessibilityElement(children: .contain)
            .task(id: banner.id) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if store.banner?.id == banner.id { store.banner = nil }
            }
        }
    }
}

// MARK: - Previews

private enum PreviewData {
    static let alertRows = [
        ContactStatus(id: "1", name: "Maya Chen", state: .noAnswer),
        ContactStatus(id: "2", name: "Daniel Park", state: .noAnswer),
        ContactStatus(id: "3", name: "Sam Rivera", state: .couldNotText),
    ]
    static let respondingRows = [
        ContactStatus(id: "1", name: "Maya Chen", state: .responding),
        ContactStatus(id: "2", name: "Daniel", state: .noAnswer),
    ]
}

/// The alert screen as HomeView lays it out, with sample data.
private struct AlertScreenPreview: View {
    var responding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing) {
                    StatusCardView(status: responding
                        ? HomeStatus(mode: .responding, headline: "Maya Chen is checking on you.", detail: "Since 12:47 AM")
                        : HomeStatus(mode: .alertSent, headline: "No one has responded yet.", detail: "Your contacts were texted at 12:46 AM."))
                    AlertContactsCard(rows: responding ? PreviewData.respondingRows : PreviewData.alertRows)
                    Button {} label: { Label("I'm okay now", systemImage: "hand.thumbsup.fill") }
                        .buttonStyle(.ripplePrimary)
                    FormNote("Texts already sent can't be undone. Contacts will get an \"I'm okay\" text.")
                        .multilineTextAlignment(.center)
                    RowGroup {
                        NavRow(title: "Session details", systemImage: "list.bullet.rectangle", detail: "Texts and connections")
                    }
                }
                .padding(Theme.spacing)
            }
            .rippleScreen()
            .navigationTitle("Ripple")
        }
        .tint(Theme.accent)
    }
}

#Preview("Alert screen") { AlertScreenPreview() }
#Preview("Alert screen, largest text") { AlertScreenPreview().dynamicTypeSize(.accessibility3) }
#Preview("Someone responding") { AlertScreenPreview(responding: true) }

#Preview("Status card, every state") {
    ScrollView {
        VStack(spacing: Theme.spacing) {
            StatusCardView(status: HomeStatus(mode: .off, headline: "Monitoring is off.", detail: "Start monitoring here or on your Watch."))
            StatusCardView(status: HomeStatus(mode: .monitoring, headline: "Your Watch will check in with you.", detail: "Next check-in at 1:15 AM"))
            StatusCardView(status: HomeStatus(mode: .checkIn, headline: "Answer on your Watch.", detail: "Tap the circle, or tap \"I'm okay\" below.", deadline: .now.addingTimeInterval(14)))
        }
        .padding(Theme.spacing)
    }
    .rippleScreen()
}

#Preview("Status card, largest text") {
    ScrollView {
        StatusCardView(status: HomeStatus(mode: .checkIn, headline: "Answer on your Watch.", detail: "Tap the circle, or tap \"I'm okay\" below.", deadline: .now.addingTimeInterval(14)))
            .padding(Theme.spacing)
    }
    .rippleScreen()
    .dynamicTypeSize(.accessibility3)
}

#Preview("Home") {
    HomeView().environment(WearerStore())
}

#Preview("Home, largest text") {
    HomeView().environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
