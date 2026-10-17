import RippleKit
import SwiftUI

/// First-run flow: a splash with "Get started" and "How it works" (two short
/// intro pages), then profile (no login), a first contact, how you answer,
/// location permission, and the server address. Connecting is the
/// last step because it finishes setup and opens the app; the name and
/// contact are saved on this iPhone before that, through the usual save.
struct OnboardingView: View {
    @Environment(WearerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .splash

    @State private var firstName = ""
    @State private var lastName = ""

    var body: some View {
        if step == .splash {
            SplashScreen(onStart: { go(.profile) }, onLearnMore: { go(.welcome(0)) })
                .transition(.opacity)
                .onAppear(perform: fillName)
        } else {
            flow
        }
    }

    private var flow: some View {
        VStack(spacing: 0) {
            if let progress = step.progress {
                StepProgress(current: progress, total: OnboardingStep.setupStepCount, onBack: goBack)
            }
            Group {
                switch step {
                case .splash:
                    EmptyView()
                case .welcome(let page):
                    WelcomePage(page: page, onNext: { next(after: step) }, onSkip: { go(.profile) })
                case .profile:
                    ProfileStep(firstName: $firstName, lastName: $lastName) { go(.contact) }
                case .contact:
                    ContactStep { go(.answer) }
                case .answer:
                    AnswerStep { go(.permissions) }
                case .permissions:
                    PermissionsStep { go(.server) }
                case .server:
                    ServerStep(fullName: fullName)
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                              removal: .opacity))
        }
        .rippleScreen(background: .three)
        .onAppear(perform: fillName)
    }

    /// "Set up again" keeps the saved name, so fill it back in.
    private func fillName() {
        if firstName.isEmpty {
            let parts = store.config.wearerName.split(separator: " ", maxSplits: 1).map(String.init)
            firstName = parts.first ?? ""
            lastName = parts.count > 1 ? parts[1] : ""
        }
    }

    private var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func go(_ newStep: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { step = newStep }
    }

    private func next(after current: OnboardingStep) {
        if case .welcome(let page) = current {
            go(page < WelcomePage.count - 1 ? .welcome(page + 1) : .profile)
        }
    }

    private func goBack() {
        switch step {
        case .splash: break
        case .welcome(let page): go(page > 0 ? .welcome(page - 1) : .splash)
        case .profile: go(.splash)
        case .contact: go(.profile)
        case .answer: go(.contact)
        case .permissions: go(.answer)
        case .server: go(.permissions)
        }
    }
}

enum OnboardingStep: Hashable {
    case splash
    case welcome(Int)
    case profile, contact, answer, permissions, server

    static let setupStepCount = 5

    /// "Step n of 5" for the setup steps; the welcome pages have their own dots.
    var progress: Int? {
        switch self {
        case .splash, .welcome: return nil
        case .profile: return 1
        case .contact: return 2
        case .answer: return 3
        case .permissions: return 4
        case .server: return 5
        }
    }
}

// MARK: - Shared pieces

/// Back link, "Step 2 of 4" and a progress bar.
private struct StepProgress: View {
    let current: Int
    let total: Int
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(Theme.labelBold)
                        .frame(minWidth: Theme.minTarget, minHeight: 44, alignment: .leading)
                }
                .foregroundStyle(Theme.accent)
                .accessibilityHint("Goes to the previous step.")
                Spacer()
                Text("Step \(current) of \(total)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.secondaryText)
            }
            ProgressView(value: Double(current), total: Double(total))
                .tint(Theme.accent)
                .accessibilityLabel("Step \(current) of \(total)")
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
    }
}

/// A scrolling step with a title, subtitle and content, and its buttons
/// pinned to the bottom so they're always in reach.
private struct StepLayout<Content: View, Buttons: View>: View {
    var icon: String? = nil
    var showLogo = false
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if showLogo {
                    Image("RippleLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Ripple")
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 72, height: 72)
                        .background(Theme.iconTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(title))
                    .font(Theme.screenTitle)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringKey(subtitle))
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(Theme.spacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                buttons
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 12)
            .background(Theme.background)
        }
    }
}

/// Stacked text fields in one white card, each with its label above the value.
private struct FieldGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .rippleCard()
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(Theme.label)
                .foregroundStyle(Theme.secondaryText)
            TextField(placeholder, text: $text)
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalize)
                .autocorrectionDisabled(keyboard != .default)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Theme.listRowHeight, alignment: .leading)
    }
}

