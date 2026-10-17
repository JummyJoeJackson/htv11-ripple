import RippleKit
import SwiftUI

/// All app preferences live on the iPhone. Saving sends them to the Watch.
struct SettingsView: View {
    @Environment(WearerStore.self) private var store
    @State private var draft = RippleConfig.makeDefault(wearerName: "")
    @State private var loaded = false
    @State private var confirmForget = false

    var body: some View {
        RippleForm {
            Section {
                TextField("Your name", text: $draft.wearerName)
                    .textContentType(.name)
            } header: {
                SectionHeader("Your name")
            }

            Section {
                Toggle("Add a note to alert texts", isOn: $draft.helpCardEnabled)
                if draft.helpCardEnabled {
                    TextField("I have Parkinson's. I may look confused. My medication is in my left pocket.", text: $draft.helpCard, axis: .vertical)
                        .lineLimit(2...5)
                }
            } header: {
                SectionHeader("Help card")
            } footer: {
                FormNote("Off unless you turn it on. A short note you write, added to alert texts.")
            }

            Section {
                Stepper(value: $draft.checkInIntervalMinutes, in: 0...240, step: 5) {
                    LabeledContent("Check in with me", value: draft.checkInIntervalMinutes == 0 ? "Off" : "Every \(draft.checkInIntervalMinutes) min")
                }
                Stepper(value: $draft.countdownSeconds, in: 5...300, step: 5) {
                    LabeledContent("Time to answer", value: "\(draft.countdownSeconds) s")
                }
                Stepper(value: $draft.ackWindowSeconds, in: 5...900, step: 5) {
                    LabeledContent("Wait before Tier 2", value: "\(draft.ackWindowSeconds) s")
                }
                Button("Use 15-second demo timers") {
                    draft.countdownSeconds = 15
                    draft.ackWindowSeconds = 15
                }
                .frame(minHeight: Theme.minTarget)
                .buttonStyle(.rippleLink)
            } header: {
                SectionHeader("Timing")
            } footer: {
                FormNote("Short timers are for demos, not medical advice. The demo admin app can also start alarms.")
            }

            Section {
                LabeledContent("Tap the circle", value: "Always on")
                Toggle("Double tap to answer", isOn: $draft.doubleTapEnabled)
                Toggle("Say a phrase to answer", isOn: $draft.voiceEnabled)
                if draft.voiceEnabled {
                    TextField("Phrase", text: $draft.voicePhrase)
                    StatusRow(label: "Speech recognition", value: store.speech.statusText)
                }
            } header: {
                SectionHeader("Answering an alarm")
            } footer: {
                FormNote("Double tap needs Apple Watch Series 9, Ultra 2 or later on watchOS 11. With a phrase on, the Watch listens for it during an alarm, with nothing to press. This iPhone recognizes the speech, so keep Ripple open on both. Pick a phrase you wouldn't say by accident: anyone nearby who says it also answers. The secret help signal is always a 2-second hold on the circle, so a stray double tap, swipe or misheard phrase can't set it off or hide it.")
            }

            Section {
                Toggle("Hand gestures to dismiss", isOn: $draft.handGesturesEnabled)
                Picker("Gesture sequence", selection: $draft.handGesturePreset) {
                    ForEach(HandGesturePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!draft.handGesturesEnabled)
                NavigationLink("Set up Watch gesture shortcuts") { HandGestureSetupView() }
            } header: {
                Text("Hand gestures")
            } footer: {
                Text("A complete sequence says I'm okay during an alarm. Allow up to 5 seconds between gestures. Save below to send this selection to your Watch. AssistiveTouch needs a one-time shortcut setup and turns off Apple's native double tap.")
            }

            Section {
                Toggle("Swipe up twice for help, down twice for I'm okay", isOn: $draft.combosEnabled)
            } header: {
                SectionHeader("Swipe combos")
            } footer: {
                FormNote("Swipe on the Watch circle. It takes two swipes the same way, so one shaky movement can't do either. Help texts your contacts straight away, even when monitoring is off.")
            }

            Section {
                Button {
                    var updated = draft
                    updated.shortcutName = updated.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save(updated)
                    store.banner = Banner(text: "Saved. Sending to your Watch.", ok: true)
                } label: {
                    Text("Save")
                }
                .buttonStyle(.ripplePrimary)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(draft.wearerName.trimmingCharacters(in: .whitespaces).isEmpty || draft == store.config)
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
            } footer: {
                FormNote("The Watch keeps the last settings it got, even when your iPhone isn't nearby.")
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
            } footer: {
                FormNote("Enter this in the Ripple Demo Admin app to control demo alarms.")
            }

            Section {
                LabeledContent("Server", value: store.serverAddress)
                Button("Set up again", role: .destructive) { confirmForget = true }
                    .frame(minHeight: Theme.minTarget)
                    .buttonStyle(.rippleDestructiveLink)
            } header: {
                SectionHeader("Device")
            } footer: {
                FormNote("Use this if the server's data was reset.")
            }
        }
        .navigationTitle("Settings")
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

    private var watchSyncText: String {
        guard let version = store.watchConfigVersion else { return "Not yet" }
        return version == store.config.version ? "Yes" : "Sending…"
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
/// Ripple decides whether those inputs complete the saved dismissal sequence.
struct HandGestureSetupView: View {
    var body: some View {
        Form {
            Section {
                Text("Apple Watch recognises the gestures. Each shortcut sends one gesture to Ripple, which checks the sequence you chose in Settings.")
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
                SetupStep(number: 6, text: "In Ripple Settings, turn on Hand gestures to dismiss, choose your sequence, and tap Save. Under Watch sync, wait for the iPhone and Watch versions to match.")
                SetupStep(number: 7, text: "With no alarm open, leave Ripple visible on your Watch and perform each gesture. Check Ripple's Gesture # counter and gesture name to confirm the input arrived while Ripple stayed visible.")
                SetupStep(number: 8, text: "Try your selected sequence in order, with no more than 5 seconds between steps. A double pinch or double clench is one input from Apple's recogniser, not two separate shortcut runs.")
            } header: {
                Text("Choose and check a sequence")
            } footer: {
                Text("Without an active alarm, inputs only update the receipt display. A matching sequence during an alarm dismisses it through Ripple's usual I'm okay action. Changing the dropdown later needs Save and Watch sync, with the same four shortcuts.")
            }
        }
        .navigationTitle("Gesture shortcuts")
    }
}

/// One-time setup for the two shortcuts: "Ripple Alert" sends the texts, and
/// "Ripple Accept" passes a contact's "RIPPLE ACCEPT 4821" reply back to Ripple.
struct ShortcutSetupView: View {
    @Environment(WearerStore.self) private var store
    @State private var name = ""
    @State private var testContactId = ""
    @State private var replyText = ""

    var body: some View {
        RippleForm {
            Section {
                Text("Ripple sends texts from your iPhone and your own Messages account by running a shortcut. Each person gets their own text, so nobody gets a group text.")
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
            } header: {
                SectionHeader("Let contacts reply to accept")
            } footer: {
                FormNote("Alert texts end with \"or reply RIPPLE ACCEPT 4821\", with a different code for each person. When a reply arrives, the automation runs Ripple Accept, which opens Ripple with the reply. It counts like tapping the link: your Watch shows who is responding and Tier 2 isn't texted. The reply itself still appears in Messages.")
            }

            Section {
                TextField("RIPPLE ACCEPT 4821", text: $replyText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Use this reply") {
                    store.acceptReply(text: replyText, from: nil)
                    replyText = ""
                }
                .frame(minHeight: Theme.minTarget)
                .buttonStyle(.rippleLink)
                .disabled(ReplyCode.acceptCode(in: replyText) == nil)
            } header: {
                SectionHeader("Try a reply")
            } footer: {
                FormNote("Does what the automation does, for testing during an alert. The code must belong to someone who was already texted.")
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
                FormNote("The input looks like {\"messages\":[{\"to\":\"+14165550101\",\"text\":\"Ripple alert: …\"}]}.")
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
                FormNote("Opening the shortcut doesn't prove a text arrived. Check the other phone. Sending works with this app open; sending while the phone is locked is untested.")
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
