import RippleKit
import SwiftUI

/// Settings as a short menu. Each row opens its own page; pages that change
/// settings have their own Save, which sends the change to the Watch.
struct SettingsView: View {
    @Environment(WearerStore.self) private var store
    /// False when opened from Home, so the navigation bar keeps its Back button.
    var isTabRoot = true

    var body: some View {
        let config = store.config
        RippleForm {
            Section {
                ScreenHeader(title: "Settings", subtitle: nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                LanguagePicker()
            }

            Section {
                MenuRow(icon: "person.fill", title: "Profile", value: config.wearerName) { ProfileSettings() }
                MenuRow(icon: "doc.text", title: "Help card", value: config.helpCardEnabled ? "On" : "Off") { HelpCardSettings() }
            }

            Section {
                MenuRow(icon: "clock", title: "Timing",
                        value: config.checkInIntervalMinutes == 0 ? "\(config.countdownSeconds) s" : "Every \(config.checkInIntervalMinutes) min") { TimingSettings() }
                MenuRow(icon: "pills", title: "Medication", value: medicationSummary) { MedicationView() }
                MenuRow(icon: "heart.text.square", title: "Apple Watch alerts",
                        value: config.healthAlerts.isEmpty ? "Off" : "On") { HealthAlertSettings() }
            }

            Section {
                MenuRow(icon: AnswerMethod(config).icon, title: "How you answer", value: answerSummary) { AnswerSetupScreen() }
                MenuRow(icon: "hand.raised", title: "Hand gestures",
                        value: config.handGesturesEnabled || config.handGestureHelpEnabled ? "On" : "Off") { HandGestureSettings() }
            }

            Section {
                MenuRow(icon: "applewatch", title: "Watch and texting", value: watchSyncText) { WatchAndTextingSettings() }
                MenuRow(icon: "iphone", title: "Device", value: nil) { DeviceSettings() }
            }
        }
        .navigationTitle("Settings")
        .toolbar(isTabRoot ? .hidden : .visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Gesture", "Voice: “I'm okay”" or "Tap", plus swipes if on.
    private var answerSummary: String {
        let method = AnswerMethod(store.config)
        var text = method == .voice ? "Voice" : method.title
        if store.config.combosEnabled { text += " + swipes" }
        return text
    }

    private var medicationSummary: String {
        let count = store.config.medicationTimes.count
        return count == 0 ? "None" : "\(count) a day"
    }

    private var watchSyncText: String {
        guard let version = store.watchConfigVersion else { return "Not yet" }
        return version == store.config.version ? "Up to date" : "Sending…"
    }
}

/// One menu row: icon, title, current value and a chevron to its page.
private struct MenuRow<Destination: View>: View {
    let icon: String
    let title: String
    let value: String?
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            IconRow(icon: icon) {
                if let value {
                    LabeledContent {
                        Text(LocalizedStringKey(value))
                    } label: {
                        Text(LocalizedStringKey(title))
                    }
                } else {
                    Text(LocalizedStringKey(title))
                }
            }
        }
    }
}

// MARK: - Pages

/// A settings page that edits a copy of the settings and saves it with one button.
private struct ConfigPage<Content: View>: View {
    @Environment(WearerStore.self) private var store
    let title: String
    var canSave: (RippleConfig) -> Bool = { _ in true }
    @ViewBuilder let content: (Binding<RippleConfig>) -> Content
    @State private var draft = RippleConfig.makeDefault(wearerName: "")
    @State private var loaded = false

    var body: some View {
        RippleForm {
            content($draft)
            Section {
                Button("Save") {
                    Haptics.success()
                    store.save(draft)
                    store.banner = Banner(text: "Saved. Sending to your Watch.", ok: true)
                }
                .buttonStyle(.ripplePrimary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(draft == store.config || !canSave(draft))
            }
        }
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = store.config
        }
    }
}

private struct ProfileSettings: View {
    var body: some View {
        ConfigPage(title: "Profile", canSave: { !$0.wearerName.trimmingCharacters(in: .whitespaces).isEmpty }) { $draft in
            Section {
                AvatarPicker(size: 64)
                IconRow(icon: "person.fill") {
                    TextField("Your name", text: $draft.wearerName)
                        .textContentType(.name)
                }
            } footer: {
                FormNote("Contacts see this name.")
            }
        }
    }
}

private struct HelpCardSettings: View {
    var body: some View {
        ConfigPage(title: "Help card") { $draft in
            Section {
                IconRow(icon: "doc.text") {
                    Toggle("Add a note to alert texts", isOn: $draft.helpCardEnabled)
                }
                if draft.helpCardEnabled {
                    TextField("I have Parkinson's. My medication is in my left pocket.", text: $draft.helpCard, axis: .vertical)
                        .lineLimit(2...5)
                }
            } footer: {
                FormNote("A short note added to alert texts.")
            }
        }
    }
}

private struct TimingSettings: View {
    var body: some View {
        ConfigPage(title: "Timing") { $draft in
            Section {
                IconRow(icon: "clock") {
                    Stepper(value: $draft.checkInIntervalMinutes, in: 0...240, step: 5) {
                        LabeledContent("Watch asks if you're okay", value: draft.checkInIntervalMinutes == 0 ? "Off" : "Every \(draft.checkInIntervalMinutes) min")
                    }
                }
                IconRow(icon: "hourglass") {
                    Stepper(value: $draft.countdownSeconds, in: 5...300, step: 5) {
                        LabeledContent("Time to tap your Watch", value: "\(draft.countdownSeconds) s")
                    }
                }
                IconRow(icon: "bell") {
                    Stepper(value: $draft.ackWindowSeconds, in: 5...900, step: 5) {
                        LabeledContent("Wait, then text Tier 2", value: "\(draft.ackWindowSeconds) s")
                    }
                }
                Button("Use 15-second demo timers") {
                    draft.countdownSeconds = 15
                    draft.ackWindowSeconds = 15
                }
                .frame(minHeight: Theme.minTarget)
                .buttonStyle(.rippleLink)
            }
        }
    }
}

private struct HealthAlertSettings: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        ConfigPage(title: "Apple Watch alerts") { $draft in
            Section {
                IconRow(icon: "figure.fall") {
                    Toggle("Falls", isOn: $draft.healthFallsEnabled)
                }
                IconRow(icon: "heart.text.square") {
                    Toggle("Heart alerts", isOn: $draft.healthHeartEnabled)
                }
                if !store.config.healthAlerts.isEmpty {
                    StatusRow(label: "Apple Health", value: store.health.statusText)
                }
            }
        }
    }
}