private struct FieldDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1).accessibilityHidden(true)
    }
}

/// A brand-blue text link for secondary actions like "Skip for now".
private struct TextLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(Theme.labelBold)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
    }
}

/// An error from setup, with an icon so it isn't shown by color alone.
private struct ErrorNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Theme.label)
            .foregroundStyle(Theme.checkIn)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Welcome

private struct WelcomePage: View {
    static let count = 2

    let page: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        let isLast = page == Self.count - 1
        StepLayout(icon: page == 0 ? "applewatch" : "lock.shield",
                   title: page == 0 ? "Answer with one tap" : "You stay in control",
                   subtitle: page == 0 ? "When your Watch buzzes, tell it you're okay. If you can't, your contacts get a text."
                                       : "You choose who gets texted. Ripple never tracks you.") {
            if isLast {
                FormNote("Hackathon prototype. Not a medical or emergency service.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            PageDots(current: page, total: Self.count)
                .padding(.top, 8)
        } buttons: {
            Button(isLast ? "Get started" : "Continue", action: onNext)
                .buttonStyle(.ripplePrimary)
            if !isLast {
                TextLinkButton(title: "Skip", action: onSkip)
            }
        }
    }
}

/// The first screen: a white-to-blue gradient, the logo, a one-line promise,
/// and two buttons, like a classic app welcome screen.
private struct SplashScreen: View {
    let onStart: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        ZStack {
            // White at the top fading to blue at the bottom, so the logo and
            // text sit on light color and the buttons on deep blue.
            LinearGradient(stops: [.init(color: Color(red: 0xF7 / 255, green: 0xFB / 255, blue: 0xFE / 255), location: 0),
                                   .init(color: Color(red: 0xD3 / 255, green: 0xEC / 255, blue: 0xFA / 255), location: 0.45),
                                   .init(color: Color(red: 0x4F / 255, green: 0xAE / 255, blue: 0xE0 / 255), location: 0.75),
                                   .init(color: Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB2 / 255), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    LanguagePicker()
                        .labelStyle(.titleAndIcon)
                        .tint(Theme.text)
                        .padding(.horizontal, 6)
                        .background(.white.opacity(0.7), in: Capsule())
                }
                Spacer()
                Image("RippleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 150)
                    .accessibilityLabel("Ripple")
                Text("Help when you can't ask for it.")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("If you can't answer your Watch, Ripple texts your people.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Spacer()
                Button(action: onStart) {
                    Text("Get started")
                        .font(Theme.button)
                        .foregroundStyle(Theme.onBrand)
                        .frame(maxWidth: .infinity, minHeight: Theme.secondaryButtonHeight)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts setup.")
                Button(action: onLearnMore) {
                    Text("How it works")
                        .font(Theme.button)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: Theme.secondaryButtonHeight)
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .environment(\.colorScheme, .light)
    }
}

private struct PageDots: View {
    let current: Int
    let total: Int
    /// White dots for use over the photo.
    var onPhoto = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(onPhoto ? Color.white.opacity(index == current ? 1 : 0.45) : (index == current ? Theme.accent : Theme.divider))
                    .frame(width: 10, height: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(total)")
    }
}

// MARK: - Profile (no login)

private struct ProfileStep: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onNext: () -> Void

    private var canContinue: Bool { !firstName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        StepLayout(icon: "person.crop.circle", title: "Create your profile",
                   subtitle: "Your contacts see this name.") {
            AvatarPicker(size: 72)
            FieldGroup {
                LabeledField(label: "First name", placeholder: "Alex", text: $firstName, contentType: .givenName)
                FieldDivider()
                LabeledField(label: "Last name (optional)", placeholder: "Chen", text: $lastName, contentType: .familyName)
            }
            FormNote("No email or password needed.")
        } buttons: {
            Button("Continue", action: onNext)
                .buttonStyle(.ripplePrimary)
                .disabled(!canContinue)
        }
    }
}

// MARK: - First contact

private struct ContactStep: View {
    @Environment(WearerStore.self) private var store
    let onNext: () -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var shareLocation = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Phone.normalize(phone) != nil
    }

    var body: some View {
        let existing = store.config.contacts
        StepLayout(icon: "person.2", title: "Add someone to text",
                   subtitle: "Someone who can check on you.") {
            if !existing.isEmpty {
                Card {
                    Label(existing.count == 1 ? "\(existing[0].name) is in your contacts." : "You have \(existing.count) contacts.",
                          systemImage: "checkmark.circle.fill")
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.safe)
                }
            }
            FieldGroup {
                LabeledField(label: "Their name", placeholder: "Maya Chen", text: $name, contentType: .name)
                FieldDivider()
                LabeledField(label: "Their phone number", placeholder: "416 555 0101", text: $phone,
                             contentType: .telephoneNumber, keyboard: .phonePad, autocapitalize: .never)
                FieldDivider()
                Toggle("Share my location with them in alerts", isOn: $shareLocation)
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
                    .padding(.horizontal, 20)
                    .frame(minHeight: Theme.listRowHeight)
            }
        } buttons: {
            Button(existing.isEmpty ? "Save contact" : "Add contact") { save() }
                .buttonStyle(.ripplePrimary)
                .disabled(!canSave)
            TextLinkButton(title: existing.isEmpty ? "Skip for now" : "Continue", action: onNext)
        }
    }

    private func save() {
        var config = store.config
        config.contacts.append(PermanentContact(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                phone: phone, tier: .one, shareLocation: shareLocation))
        store.save(config)
        onNext()
    }
}

// MARK: - How you answer

/// Pick the main way to answer an alarm (tap, gesture or voice) and set it
/// up. Saved with the usual save, so the Watch gets it.
private struct AnswerStep: View {
    @Environment(WearerStore.self) private var store
    let onNext: () -> Void
    @State private var choice: AnswerChoice?

