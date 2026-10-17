import RippleKit
import SwiftUI

/// The main way the wearer answers an alarm. Touch always works on top of
/// whichever one is picked.
enum AnswerMethod: CaseIterable {
    case tap, gesture, voice

    init(_ config: RippleConfig) {
        if config.voiceEnabled { self = .voice } else if config.doubleTapEnabled { self = .gesture } else { self = .tap }
    }

    var title: String {
        switch self {
        case .tap: return "Tap"
        case .gesture: return "Gesture"
        case .voice: return "Voice"
        }
    }

    var detail: String {
        switch self {
        case .tap: return "Tap the circle on your Watch"
        case .gesture: return "Pinch your fingers twice"
        case .voice: return "Say a short phrase"
        }
    }

    var icon: String {
        switch self {
        case .tap: return "hand.tap.fill"
        case .gesture: return "hand.pinch.fill"
        case .voice: return "mic.fill"
        }
    }
}

/// What the wearer picked, ready to write into the config.
struct AnswerChoice: Equatable {
    var method: AnswerMethod = .tap
    var phrase = ""
    var combos = false

    init(_ config: RippleConfig) {
        method = AnswerMethod(config)
        phrase = config.voicePhrase
        combos = config.combosEnabled
    }

    var isComplete: Bool { method != .voice || !phrase.trimmingCharacters(in: .whitespaces).isEmpty }

    func applied(to config: RippleConfig) -> RippleConfig {
        var updated = config
        updated.doubleTapEnabled = method == .gesture
        updated.voiceEnabled = method == .voice
        updated.voicePhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.combosEnabled = combos
        return updated
    }
}

/// Pick one way to answer, then a short setup for it. Used in onboarding and
/// in Settings, so there's only one place this is set up.
struct AnswerMethodPicker: View {
    @Binding var choice: AnswerChoice

    var body: some View {
        VStack(spacing: 12) {
            ForEach(AnswerMethod.allCases, id: \.self) { method in
                MethodCard(method: method, selected: choice.method == method) {
                    choice.method = method
                }
            }

            MethodSetup(choice: $choice)

            Toggle(isOn: $choice.combos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also allow swipes")
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Up twice for help, down twice for okay")
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)
            .padding(16)
            .frame(minHeight: Theme.listRowHeight)
            .rippleCard()
        }
    }
}

/// One way to answer, as a big single-choice card.
private struct MethodCard: View {
    let method: AnswerMethod
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: method.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? .white : Theme.accent)
                    .frame(width: 52, height: 52)
                    .background(selected ? Theme.accent : Theme.iconTint, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(method.title))
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(LocalizedStringKey(method.detail))
                        .font(Theme.label)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: Theme.listRowHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.divider, lineWidth: selected ? 2 : 1))
                    .shadow(color: Theme.shadowColor, radius: Theme.shadowRadius, y: Theme.shadowY)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(method.title). \(method.detail)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The short setup for the picked method.
private struct MethodSetup: View {
    @Binding var choice: AnswerChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch choice.method {
            case .tap:
                SetupLine(icon: "applewatch", text: "When your Watch buzzes, tap the big circle.")
            case .gesture:
                SetupLine(icon: "hand.pinch", text: "Pinch your thumb and finger together twice.")
                SetupLine(icon: "applewatch", text: "Needs Apple Watch Series 9 or later.")
            case .voice:
                Text("Your phrase")
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
                TextField("I'm okay", text: $choice.phrase)
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.sentences)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Your phrase")
                SetupLine(icon: "ear", text: "Your Watch listens for it during an alarm.")
            }
            SetupLine(icon: "hand.tap", text: "Tapping the circle always works too.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.iconTint.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct SetupLine: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(LocalizedStringKey(text))
                .font(Theme.label)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.accent)
        }
    }
}

/// Settings → How you answer: the same picker, with a Save button.
struct AnswerSetupScreen: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choice: AnswerChoice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let binding = Binding($choice) {
                    AnswerMethodPicker(choice: binding)
                    Button("Save") {
                        store.save(binding.wrappedValue.applied(to: store.config))
                        store.banner = Banner(text: "Saved. Sending to your Watch.", ok: true)
                        dismiss()
                    }
                    .buttonStyle(.ripplePrimary)
                    .disabled(!binding.wrappedValue.isComplete)
                }
            }
            .padding(Theme.spacing)
        }
        .rippleScreen(background: .three)
        .navigationTitle("How you answer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if choice == nil { choice = AnswerChoice(store.config) }
        }
    }
}

#Preview("How you answer") {
    NavigationStack { AnswerSetupScreen() }.environment(WearerStore())
}