private struct HandGestureSettings: View {
    var body: some View {
        ConfigPage(title: "Hand gestures") { $draft in
            Section {
                IconRow(icon: "hand.raised") {
                    Toggle("Hand gestures to dismiss", isOn: $draft.handGesturesEnabled)
                }
                IconRow(icon: "list.number") {
                    // Only the identical selection is excluded. The Watch
                    // listens for dismissal or alarm triggering by alarm state.
                    Picker("Dismiss gesture", selection: $draft.handGesturePreset) {
                        ForEach(HandGesturePreset.dismissChoices(besides: draft.handGestureHelpPreset)) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!draft.handGesturesEnabled)
                }
            } header: {
                SectionHeader("Dismiss")
            }
            Section {
                IconRow(icon: "exclamationmark.bubble") {
                    Toggle("Hand gestures to trigger alarm", isOn: $draft.handGestureHelpEnabled)
                }
                IconRow(icon: "list.number") {
                    Picker("Alarm gesture", selection: $draft.handGestureHelpPreset) {
                        ForEach(HandGesturePreset.helpChoices(besides: draft.handGesturePreset)) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!draft.handGestureHelpEnabled)
                }
            } header: {
                SectionHeader("Trigger alarm")
            } footer: {
                FormNote("Texts your contacts right away, only when no alarm is open. Pick two different gestures. Turns off Apple's double tap.")
            }
        }
    }
}

private struct WatchAndTextingSettings: View {
    @Environment(WearerStore.self) private var store

    var body: some View {
        RippleForm {
            Section {
                StatusRow(label: "Watch has your settings", value: store.watchConfigVersion == store.config.version ? "Yes" : "Not yet",
                          ok: store.watchConfigVersion == store.config.version)
                if let synced = store.watchConfigSyncedAt {
                    StatusRow(label: "Last checked", value: synced.shortTime)
                }
                Button("Send to Watch again") { store.pushToWatch(force: true) }
                    .frame(minHeight: Theme.minTarget)
                    .buttonStyle(.rippleLink)
            } header: {
                SectionHeader("Watch")
            }

            Section {
                NavigationLink {
                    ShortcutSetupView()
                } label: {
                    Label("Set up all Ripple shortcuts", systemImage: "square.stack.3d.up")
                }
                StatusRow(label: "Location", value: store.location.statusText)
                NavigationLink {
                    LocationCheckView()
                } label: {
                    Label("Check my location", systemImage: "location")
                }
            } header: {
                SectionHeader("Texting")
            }
        }
        .navigationTitle("Watch and texting")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeviceSettings: View {
    @Environment(WearerStore.self) private var store
    @State private var confirmForget = false

    var body: some View {
        RippleForm {
            Section {
                Text(store.pairingCode.isEmpty ? "––––––" : store.pairingCode)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Pairing code \(store.pairingCode)")
            } header: {
                SectionHeader("Demo admin pairing code")
            }

            Section {
                LabeledContent("Server", value: store.serverAddress)
                Button("Set up again", role: .destructive) { confirmForget = true }
                    .frame(minHeight: Theme.minTarget)
                    .buttonStyle(.rippleDestructiveLink)
            }
        }
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Set up this iPhone again?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Set up again", role: .destructive) { store.forgetDevice() }
        }
    }
}

/// A form row with a blue outline icon on the left, like the mockup's
/// settings rows.
private struct IconRow<Content: View>: View {
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            content
        }
    }
}

/// A form section title: 15 pt, uppercase, letter-spaced.
struct SectionHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        SectionLabel(text)
            .padding(.bottom, 4)
    }
}

#Preview("Settings") {
    NavigationStack { SettingsView() }.environment(WearerStore())
}

#Preview("Settings, largest text") {
    NavigationStack { SettingsView() }.environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
