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
///
/// With swipe combos on: swipe up twice asks for help in any state; swipe
/// down twice is "I'm okay" during an alarm. With the voice phrase on, the
/// microphone listens for it during an alarm without anything to press.
struct CircleScreen: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

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
                swipesEnabled: store.config.combosEnabled,
                onTap: { method in store.tapCircle(method: method) },
                onHold: { store.holdCircle() },
                onSwipe: { step in store.swipe(step) }
            )
            // VoiceOver uses swipes to move around, so it gets help as a named action.
            .accessibilityAction(named: Text("Get help")) { store.requestHelp() }

            if let deadline = display.deadline, display.mode == .checkIn {
                WatchCountdown(deadline: deadline)
            }
            // Shown during a check-in too, so "Swipe down again" appears under the countdown.
            if let feedback = store.feedback {
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
        .padding(.horizontal, 4)
        // Coming back to the front restarts whatever the system stopped, straight away.
        .onChange(of: scenePhase) { _, _ in store.refreshRuntime() }
        .confirmationDialog("Stop monitoring?", isPresented: Binding(get: { store.confirmStop }, set: { store.confirmStop = $0 })) {
            Button("Stop monitoring", role: .destructive) { store.confirmStopMonitoring() }
            Button("Keep monitoring", role: .cancel) {}
        }
    }
}

/// The circle. Tap and native double tap run the visible action; holding
/// for 2 seconds runs the hold action instead (never both). With combos on,
/// a vertical swipe is a combo step and never also counts as a tap. A shaky
/// tap that wanders and comes back is still a tap.
private struct RippleCircle: View {
    let label: String
    let color: Color
    let doubleTapEnabled: Bool
    let swipesEnabled: Bool
    let onTap: (DismissMethod) -> Void
    let onHold: () -> Void
    let onSwipe: (GestureStep) -> Void

    @State private var holdFired = false
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
        .accessibilityHint("Tap to \(label.lowercased()). Hold for two seconds for more.")
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
                .font(.footnote)
        } onSubmit: { text in
            onText(text)
        }
    }
}
