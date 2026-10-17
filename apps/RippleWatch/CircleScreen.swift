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
///
/// With swipe combos on: swipe up twice asks for help in any state; swipe
/// down twice is "I'm okay" during an alarm. With the voice phrase on, the
/// microphone listens for it during an alarm without anything to press.
/// While monitoring, a button under the circle starts a walk session.
struct CircleScreen: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let display = store.display
        VStack(spacing: 6) {
            RippleCircle(
                label: store.sending ? "…" : display.circleLabel,
                mode: display.mode,
                deadline: display.mode == .checkIn ? display.deadline : nil,
                doubleTapEnabled: store.config.doubleTapEnabled && display.mode.isAlarm,
                swipesEnabled: store.config.combosEnabled,
                onTap: { method in store.tapCircle(method: method) },
                onHold: { store.holdCircle() },
                onSwipe: { step in store.swipe(step) }
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: display.mode)
            // VoiceOver uses swipes to move around, so it gets help as a named action.
            .accessibilityAction(named: Text("Get help")) { store.requestHelp() }

            // The countdown is inside the circle. Feedback shows during a check-in
            // too, so "Swipe down again" appears under the circle.
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

            if store.config.walkEnabled && display.mode == .monitoring {
                WalkButton(walking: store.walking, steps: store.walkSteps, stillSince: store.walkStillSince,
                           stopAfter: store.config.walkStopSeconds) {
                    store.toggleWalk()
                }
                .disabled(store.sending)
            }

            if store.config.voiceEnabled && display.mode.isAlarm {
                if store.listening {
                    ListeningLabel(phrase: store.config.voicePhrase, heard: store.heardText)
                } else {
                    VoiceButton(phrase: store.config.voicePhrase) { text in
                        store.voiceInput(text)
                    }
                }
            }

            if let gesture = store.lastHandGesture {
                VStack(spacing: 1) {
                    Text("Gesture #\(store.handGestureCount): \(gesture)")
                    if !store.handGestureStatus.isEmpty {
                        Text(store.handGestureStatus)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        // Coming back to the front restarts whatever the system stopped, straight away.
        .onChange(of: scenePhase) { _, _ in store.refreshRuntime() }
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
/// for 2 seconds runs the hold action instead (never both). With combos on,
/// a vertical swipe is a combo step and never also counts as a tap. A shaky
/// tap that wanders and comes back is still a tap.
private struct RippleCircle: View {
    let label: String
    let mode: CircleMode
    let deadline: Date?
    let doubleTapEnabled: Bool
    let swipesEnabled: Bool
    let onTap: (DismissMethod) -> Void
    let onHold: () -> Void
    let onSwipe: (GestureStep) -> Void

    @State private var holdFired = false
    @ScaledMetric(relativeTo: .title3) private var labelSize: CGFloat = 26
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 38
    /// The current touch has travelled far enough to be a swipe.
    @State private var swiping = false
    @State private var lastSwipeAt = Date.distantPast

    var body: some View {
        Button {
            if holdFired {
                holdFired = false
                return
            }
            // A swipe that ends on the circle can also end a button press.
            if swiping || Date().timeIntervalSince(lastSwipeAt) < 0.5 { return }
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    swiping = swipesEnabled && Self.step(value.translation) != nil
                }
                .onEnded { value in
                    swiping = false
                    guard swipesEnabled, let step = Self.step(value.translation) else { return }
                    lastSwipeAt = Date()
                    onSwipe(step)
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

    /// Net travel from where the finger went down, so tremor that comes back cancels out.
    private static func step(_ translation: CGSize) -> GestureStep? {
        GestureStep.swipe(dx: Double(translation.width), dy: Double(translation.height))
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

/// Starts or ends a walk session while monitoring. During a walk it shows the
/// step count, and how long the wearer has been still once a stop would count,
/// so it's clear steps are being counted, even after the screen was off.
private struct WalkButton: View {
    let walking: Bool
    let steps: Int
    let stillSince: Date?
    let stopAfter: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                Label(walking ? "End walk · \(steps) steps" : "Start walk", systemImage: "figure.walk")
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .tint(walking ? .orange : .green)
            .accessibilityLabel(walking ? "End walk. \(steps) steps so far." : "Start walk")
            .accessibilityHint("During a walk, if your steps stop for a while, Ripple checks in.")

            if walking, let stillSince {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let still = max(0, Int(context.date.timeIntervalSince(stillSince)))
                    if still >= 3 {
                        Text("Still \(still) s of \(stopAfter) s")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Still for \(still) seconds. Ripple checks in at \(stopAfter).")
                    }
                }
            }
        }
    }
}

/// Shown while the microphone listens for the phrase during an alarm. Once
/// something is heard it shows the words, so the wearer knows it's working.
private struct ListeningLabel: View {
    let phrase: String
    let heard: String

    var body: some View {
        Label(heard.isEmpty ? "Say \"\(phrase)\"" : "\"\(heard)\"", systemImage: "waveform")
            .font(.footnote)
            .foregroundStyle(heard.isEmpty ? Color.primary : Color.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .minimumScaleFactor(0.7)
            .accessibilityLabel("Listening. Say \(phrase) to dismiss.")
    }
}

/// Dismiss by saying the configured phrase, using Watch dictation while the
/// app is open. The fallback when the microphone can't listen by itself.
/// Always a normal dismissal; duress stays touch only.
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
            RippleCircle(label: label, mode: mode, deadline: deadline, doubleTapEnabled: false, swipesEnabled: false,
                         onTap: { _ in }, onHold: {}, onSwipe: { _ in })
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