    var body: some View {
        StepLayout(icon: "hand.tap", title: "How will you answer?",
                   subtitle: "Pick what's easiest for you.") {
            if let binding = Binding($choice) {
                AnswerMethodPicker(choice: binding)
            }
        } buttons: {
            Button("Continue") {
                if let choice {
                    let updated = choice.applied(to: store.config)
                    if updated != store.config { store.save(updated) }
                }
                onNext()
            }
            .buttonStyle(.ripplePrimary)
            .disabled(!(choice?.isComplete ?? true))
        }
        .onAppear {
            if choice == nil { choice = AnswerChoice(store.config) }
        }
    }
}

// MARK: - Permissions

private struct PermissionsStep: View {
    @Environment(WearerStore.self) private var store
    let onNext: () -> Void

    var body: some View {
        StepLayout(icon: "location", title: "Allow location",
                   subtitle: "Only sent with an alert.") {
            Card {
                PermissionStepRow(number: 1, text: "Tap \"Allow location\" below.")
                PermissionStepRow(number: 2, text: "Choose \"Allow While Using App\".")
            }
            // The permission status isn't observable, so re-read it every second.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                StatusRow(label: "Location for Ripple", value: store.location.statusText)
                    .padding(.horizontal, 4)
            }
        } buttons: {
            Button("Allow location") {
                store.location.requestPermission()
                onNext()
            }
            .buttonStyle(.ripplePrimary)
            TextLinkButton(title: "Not now", action: onNext)
        }
    }
}

private struct PermissionStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Theme.labelBold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accent, in: Circle())
                .accessibilityHidden(true)
            Text(LocalizedStringKey(text))
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

// MARK: - Server (finishes setup)

private struct ServerStep: View {
    @Environment(WearerStore.self) private var store
    let fullName: String

    @State private var address = ""
    @State private var working = false

    var body: some View {
        StepLayout(icon: "network", title: "Connect to Ripple",
                   subtitle: "The address your Ripple server shows.") {
            FieldGroup {
                LabeledField(label: "Server address", placeholder: "192.168.1.20:8080", text: $address,
                             contentType: .URL, keyboard: .URL, autocapitalize: .never)
            }
            FormNote("Simulator: localhost:8080")
            if let banner = store.banner, !banner.ok {
                ErrorNote(text: banner.text)
            }
        } buttons: {
            Button(working ? "Connecting…" : "Connect") {
                Task {
                    working = true
                    _ = await store.setUp(serverAddress: address, name: fullName)
                    working = false
                }
            }
            .buttonStyle(.ripplePrimary)
            .disabled(working || address.trimmingCharacters(in: .whitespaces).isEmpty || fullName.isEmpty)
            .accessibilityHint("Finishes setup and opens Ripple.")
        }
        .onAppear {
            if address.isEmpty {
                #if targetEnvironment(simulator)
                address = store.serverAddress.isEmpty ? "localhost:8080" : store.serverAddress
                #else
                address = store.serverAddress
                #endif
            }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView().environment(WearerStore())
}

#Preview("Onboarding, largest text") {
    OnboardingView().environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
