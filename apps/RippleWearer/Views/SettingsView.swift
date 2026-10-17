import RippleKit
import SwiftUI

/// All app preferences live on the iPhone. Saving sends them to the Watch.
struct SettingsView: View {
    @Environment(WearerStore.self) private var store
    @State private var draft = RippleConfig.makeDefault(wearerName: "")
    @State private var loaded = false
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section("About you") {
                TextField("Your name", text: $draft.wearerName)
                    .textContentType(.name)
            }

            Section {
                Toggle("Add a help card to alert texts", isOn: $draft.helpCardEnabled)
                if draft.helpCardEnabled {
                    TextField("I have Parkinson's. I may look confused. My medication is in my left pocket.", text: $draft.helpCard, axis: .vertical)
                        .lineLimit(2...5)
                }
            } header: {
                Text("Help card")
            } footer: {
                Text("Off by default. A short note you write, added to alert texts.")
            }

            Section {
                Stepper(value: $draft.checkInIntervalMinutes, in: 0...240, step: 5) {
                    LabeledContent("Automatic check-ins", value: draft.checkInIntervalMinutes == 0 ? "Off" : "Every \(draft.checkInIntervalMinutes) min")
                }
                Stepper(value: $draft.countdownSeconds, in: 5...300, step: 5) {
                    LabeledContent("Time to respond", value: "\(draft.countdownSeconds) s")
                }
                Stepper(value: $draft.ackWindowSeconds, in: 5...900, step: 5) {
                    LabeledContent("Before Tier 2 is texted", value: "\(draft.ackWindowSeconds) s")
                }
                Button("Use 15-second demo timers") {
                    draft.countdownSeconds = 15
                    draft.ackWindowSeconds = 15
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("Short timers are for demos, not medically validated settings. The demo admin app can also start alarms.")
            }

            Section {
                Text("Touch: tap the circle. Always available.")
                Toggle("Double tap to dismiss", isOn: $draft.doubleTapEnabled)
                Toggle("Voice phrase to dismiss", isOn: $draft.voiceEnabled)
                if draft.voiceEnabled {
                    TextField("Phrase", text: $draft.voicePhrase)
                    StatusRow(label: "Speech recognition", value: store.speech.statusText)
                }
            } header: {
                Text("Dismissing an alarm")
            } footer: {
                Text("Double tap needs Apple Watch Series 9, Ultra 2 or later on watchOS 11. With the voice phrase on, the Watch listens for it during an alarm, with nothing to press. This iPhone recognizes the speech, so keep Ripple open on both. Pick a phrase you wouldn't say by accident: anyone nearby who says it also dismisses. Duress is always the 2-second hold, touch only, so a stray double tap, swipe or misheard phrase can never trigger or hide it.")
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
                Text("Swipe combos")
            } footer: {
                Text("Swipe on the Watch circle. It takes two swipes the same way, so one shaky movement can't do either. Help texts your contacts straight away, even when monitoring is off.")
            }

            Section {
                Button {
                    var updated = draft
                    updated.shortcutName = updated.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save(updated)
                    store.banner = Banner(text: "Saved. Sending to your Watch.", ok: true)
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .disabled(draft.wearerName.trimmingCharacters(in: .whitespaces).isEmpty || draft == store.config)
            }

            Section {
                StatusRow(label: "On this iPhone", value: "v\(store.config.version)")
                StatusRow(label: "On the Watch", value: store.watchConfigVersion.map { "v\($0)" } ?? "Not synced yet",
                          ok: store.watchConfigVersion == store.config.version)
                if let synced = store.watchConfigSyncedAt {
                    StatusRow(label: "Last confirmed", value: synced.timeWithSeconds)
                }
                Button("Send to Watch again") { store.pushToWatch(force: true) }
            } header: {
                Text("Watch sync")
            } footer: {
                Text("The Watch keeps the last settings it received, even when your iPhone isn't nearby.")
            }

            Section {
                NavigationLink("Messaging shortcut") { ShortcutSetupView() }
                StatusRow(label: "Location", value: store.location.statusText)
            }

            Section {
                Text(store.pairingCode.isEmpty ? "––––––" : store.pairingCode)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Pairing code \(store.pairingCode)")
            } header: {
                Text("Demo admin pairing code")
            } footer: {
                Text("Enter this in the Ripple Demo Admin app to control demo alarms for this wearer.")
            }

            Section {
                LabeledContent("Server", value: store.serverAddress)
                Button("Set up again", role: .destructive) { confirmForget = true }
            } header: {
                Text("Device")
            } footer: {
                Text("Use this if the server's data was reset.")
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

/// One-time setup for the "Ripple Alert" shortcut that sends the texts.
struct ShortcutSetupView: View {
    @Environment(WearerStore.self) private var store
    @State private var name = ""
    @State private var testContactId = ""

    var body: some View {
        Form {
            Section {
                Text("Ripple sends texts from your iPhone and your own Messages account by running a shortcut. It passes a list of messages; the shortcut sends each one to its own recipient, so nobody gets a group text.")
            }

            Section {
                TextField("Shortcut name", text: $name)
                    .autocorrectionDisabled()
                Button("Save name") {
                    var updated = store.config
                    updated.shortcutName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.save(updated)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == store.config.shortcutName)
            } header: {
                Text("Shortcut name")
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
                Text("Build the shortcut")
            } footer: {
                Text("The input looks like {\"messages\":[{\"to\":\"+14165550101\",\"text\":\"Ripple alert: …\"}]}.")
            }

            Section {
                if store.config.contacts.isEmpty {
                    Text("Add a contact first.").foregroundStyle(.secondary)
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
                    .disabled(testContactId.isEmpty)
                }
                if let result = store.testResult {
                    Text(result).font(.footnote)
                }
            } header: {
                Text("Test")
            } footer: {
                Text("Opening the shortcut doesn't prove a text was delivered. Check the other phone. Sending works with this app in the foreground; locked-phone sending is untested.")
            }
        }
        .navigationTitle("Messaging shortcut")
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
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 24)
            Text(text)
        }
    }
}
