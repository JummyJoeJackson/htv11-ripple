import RippleKit
import SwiftUI

/// One large circle, a short status line under it, and a countdown inside the
/// circle when a check-in is waiting. No contacts or settings here.
///
/// | State            | Label        | Tap                      | Hold 2 s                     |
/// | Monitoring off   | Start        | Start monitoring         | Same as tap                  |
/// | Monitoring on    | Stop         | "Hold to stop." only     | Asks "Stop monitoring?"      |
/// | Alarm pending    | I'm okay     | Dismiss, keep monitoring | Duress: looks like dismissal |
/// | Alert sent       | I'm okay now | Okay-now texts, close    | Duress: looks like dismissal |
struct CircleScreen: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let display = store.display
        VStack(spacing: 6) {
            RippleCircle(
                label: store.sending ? "…" : display.circleLabel,
                mode: display.mode,
                deadline: display.mode == .checkIn ? display.deadline : nil,
                doubleTapEnabled: store.config.doubleTapEnabled && display.mode.isAlarm,
                onTap: { method in store.tapCircle(method: method) },
                onHold: { store.holdCircle() }
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: display.mode)

            if let feedback = store.feedback {
                WatchNote(text: feedback.text, systemImage: feedback.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                          color: feedback.ok ? .white : Theme.primaryTint)
                    .task(id: feedback.id) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if store.feedback?.id == feedback.id { store.feedback = nil }
                    }
            } else if store.showHoldHint {
                WatchNote(text: "Hold to stop.", systemImage: "hand.tap.fill", color: .white)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        store.showHoldHint = false
                    }
            } else if !store.phoneReachable || !display.phoneAvailable {
                WatchNote(text: "iPhone not available", systemImage: "iphone.slash", color: Theme.primaryTint)
            } else {
                StatusLine(text: display.status, mode: display.mode)
            }

            if store.config.voiceEnabled && display.mode.isAlarm {
                VoiceButton(phrase: store.config.voicePhrase) { text in
                    store.voiceInput(text)
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .confirmationDialog("Stop monitoring?", isPresented: Binding(get: { store.confirmStop }, set: { store.confirmStop = $0 })) {
            Button("Stop monitoring", role: .destructive) { store.confirmStopMonitoring() }
            Button("Keep monitoring", role: .cancel) {}
        }
    }
}

/// Short status under the circle, always with an icon so color isn't the only cue.
private struct StatusLine: View {
    let text: String
    let mode: CircleMode

    var body: some View {
        Label(text, systemImage: mode.symbol)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Status: \(text)")
            .accessibilityAddTraits(.isHeader)
    }
}

private struct WatchNote: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
    }
}

/// The circle. Tap and native double tap run the visible action; holding
/// for 2 seconds runs the hold action instead (never both).
private struct RippleCircle: View {
    let label: String
    let mode: CircleMode
    let deadline: Date?
    let doubleTapEnabled: Bool
    let onTap: (DismissMethod) -> Void
    let onHold: () -> Void

    @State private var holdFired = false
    @ScaledMetric(relativeTo: .title3) private var labelSize: CGFloat = 26
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 38

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
                    .fill(mode.circleColor)
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 3)
                VStack(spacing: 0) {
                    Text(label)
                        .font(.system(size: labelSize, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let deadline {
                        WatchCountdown(deadline: deadline, size: countdownSize)
                    }
                }
                .padding(14)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .accessibilityHint(hint)
    }

    private var hint: String {
        switch mode {
        case .off: return "Tap to start monitoring."
        case .monitoring: return "Hold for two seconds to stop monitoring."
        case .checkIn: return "Tap to answer the check-in."
        case .alertSent, .responding: return "Tap to tell your contacts you're okay."
        }
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
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
            Text("\(remaining)")
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .accessibilityLabel("\(remaining) seconds to answer")
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
                .font(.headline)
                .frame(minHeight: 44)
        } onSubmit: { text in
            onText(text)
        }
        .accessibilityHint("Answer by saying your phrase.")
    }
}

// MARK: - Previews

/// The Watch screen as CircleScreen lays it out, with sample states.
private struct CirclePreview: View {
    let label: String
    let status: String
    let mode: CircleMode
    var deadline: Date? = nil

    var body: some View {
        VStack(spacing: 6) {
            RippleCircle(label: label, mode: mode, deadline: deadline, doubleTapEnabled: false, onTap: { _ in }, onHold: {})
            StatusLine(text: status, mode: mode)
        }
        .padding(.horizontal, 2)
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview("Monitoring") { CirclePreview(label: "Stop", status: "Monitoring", mode: .monitoring) }
#Preview("Check in") { CirclePreview(label: "I'm okay", status: "Check in", mode: .checkIn, deadline: .now.addingTimeInterval(14)) }
#Preview("Alert sent") { CirclePreview(label: "I'm okay now", status: "Alert sent", mode: .alertSent) }
#Preview("Check in, largest text") {
    CirclePreview(label: "I'm okay", status: "Check in", mode: .checkIn, deadline: .now.addingTimeInterval(14))
        .dynamicTypeSize(.accessibility3)
}
#Preview("Alert sent, largest text") {
    CirclePreview(label: "I'm okay now", status: "Alert sent", mode: .alertSent)
        .dynamicTypeSize(.accessibility3)
}
