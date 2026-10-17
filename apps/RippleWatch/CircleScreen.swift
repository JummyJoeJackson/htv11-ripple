import RippleKit
import SwiftUI

/// One large circle, a short status label, and a countdown when an alarm is
/// pending. No contacts or settings here.
///
/// | State            | Label        | Tap                      | Hold 2 s                     |
/// | Monitoring off   | Start        | Start monitoring         | Same as tap                  |
/// | Monitoring on    | Stop         | "Hold to stop." only     | Asks "Stop monitoring?"      |
/// | Alarm pending    | I'm okay     | Dismiss, keep monitoring | Duress: looks like dismissal |
/// | Alert sent       | I'm okay now | Okay-now texts, close    | Duress: looks like dismissal |
struct CircleScreen: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let display = store.display
        VStack(spacing: 6) {
            Text(display.status)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            RippleCircle(
                label: store.sending ? "…" : display.circleLabel,
                color: display.mode.color,
                doubleTapEnabled: store.config.doubleTapEnabled && display.mode.isAlarm,
                onTap: { method in store.tapCircle(method: method) },
                onHold: { store.holdCircle() }
            )

            if let deadline = display.deadline, display.mode == .checkIn {
                WatchCountdown(deadline: deadline)
            } else if let feedback = store.feedback {
                Text(feedback.text)
                    .font(.footnote)
                    .foregroundStyle(feedback.ok ? Color.primary : Color.orange)
                    .multilineTextAlignment(.center)
                    .task(id: feedback.id) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if store.feedback?.id == feedback.id { store.feedback = nil }
                    }
            } else if store.showHoldHint {
                Text("Hold to stop.")
                    .font(.footnote)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        store.showHoldHint = false
                    }
            } else if !store.phoneReachable || !display.phoneAvailable {
                Label("iPhone not available", systemImage: "iphone.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if store.config.voiceEnabled && display.mode.isAlarm {
                VoiceButton(phrase: store.config.voicePhrase) { text in
                    store.voiceInput(text)
                }
            }
        }
        .padding(.horizontal, 4)
        .confirmationDialog("Stop monitoring?", isPresented: Binding(get: { store.confirmStop }, set: { store.confirmStop = $0 })) {
            Button("Stop monitoring", role: .destructive) { store.confirmStopMonitoring() }
            Button("Keep monitoring", role: .cancel) {}
        }
    }
}

/// The circle. Tap and native double tap run the visible action; holding
/// for 2 seconds runs the hold action instead (never both).
private struct RippleCircle: View {
    let label: String
    let color: Color
    let doubleTapEnabled: Bool
    let onTap: (DismissMethod) -> Void
    let onHold: () -> Void

    @State private var holdFired = false

    var body: some View {
        Button {
            if holdFired {
                holdFired = false
                return
            }
            onTap(.touch)
        } label: {
            ZStack {
                Circle()
                    .fill(color.gradient)
                Text(label)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(color == .yellow ? Color.black : Color.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(10)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 2, maximumDistance: 40).onEnded { _ in
                holdFired = true
                onHold()
            }
        )
        .doubleTapShortcut(enabled: doubleTapEnabled)
        .accessibilityLabel(label)
        .accessibilityHint("Tap to \(label.lowercased()). Hold for two seconds for more.")
    }
}

private extension View {
    /// Native double tap (Apple Watch Series 9 / Ultra 2 or later on watchOS 11)
    /// runs the visible dismiss action only. It never triggers duress.
    @ViewBuilder
    func doubleTapShortcut(enabled: Bool) -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction, isEnabled: enabled)
        } else {
            self
        }
    }
}

private struct WatchCountdown: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text("\(remaining) s")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(remaining > 10 ? Color.yellow : Color.red)
                .accessibilityLabel("\(remaining) seconds to respond")
        }
    }
}

/// Dismiss by saying the configured phrase, using Watch dictation while the
/// app is open. Always a normal dismissal; duress stays touch only.
private struct VoiceButton: View {
    let phrase: String
    let onText: (String) -> Void

    var body: some View {
        TextFieldLink(prompt: Text("Say \"\(phrase)\"")) {
            Label("Say \"\(phrase)\"", systemImage: "mic.fill")
                .font(.footnote)
        } onSubmit: { text in
            onText(text)
        }
    }
}
