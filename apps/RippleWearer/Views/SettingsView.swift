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

/// One-time setup for the "Ripple Alert" shortcut that sends the texts.
struct ShortcutSetupView: View {
    @Environment(WearerStore.self) private var store
    @State private var name = ""
    @State private var testContactId = ""

    var body: some View {
        RippleForm {
            Section {
                Text("Ripple sends texts from your iPhone and your own Messages account by running a shortcut. Each person gets their own text, so nobody gets a group text.")
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
                SectionHeader("Build the shortcut")
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
