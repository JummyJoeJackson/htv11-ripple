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
                    Text("Ripple gets you help when you can't respond to an alarm on your Apple Watch. If you don't answer, your iPhone texts the contacts you choose.")
                    Text("Hackathon prototype. It doesn't detect falls or any medical condition, and it isn't an emergency service.")
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
                    Text("The Ripple server prints this address when it starts. Your iPhone must be on the same Wi-Fi, or use a tunnel URL.")
                }

                Section("Your name") {
                    TextField("The name your contacts will see", text: $name)
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
            .navigationTitle("Welcome to Ripple")
        }
        .onAppear {
            if address.isEmpty { address = store.serverAddress }
        }
    }
}
