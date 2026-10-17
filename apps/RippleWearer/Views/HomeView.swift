import RippleKit
import SwiftUI
import UIKit

/// Logo, greeting, the Watch monitoring card, then four cards: medication,
/// symptom check-in and appointments (coming soon) and Emergency Help. During
/// an alarm the cards step aside for who was texted and one "I'm okay now"
/// button. The Watch circle is still the everyday control.
struct HomeView: View {
    @Environment(WearerStore.self) private var store
    /// The greeting is a little larger than other titles, and still scales with text size.
    @ScaledMetric(relativeTo: .largeTitle) private var greetingSize: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read the revision so the screen refreshes when the coordinator changes.
        let _ = store.revision
        let display = store.coordinator.display(phoneAvailable: !store.inOutage)
        let alarm = store.coordinator.visibleAlarm
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    HStack(alignment: .center) {
                        Image("RippleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                            .accessibilityLabel("Ripple")
                        Spacer()
                        NavigationLink {
                            SettingsView(isTabRoot: false)
                        } label: {
                            ProfileAvatar(size: Theme.minTarget)
                        }
                        .accessibilityLabel("Your profile and settings")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        greeting
                            .font(.system(size: greetingSize, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if !display.mode.isAlarm {
                            Text("Your care at a glance")
                                .font(.title3)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    if store.outageUntil != nil {
                        OutageCard()
                    }

                    StatusCardView(status: HomeStatus(display: display, alarm: alarm, nextCheckIn: store.coordinator.nextCheckInAt),
                                   watchConnected: store.connectivity.isReachable)

                    if display.mode == .alertSent || display.mode == .responding, let alarm {
                        AlertContactsCard(rows: ContactStatus.rows(for: alarm))
                    }

                    actions(for: display.mode)

                    if display.mode.isAlarm {
                        // The bottom bar hides during an alarm, so Session stays one tap away here.
                        RowGroup {
                            NavigationLink {
                                SessionView(isTabRoot: false)
                            } label: {
                                NavRow(title: "Session details", systemImage: "list.bullet.rectangle", detail: "Who was texted and when")
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        HomeCardGrid()
                    }
                }
                .padding(Theme.spacing)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: display.mode)
            }
            .rippleScreen(background: .one)
            .navigationTitle("Ripple")
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
    }

    /// "Hello, Alex!" from the name the app already stores, or "Ripple" without
    /// one. Written as a translatable sentence with the name filled in.
    private var greeting: Text {
        let first = store.config.wearerName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? Text(verbatim: "Ripple") : Text("Hello, \(first)!")
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
            .accessibilityHint("Your Watch will buzz and ask if you're okay.")
        case .monitoring:
            Button {
                store.stopMonitoring()
            } label: {
                Label("Stop monitoring", systemImage: "stop.fill")
            }
            .buttonStyle(.ripplePrimary)
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
                FormNote("Contacts get an \"I'm okay\" text.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Status card

/// Everything the status card shows, worked out from the coordinator. The
/// words are translatable sentences, with names and times filled in.
struct HomeStatus {
    var mode: CircleMode
    var headline: LocalizedStringKey
    var detail: LocalizedStringKey?
    var deadline: Date?

    init(mode: CircleMode, headline: LocalizedStringKey, detail: LocalizedStringKey? = nil, deadline: Date? = nil) {
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
            headline = "Monitoring is off"
            detail = "Turn it on to get check-ins."
        case .monitoring:
            headline = "Monitoring is active"
            if let next = nextCheckIn {
                detail = "Next check-in at \(next.shortTime)."
            } else {
                detail = nil
            }
        case .checkIn:
            headline = "Your Watch is asking if you're okay"
            detail = "Tap your Watch or \"I'm okay\" below."
        case .alertSent:
            let texted = (alarm?.alertedAt ?? alarm?.startedAt)?.shortTime
            if alarm?.helpRequestedAt != nil {
                // The wearer asked for help on the Watch or the iPhone.
                headline = "You asked for help."
                if let texted {
                    detail = "Your contacts were texted at \(texted). No one has responded yet."
                } else {
                    detail = "No one has responded yet."
                }
            } else {
                headline = "No one has responded yet."
                if let texted {
                    detail = "Your contacts were texted at \(texted)."
                } else {
                    detail = nil
                }
            }
        case .responding:
            if let ack = alarm?.acknowledgment {
                headline = "\(ack.name) is checking on you."
                detail = "Since \(ack.at.shortTime)"
            } else {
                headline = "A contact is checking on you."
                detail = nil
            }
        }
    }
}

struct StatusCardView: View {
    let status: HomeStatus
    var watchConnected = false

    var body: some View {
        Group {
            if status.mode == .alertSent || status.mode == .responding {
                SolidStatusCard(status: status)
            } else {
                MonitoringCard(status: status, watchConnected: watchConnected)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Status:") + Text(verbatim: " ") + Text(LocalizedStringKey(status.mode.pillLabel))
                            + Text(verbatim: ". ") + Text(status.headline))
    }
}

/// Off, monitoring and check-in: the Watch monitoring card, tinted with the
/// status color, with the status in words next to a dot (never color alone).
private struct MonitoringCard: View {
    @Environment(WearerStore.self) private var store
    let status: HomeStatus
    let watchConnected: Bool

    private var pillText: String {
        switch status.mode {
        case .monitoring: return "Active"
        case .checkIn: return "Check in"
        default: return "Off"
        }
    }

    /// What monitoring actually does, in plain words: how often the Watch
    /// buzzes, how long there is to answer, and what happens if there's no answer.
    private var detail: Text? {
        guard status.mode == .monitoring else { return status.detail.map { Text($0) } }
        let config = store.config
        if config.checkInIntervalMinutes > 0, let next = store.coordinator.nextCheckInAt {
            return Text("Next check-in at \(next.shortTime).")
        }
        return Text("\(config.countdownSeconds) s to answer when your Watch buzzes.")
    }

    var body: some View {
        let color = status.mode.color
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: Theme.spacing) {
                Image(systemName: status.mode == .checkIn ? "bell.fill" : "applewatch")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(color, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    // Label and status pill share one row, so nothing overlaps the headline.
                    HStack(alignment: .center, spacing: 8) {
                        SectionLabel("Watch monitoring")
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        HStack(spacing: 5) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(LocalizedStringKey(pillText))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.14), in: Capsule())
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(LocalizedStringKey(pillText)))
                    }
                    Text(status.headline)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let deadline = status.deadline {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            CountdownText(deadline: deadline)
                                .font(.title.weight(.bold))
                                .foregroundStyle(Theme.checkIn)
                            Text("left to answer")
                                .font(Theme.body)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let detail {
                        detail
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if status.mode == .monitoring && !watchConnected {
                        Label("Open Ripple on your Watch", systemImage: "applewatch")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.checkIn)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(color.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(color.opacity(0.18), lineWidth: 1))
                .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
        }
    }
}

// MARK: - Home cards

/// Medication, symptom check-in, appointments (coming soon) and Emergency Help.
/// Two columns, or one at the largest text sizes.
private struct HomeCardGrid: View {
    @Environment(WearerStore.self) private var store
    @State private var confirmHelp = false

    var body: some View {
        // Full-width cards, one under the other: help first, then medication.
        VStack(spacing: Theme.spacing) {
            HomeCard(icon: "message.fill", tint: Theme.alert, title: "Emergency Help", subtitle: "Text your contacts.") {
                Button {
                    confirmHelp = true
                } label: {
                    Label("Send Ripple alert", systemImage: "message.fill")
                        .font(Theme.labelBold)
                        .foregroundStyle(Theme.alert)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        .background(Theme.alert.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Asks for confirmation before texting a Ripple alert to all your contacts.")
            }
            HomeCard(icon: "pills.fill", tint: Theme.accent, title: "Medication Reminders", subtitle: "Stay on track.",
                     destination: AnyView(MedicationView())) {
                MedicationFooter()
            }
        }
        .confirmationDialog("Text all your contacts?", isPresented: $confirmHelp, titleVisibility: .visible) {
            Button("Send Ripple alert", role: .destructive) { store.requestHelpFromPhone() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your contacts get a text now.")
        }
    }
}

/// The card's color, so its footer can be tinted to match.
private struct HomeCardTintKey: EnvironmentKey {
    static let defaultValue = Theme.accent
}

private extension EnvironmentValues {
    var homeCardTint: Color {
        get { self[HomeCardTintKey.self] }
        set { self[HomeCardTintKey.self] = newValue }
    }
}

private struct HomeCard<Footer: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    /// When set, the top of the card opens this screen and shows a chevron.
    var destination: AnyView? = nil
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let destination {
                NavigationLink {
                    destination
                } label: {
                    HStack(alignment: .center, spacing: 4) {
                        header
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                header
            }
            footer
                .environment(\.homeCardTint, tint)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .rippleCard()
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title))
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocalizedStringKey(subtitle))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
    }
}

/// The bottom of the Medication card: "I took them" while a dose is due,
/// otherwise the next dose time, or a link to add dose times.
private struct MedicationFooter: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        let _ = store.revision
        let coordinator = store.coordinator
        if coordinator.pendingDoseAt != nil {
            Button {
                store.tookMedsFromPhone()
            } label: {
                Label("I took them", systemImage: "checkmark")
                    .font(Theme.labelBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Tells Ripple you've taken this dose, so no check-in starts.")
        } else if let next = coordinator.nextDoseAt {
            NavigationLink {
                MedicationView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next dose")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        Text(next.shortTime)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your medication times.")
        } else {
            NavigationLink {
                MedicationView()
            } label: {
                Label("Add dose times", systemImage: "plus")
                    .font(Theme.labelBold)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityHint("Opens your medication times.")
        }
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
                .font(.system(size: headlineSize, weight: .semibold))
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
