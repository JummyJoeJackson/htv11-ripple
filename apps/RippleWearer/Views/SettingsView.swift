import RippleKit
import SwiftUI

/// All app preferences live on the iPhone. Saving sends them to the Watch.
struct SettingsView: View {
    @Environment(WearerStore.self) private var store
    @State private var draft = RippleConfig.makeDefault(wearerName: "")
    @State private var loaded = false
    @State private var confirmForget = false
    /// False when opened from Home, so the navigation bar keeps its Back button.
    var isTabRoot = true

    var body: some View {
        RippleForm {
            Section {
                ScreenHeader(title: "Settings", subtitle: nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                LanguagePicker()
            } header: {
                SectionHeader("Language")
            }

            Section {
                AvatarPicker(size: 64)
                IconRow(icon: "person.fill") {
                    TextField("Your name", text: $draft.wearerName)
                        .textContentType(.name)
                }
            } header: {
                SectionHeader("Profile")
            }

            Section {
                IconRow(icon: "doc.text") {
                    Toggle("Add a note to alert texts", isOn: $draft.helpCardEnabled)
                }
                if draft.helpCardEnabled {
                    TextField("I have Parkinson's. My medication is in my left pocket.", text: $draft.helpCard, axis: .vertical)
                        .lineLimit(2...5)
                }
            } header: {
                SectionHeader("Help card")
            } footer: {
                FormNote("A short note added to alert texts.")
            }

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
            } header: {
                SectionHeader("Timing")
            }

            Section {
                NavigationLink {
                    MedicationView()
                } label: {
                    IconRow(icon: "pills") {
                        LabeledContent("Dose times", value: medicationSummary)
                    }
                }
            } header: {
                SectionHeader("Medication")
            }

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
            } header: {
                SectionHeader("Apple Watch alerts")
            } footer: {
                FormNote("When your Watch records a fall or a heart alert in Health, Ripple checks in. Texts say which alert it was.")
            }

            Section {
                NavigationLink {
                    AnswerSetupScreen()
                } label: {
                    IconRow(icon: AnswerMethod(store.config).icon) {
                        LabeledContent("How you answer", value: answerSummary)
                    }
                }
                if store.config.voiceEnabled {
                    StatusRow(label: "Speech recognition", value: store.speech.statusText)
                }
            } header: {
                SectionHeader("Answering an alarm")
            } footer: {
                FormNote("The secret help signal is always a 2-second hold.")
            }

            Section {
                IconRow(icon: "hand.raised") {
                    Toggle("Hand gestures to dismiss", isOn: $draft.handGesturesEnabled)
                }
                IconRow(icon: "list.number") {
                    // Each picker leaves out the other's choice and anything
                    // overlapping it, so one gesture can't set off the other.
                    Picker("Dismiss gesture", selection: $draft.handGesturePreset) {
                        ForEach(HandGesturePreset.dismissChoices(besides: draft.handGestureHelpPreset)) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!draft.handGesturesEnabled)
                }
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
                SectionHeader("Hand gestures")
            } footer: {
                FormNote("The alarm gesture texts your contacts right away. Choices that could set off the other gesture are hidden. Turns off Apple's double tap.")
            }

            Section {
                Button {
                    var updated = draft
                    updated.shortcutName = updated.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
                    // "How you answer" saves on its own screen, so keep what it saved.
                    updated = AnswerChoice(store.config).applied(to: updated)
                    // Dose times save on their own screen, so keep what it saved.
                    updated.medicationTimes = store.config.medicationTimes
                    updated.medicationGraceMinutes = store.config.medicationGraceMinutes
                    store.save(updated)
                    store.banner = Banner(text: "Saved. Sending to your Watch.", ok: true)
                } label: {
                    Text("Save")
                }
                .buttonStyle(.ripplePrimary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(draft.wearerName.trimmingCharacters(in: .whitespaces).isEmpty || unchanged)
            }

            Section {
                StatusRow(label: "Watch has your settings", value: watchSyncText,
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
            } header: {
                SectionHeader("Shortcuts")
            }

            Section {
                StatusRow(label: "Location", value: store.location.statusText)
                NavigationLink {
                    LocationCheckView()
                } label: {
                    Label("Check my location", systemImage: "location")
                }
            } header: {
                SectionHeader("Texting")
            }

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
            } header: {
                SectionHeader("Device")
            }
        }
        .navigationTitle("Settings")
        .toolbar(isTabRoot ? .hidden : .visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Set up this iPhone again?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Set up again", role: .destructive) { store.forgetDevice() }
        }
        .onAppear {
            if !loaded {
                draft = store.config
                loaded = true
            }
        }

    }

    /// "Gesture", "Voice: “I'm okay”" or "Tap", plus swipes if on.
    private var answerSummary: String {
        let method = AnswerMethod(store.config)
        var text = method == .voice ? "Voice: \u{201C}\(store.config.voicePhrase)\u{201D}" : method.title
        if store.config.combosEnabled { text += " + swipes" }
        return text
    }

    /// Nothing on this screen differs from what's saved. "How you answer"
    /// and dose times save on their own screens, so they don't count.
    private var unchanged: Bool {
        var compared = AnswerChoice(store.config).applied(to: draft)
        compared.medicationTimes = store.config.medicationTimes
        compared.medicationGraceMinutes = store.config.medicationGraceMinutes
        return compared == store.config
    }

    private var medicationSummary: String {
        let count = store.config.medicationTimes.count
        return count == 0 ? "None" : "\(count) a day"
    }

    private var watchSyncText: String {
        guard let version = store.watchConfigVersion else { return "Not yet" }
        return version == store.config.version ? "Yes" : "Sending…"
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
