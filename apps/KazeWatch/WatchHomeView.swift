import KazeKit
import SwiftUI

/// One dominant I'm okay button, an accessible Get help button, readable
/// status, and a countdown during a check-in. Configuration lives on the iPhone.
struct WatchHomeView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let state = store.state
        ScrollView {
            VStack(spacing: 10) {
                StatusHeader(state: state)

                if let respondBy = state?.respondBy {
                    WatchCountdown(deadline: respondBy, serverOffset: state?.serverOffset ?? 0)
                }

                OkayButton(
                    awaiting: store.isAwaitingCheckIn,
                    pending: store.pending?.kind == .confirm,
                    action: { store.confirm() }
                )

                HelpButton(pending: store.pending?.kind == .help, action: { store.help() })

                if let feedback = store.feedback {
                    Label(feedback.text, systemImage: feedback.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(feedback.ok ? Color.green : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .task(id: feedback.id) {
                            try? await Task.sleep(nanoseconds: 6_000_000_000)
                            if store.feedback?.id == feedback.id { store.feedback = nil }
                        }
                }

                if let line = state?.responderLine {
                    Label(line, systemImage: "person.fill.checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !store.phoneReachable {
                    Label("iPhone not connected", systemImage: "iphone.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if state?.phoneOnline == false {
                    Label("iPhone can't reach the server", systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct StatusHeader: View {
    let state: WatchState?

    var body: some View {
        let tone = state?.tone ?? .neutral
        VStack(alignment: .leading, spacing: 4) {
            Label(tone.label, systemImage: tone.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone == .awaiting ? Color.yellow : tone.color)
            Text(state?.headline ?? "Open KAZE on iPhone")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = state?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WatchCountdown: View {
    let deadline: Date
    let serverOffset: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(deadline.timeIntervalSince(context.date.addingTimeInterval(serverOffset)).rounded(.up))
            Text(remaining > 0 ? "\(remaining) s to respond" : "Time's up")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(remaining > 5 ? Color.yellow : Color.red)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(remaining > 0 ? "\(remaining) seconds to respond" : "Time is up")
        }
    }
}

private struct OkayButton: View {
    let awaiting: Bool
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                Text(pending ? "Sending…" : "I'm okay")
                    .font(.title3.weight(.heavy))
            }
            .frame(maxWidth: .infinity, minHeight: awaiting ? 92 : 70)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(pending)
        .doubleTapConfirms()
        .accessibilityLabel("I'm okay")
        .accessibilityHint(awaiting ? "Answers the check-in. You can also double tap." : "Records that you're okay.")
    }
}

private struct HelpButton: View {
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(pending ? "Sending…" : "Get help", systemImage: "sos")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(pending)
        .accessibilityHint("Immediately alerts your responders.")
    }
}

private extension View {
    /// Native double tap (Apple Watch Series 9 / Ultra 2 or later, watchOS 11+)
    /// triggers only the visible safety confirmation. The button always works too.
    @ViewBuilder
    func doubleTapConfirms() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
