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
                }
            } header: {
                Text("Dismissing an alarm")
            } footer: {
                Text("Double tap needs Apple Watch Series 9, Ultra 2 or later on watchOS 11. The voice phrase uses dictation on the Watch while the app is open. Duress is always the 2-second hold, touch only, so a stray double tap or a misheard phrase can never trigger or hide it.")
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
