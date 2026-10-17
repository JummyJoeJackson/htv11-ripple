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
                NavigationLink {
                    HandGestureSetupView()
                } label: {
                    IconRow(icon: "applewatch") { Text("Set up Watch gesture shortcuts") }
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
                    Label("Messaging shortcut", systemImage: "message")
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

/// AssistiveTouch runs one background input shortcut per recognised gesture.
/// Ripple decides whether those inputs complete the saved dismiss or alarm
/// sequence.
struct HandGestureSetupView: View {
    var body: some View {
        Form {
            Section {
                Text("Apple Watch recognises the gestures. Each shortcut sends one gesture to Ripple, which checks the sequences you chose in Settings.")
                Text("These four shortcuts are gesture inputs. Keep your existing Ripple Alert messaging shortcut separate.")
            }

            Section {
                SetupStep(number: 1, text: "Send the four Ripple gesture shortcut files supplied with this build to your iPhone using AirDrop or iCloud Drive, and import them into Shortcuts. In each shortcut's details, turn on Show on Apple Watch.")
                ForEach(HandGestureStep.allCases) { step in
                    LabeledContent(step.label, value: step.shortcutName)
                }
                SetupStep(number: 2, text: "Each imported shortcut contains its matching Ripple Watch action. Install the updated Ripple apps on both iPhone and Watch before importing. Wait for the shortcuts to sync to your Watch.")
            } header: {
                Text("Add the four shortcuts")
            } footer: {
                Text("The gesture actions run in the background. Keep the shortcuts to one action, without Open App or Show Alert, so they don't request a screen change.")
            }

            Section {
                SetupStep(number: 3, text: "On your iPhone, open Watch → Accessibility → AssistiveTouch. Turn on AssistiveTouch and Hand Gestures.")
                SetupStep(number: 4, text: "Open each hand gesture's assignment, choose Shortcuts, and select the matching Ripple shortcut above. Pinch may be called Tap; double pinch may be called Double Tap.")
                SetupStep(number: 5, text: "Set Activation Gesture to None so double clench reaches its shortcut instead of activating AssistiveTouch. These assignments apply across the Watch.")
            } header: {
                Text("Assign AssistiveTouch gestures")
            } footer: {
                Text("AssistiveTouch turns off Apple's native double tap. Ripple's touchscreen controls remain available.")
            }

            Section {
                SetupStep(number: 6, text: "In Ripple Settings, turn on Hand gestures to dismiss, choose a dismiss gesture, and tap Save. Under Watch sync, wait for the iPhone and Watch versions to match.")
                SetupStep(number: 7, text: "With no alarm open, leave Ripple visible on your Watch and perform each gesture. Check Ripple's Gesture # counter and gesture name to confirm the input arrived while Ripple stayed visible.")
                SetupStep(number: 8, text: "Try your selected sequence in order, with no more than 5 seconds between steps. A double pinch or double clench is one input from Apple's recogniser, not two separate shortcut runs.")
                SetupStep(number: 9, text: "To trigger an alarm with a gesture, tell your contacts first. Then turn on Hand gestures to trigger alarm, choose an alarm gesture, and tap Save. Doing it texts your contacts, even with no alarm open.")
            } header: {
                Text("Choose and check a sequence")
            } footer: {
                Text("The dismiss gesture works during an alarm, through Ripple's usual I'm okay action. The alarm gesture texts your contacts at any time, like swiping up twice. Other inputs only update the receipt display. Changing either dropdown later needs Save and Watch sync, with the same four shortcuts.")
            }
        }
        .navigationTitle("Gesture shortcuts")
    }
}

/// One-time setup for the two shortcuts: "Ripple Alert" sends the texts, and
/// "Ripple Accept" passes both alarm and invitation replies back to Ripple.
struct ShortcutSetupView: View {
    @Environment(WearerStore.self) private var store
    @State private var name = ""
    @State private var testContactId = ""
    @State private var replyText = ""

    var body: some View {
        RippleForm {
            Section {
                Text("Ripple texts from your iPhone using this shortcut.")
            }

            Section {
                SetupStep(number: 1, text: "Get \"Ripple Alert.shortcut\" and \"Ripple Accept.shortcut\" from the team (the shortcuts folder in the repo, signed on a Mac).")
                SetupStep(number: 2, text: "AirDrop them to this iPhone, or open them from Files, and tap Add Shortcut for each.")
                SetupStep(number: 3, text: "Keep the names Ripple Alert and Ripple Accept, then send a test message below.")
            } header: {
                SectionHeader("Install the shortcuts")
            } footer: {
                FormNote("If you can't get the files, build Ripple Alert by hand with the steps further down.")
            }

            Section {
                SetupStep(number: 1, text: "In Shortcuts, open Automation, tap +, and choose Message.")
                SetupStep(number: 2, text: "Set Message Contains to \"Ripple accept\". Leave Sender as anyone, or pick your contacts.")
                SetupStep(number: 3, text: "Choose Run Immediately, then tap Next.")
                SetupStep(number: 4, text: "Pick the Ripple Accept shortcut, so the message is passed to it.")
                SetupStep(number: 5, text: "Add a second Message automation containing \"Ripple join\", also Run Immediately and using Ripple Accept. Keep the first automation too.")
            } header: {
                SectionHeader("Let contacts reply")
            } footer: {
                FormNote("Alert texts ask contacts to reply \"Ripple accept 4821\", with a different code for each person. When a reply arrives, the automation runs Ripple Accept, which opens Ripple with the reply. Your Watch shows who is responding and Tier 2 isn't texted. The reply itself still appears in Messages.")
            }

            Section {
                TextField("Ripple accept 4821 or Ripple join 583921", text: $replyText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Use this reply") {
                    store.acceptReply(text: replyText, from: nil)
                    replyText = ""
                }
                .frame(minHeight: Theme.minTarget)
                .buttonStyle(.rippleLink)
                .disabled(ReplyCode.acceptCode(in: replyText) == nil && JoinCode.code(in: replyText) == nil)
            } header: {
                SectionHeader("Try a reply")
            } footer: {
                FormNote("For testing. Accept uses an alert's code; Join uses an invitation's code.")
            }

            Section {
                TextField("Shortcut name", text: $name)
                    .autocorrectionDisabled()
                Button("Save name") {
                    var updated = store.config
                    updated.shortcutName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save(updated)
                }
                .frame(minHeight: Theme.minTarget)
                .buttonStyle(.rippleLink)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == store.config.shortcutName)
            } header: {
                SectionHeader("Shortcut name")
            }

            Section {
                SetupStep(number: 1, text: "Open Shortcuts, tap +, and name the shortcut \"\(store.config.shortcutName)\".")
                SetupStep(number: 2, text: "Tap the (i) button and turn on Show in Share Sheet, then set it to receive Text. If there's no input, choose Stop and Respond.")
                SetupStep(number: 3, text: "Add Get Dictionary from Input, using Shortcut Input.")
                SetupStep(number: 4, text: "Add Get Dictionary Value: get Value for messages in Dictionary.")
                SetupStep(number: 5, text: "Add Repeat with Each, over Dictionary Value.")
                SetupStep(number: 6, text: "Inside the repeat, add Get Dictionary Value for to in Repeat Item, then another for text in Repeat Item.")
                SetupStep(number: 7, text: "Inside the repeat, add Send Message: the message is the text value, the recipient is the to value. Expand it and turn off Show When Run.")
                SetupStep(number: 8, text: "Come back here and send a test message. Approve any permission Shortcuts asks for, so it can send without asking during the demo.")
            } header: {
                SectionHeader("Or build Ripple Alert by hand")
            } footer: {
                FormNote("The input looks like {\"messages\":[{\"to\":\"+14165550101\",\"text\":\"RIPPLE ALERT: …\"}]}.")
            }

            Section {
                if store.config.contacts.isEmpty {
                    FormNote("Add a contact first.")
                } else {
                    Picker("Send to", selection: $testContactId) {
                        ForEach(store.config.contacts) { contact in
                            Text(contact.name).tag(contact.id)
                        }
                    }
                    Button("Send test message") {
                        if let contact = store.config.contacts.first(where: { $0.id == testContactId }) {
                            store.sendTestMessage(to: contact)
                        }
                    }
                    .frame(minHeight: Theme.minTarget)
                    .buttonStyle(.rippleLink)
                    .disabled(testContactId.isEmpty)
                }
                if let result = store.testResult {
                    FormNote(result)
                }
            } header: {
                SectionHeader("Test")
            } footer: {
                FormNote("Check the other phone to confirm it arrived.")
            }
        }
        .navigationTitle("Messaging shortcuts")
        .onAppear {
            name = store.config.shortcutName
            if testContactId.isEmpty { testContactId = store.config.contacts.first?.id ?? "" }
        }
    }
}

private struct SetupStep: View {
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
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

#Preview("Settings") {
    NavigationStack { SettingsView() }.environment(WearerStore())
}

#Preview("Settings, largest text") {
    NavigationStack { SettingsView() }.environment(WearerStore()).dynamicTypeSize(.accessibility3)
}
