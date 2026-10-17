import KazeKit
import SwiftUI

struct SettingsView: View {
    @Environment(WearerStore.self) private var store
    @State private var name = ""
    @State private var phone = ""
    @State private var helpCard = ""
    @State private var timing = TimingSettings.demo
    @State private var loaded = false
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                TextField("Your phone (optional)", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Text("About you")
            } footer: {
                Text("Responders see your name and phone only if you allow it for them.")
            }

            Section {
                TextField("Where your medication is kept, how to help…", text: $helpCard, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Help card")
            } footer: {
                Text("Shown to responders during an alert, if you allow it.")
            }

            Section {
                SecondsStepper(title: "Grace after expected end", value: $timing.graceSeconds, range: 0...600, step: 5)
                SecondsStepper(title: "Time to answer a check-in", value: $timing.responseWindowSeconds, range: 5...600, step: 5)
                SecondsStepper(title: "Time for a responder to acknowledge", value: $timing.ackWindowSeconds, range: 5...600, step: 5)
                SecondsStepper(title: "Follow-up if progress stops", value: $timing.followUpWindowSeconds, range: 5...1800, step: 5)
                SecondsStepper(title: "Alert after lost connection (0 = off)", value: $timing.connectionGraceSeconds, range: 0...1800, step: 5)
                Stepper("Retries after a failed send: \(timing.maxRetries)", value: $timing.maxRetries, in: 0...3)
                Button("Use demo timings") { timing = .demo }
            } header: {
                Text("Timings")
            } footer: {
                Text("Demo settings for filming, not medically validated defaults. The server owns every deadline.")
            }

            Section {
                Button {
                    Task {
                        _ = await store.saveConfig(ConfigRequest(displayName: name, phone: phone, helpCard: helpCard, timing: timing))
                    }
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("People and PINs") {
                NavigationLink {
                    ContactsView()
                } label: {
                    LabeledContent("Trusted contacts", value: "\(store.state?.profile.contacts.count ?? 0)")
                }
                NavigationLink {
                    PinSetupView()
                } label: {
                    LabeledContent("Safety and duress PINs", value: store.state?.profile.hasPins == true ? "Set" : "Not set")
                }
            }

            Section {
                Text(store.state?.profile.pairingCode ?? "––––––")
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Pairing code \(store.state?.profile.pairingCode ?? "")")
            } header: {
                Text("Demo admin pairing code")
            } footer: {
                Text("Enter this code in the KAZE Admin app to control demo scenarios for this wearer.")
            }

            Section {
                LabeledContent("Server", value: store.serverAddress)
                Button("Set up again", role: .destructive) { confirmForget = true }
            } header: {
                Text("Device")
            } footer: {
                Text("Use this if the server's data was reset. You'll enter the server address and your name again.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Set up this iPhone again?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Set up again", role: .destructive) { store.forgetDevice() }
        }
        .onAppear { load() }
    }

    private func load() {
        guard !loaded, let profile = store.state?.profile else { return }
        name = profile.displayName
        phone = profile.phone
        helpCard = profile.helpCard
        timing = profile.timing
        loaded = true
    }
}

private struct SecondsStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            VStack(alignment: .leading) {
                Text(title)
                Text("\(value) s").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
