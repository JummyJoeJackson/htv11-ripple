import RippleKit
import SwiftUI

/// One large circle, a short status line under it, and a countdown inside the
/// circle when a check-in is waiting (then the circle fills the screen alone). No contacts or settings here.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let display = store.display
        ZStack {
        WatchBackground()
        VStack(spacing: 4) {
            RippleCircle(
                label: display.circleLabel,
                sending: store.sending,
                mode: display.mode,
                medsDue: display.medsDueAt != nil,
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
                          color: feedback.ok ? WatchColors.text : Theme.checkIn)
                    .task(id: feedback.id) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if store.feedback?.id == feedback.id { store.feedback = nil }
                    }
            } else if store.showHoldHint {
                WatchNote(text: "Hold to stop.", systemImage: "hand.tap.fill", color: WatchColors.text)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        store.showHoldHint = false
                    }
            } else if !store.phoneReachable || !display.phoneAvailable {
                WatchNote(text: "iPhone not available", systemImage: "iphone.slash", color: Theme.checkIn)
            } else if display.mode != .checkIn {
                // During a check-in the circle fills the screen with nothing under it.
                StatusLine(text: display.status, mode: display.mode, medsDue: display.medsDueAt != nil)
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

            if let hint = store.handGestureHint {
                Text(hint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WatchColors.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            if let gesture = store.lastHandGesture {
                VStack(spacing: 1) {
                    Text("Gesture #\(store.handGestureCount): \(gesture)")
                    if !store.handGestureStatus.isEmpty && store.handGestureStatus != store.handGestureHint {
                        Text(store.handGestureStatus)
                    }
                }
                .font(.caption2)
                .foregroundStyle(WatchColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            Image("RippleMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: 26)
                .padding(.leading, 8)
                .offset(y: -20)
                .accessibilityHidden(true)
        }
        // Coming back to the front restarts whatever the system stopped, straight away.
        .onChange(of: scenePhase) { _, _ in store.refreshRuntime() }
        .confirmationDialog("Stop monitoring?", isPresented: Binding(get: { store.confirmStop }, set: { store.confirmStop = $0 })) {
            Button("Stop monitoring", role: .destructive) { store.confirmStopMonitoring() }
            Button("Keep monitoring", role: .cancel) {}
        }
    }
}

/// The light, calm look: a pale blue wave background with navy text.
enum WatchColors {
    static let text = Color(red: 0x0B / 255, green: 0x2E / 255, blue: 0x4A / 255)
    static let secondaryText = Color(red: 0x3D / 255, green: 0x54 / 255, blue: 0x68 / 255)
}

/// Pale blue waves behind everything. Decorative only.
private struct WatchBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0xEA / 255, green: 0xF5 / 255, blue: 0xFC / 255)
            Image("WatchBackground")
                .resizable()
                .scaledToFill()
                .opacity(0.9)
            // watchOS always draws the clock in white, so a soft blue band at
            // the top keeps it (and the logo) readable.
            LinearGradient(stops: [.init(color: Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB2 / 255).opacity(0.9), location: 0),
                                   .init(color: Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB2 / 255).opacity(0), location: 0.24)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A bold status title and a short line saying what to do, in words, so the
/// circle's color is never the only cue.
private struct StatusLine: View {
    let text: String
    let mode: CircleMode
    var medsDue = false

    private var subtitle: String {
        if medsDue { return "Tap when you've taken them" }
        switch mode {
        case .off: return "Tap to start"
        case .monitoring: return "Hold to stop"
        case .checkIn: return "Are you okay? Tap"
        case .alertSent: return "Contacts notified"
        case .responding: return "Help is on the way"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.headline.weight(.bold))
                .foregroundStyle(WatchColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(WatchColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(text). \(subtitle)")
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
    var sending = false
    let mode: CircleMode
    /// A dose is due: the circle becomes a teal pill button for "Took my meds".
    var medsDue = false
    let deadline: Date?
    let doubleTapEnabled: Bool
    let swipesEnabled: Bool
    let onTap: (DismissMethod) -> Void
    let onHold: () -> Void
    let onSwipe: (GestureStep) -> Void

    @State private var holdFired = false
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 40
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
                RippleRings(color: circleColor)
                if let deadline {
                    // Check-in: a light disc with an amber ring that empties as time
                    // runs out, as big as the screen allows.
                    Circle()
                        .fill(.white.opacity(0.85))
                        .padding(6)
                    CountdownRing(deadline: deadline, size: countdownSize)
                        .padding(6)
                } else {
                    Circle()
                        .fill(circleColor.gradient)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                        .shadow(color: circleColor.opacity(0.45), radius: 6, y: 2)
                        .padding(24)
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: medsDue ? "pills.fill" : mode.watchSymbol)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
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

    private var circleColor: Color { medsDue ? Theme.primary : mode.ringColor }

    private var hint: String {
        if medsDue { return "Tap when you've taken your medication." }
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

/// The seconds left, inside an amber ring that empties as time runs out. The
/// Watch isn't told the alarm's full length, so the ring measures from the
/// moment this countdown first appeared.
private struct CountdownRing: View {
    let deadline: Date
    let size: CGFloat
    @State private var total: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, deadline.timeIntervalSince(context.date))
            let fraction = total > 0 ? min(1, left / total) : 1
            ZStack {
                Circle()
                    .stroke(Theme.checkIn.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.checkIn, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // Two digits must stay on one line inside the ring, even when
                // the circle is small or the text size is large.
                Text("\(Int(left.rounded(.up)))s")
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 12)
                    .foregroundStyle(WatchColors.text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(left.rounded(.up))) seconds to answer")
        }
        .onAppear { total = max(1, deadline.timeIntervalSinceNow) }
        .onChange(of: deadline) { _, new in total = max(1, new.timeIntervalSinceNow) }
    }
}

/// A soft halo, plus thin rings that keep spreading out from the edge of the
/// button and fading, staggered like ripples from a pebble dropped in water.
/// With Reduce Motion on, only the still halo shows. Decorative only.
private struct RippleRings: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    /// How many ripples are travelling outward at once.
    private let rippleCount = 3
    /// Seconds for one ripple to travel from the button to the edge.
    private let period: Double = 2.6

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // The still halo: soft filled rings, gently breathing.
                ForEach(0..<3) { ring in
                    Circle()
                        .fill(color.opacity(0.08 + Double(2 - ring) * 0.04))
                        .padding(CGFloat(ring) * 8)
                        .scaleEffect(breathe && !reduceMotion ? 1.03 : 0.98)
                }
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate / period
                        // A ZStack keeps the ripples centered on each other.
                        ZStack {
                            ForEach(0..<rippleCount, id: \.self) { index in
                                let progress = (t + Double(index) / Double(rippleCount)).truncatingRemainder(dividingBy: 1)
                                ripple(progress: progress, side: side)
                            }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityHidden(true)
    }

    /// One ripple partway out. It starts at the button's edge, strong and
    /// thick, and eases outward, thinning and fading like a wave losing energy.
    private func ripple(progress: Double, side: CGFloat) -> some View {
        let eased = 1 - pow(1 - progress, 2)
        let start = 0.62
        let size = side * (start + (1.02 - start) * eased)
        return Circle()
            .stroke(color.opacity(0.6 * (1 - progress)), lineWidth: 3.5 - 2.5 * progress)
            .frame(width: size, height: size)
    }
}

private extension CircleMode {
    /// Green monitoring, amber check-in, red alert, blue responding, gray off.
    var ringColor: Color {
        switch self {
        case .off: return Theme.off
        case .monitoring: return Theme.safe
        case .checkIn: return Theme.checkIn
        case .alertSent: return Theme.alert
        case .responding: return Theme.responding
        }
    }

    var watchSymbol: String {
        switch self {
        case .off: return "power"
        case .monitoring: return "checkmark"
        case .checkIn: return "bell.fill"
        case .alertSent: return "exclamationmark"
        case .responding: return "person.2.fill"
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
            .foregroundStyle(heard.isEmpty ? WatchColors.text : WatchColors.secondaryText)
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
        .background(WatchBackground())
    }
}

#Preview("Monitoring") { CirclePreview(label: "Stop", status: "Monitoring", mode: .monitoring) }
#Preview("Check in") { CirclePreview(label: "I'm okay", status: "Check in", mode: .checkIn, deadline: .now.addingTimeInterval(14)) }
#Preview("Alert sent") { CirclePreview(label: "I'm okay now", status: "Alert sent", mode: .alertSent) }
#Preview("Responding") { CirclePreview(label: "I'm okay now", status: "Maya is responding", mode: .responding) }
#Preview("Check in, largest text") {
    CirclePreview(label: "I'm okay", status: "Check in", mode: .checkIn, deadline: .now.addingTimeInterval(14))
        .dynamicTypeSize(.accessibility3)
}
#Preview("Alert sent, largest text") {
    CirclePreview(label: "I'm okay now", status: "Alert sent", mode: .alertSent)
        .dynamicTypeSize(.accessibility3)
}
