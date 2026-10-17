import SwiftUI

struct OnboardingView: View {
    @Environment(WearerStore.self) private var store
    @State private var address = ""
    @State private var name = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("KAZE starts a call for help when you can't ask for it. Start a session on this iPhone and answer check-ins on your Apple Watch. If you don't respond, ask for help, or enter your duress PIN, KAZE alerts the people you choose.")
                    Text("Hackathon prototype. Not a medical or emergency service.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("192.168.1.20:8080", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server address")
                } footer: {
                    Text("The KAZE server prints this address when it starts. Your iPhone must be on the same Wi-Fi, or use a tunnel URL.")
                }

                Section("Your name") {
                    TextField("The name responders will see", text: $name)
                        .textContentType(.name)
                }

                Section {
                    Button {
                        Task {
                            working = true
                            _ = await store.setUp(serverAddress: address, name: name)
                            working = false
                        }
                    } label: {
                        Text(working ? "Connecting…" : "Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(working || address.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let banner = store.banner, !banner.ok {
                    Section {
                        Label(banner.text, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Welcome to KAZE")
        }
        .onAppear {
            if address.isEmpty { address = store.serverAddress }
        }
    }
}
