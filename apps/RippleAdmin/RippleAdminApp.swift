import RippleKit
import SwiftUI

@main
struct RippleAdminApp: App {
    @State private var store = AdminStore()

    var body: some Scene {
        WindowGroup {
            AdminRootView()
                .environment(store)
        }
    }
}

struct AdminRootView: View {
    @Environment(AdminStore.self) private var store

    var body: some View {
        if store.isSignedIn {
            WearerListView()
        } else {
            AdminSignInView()
        }
    }
}

/// Always visible: this app is for testing and presentations, not caregivers.
struct DemoAdminBanner: View {
    var body: some View {
        Label("DEMO ADMIN · simulated alarms", systemImage: "theatermasks.fill")
            .font(.headline.weight(.heavy))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color.orange)
            .foregroundStyle(Color.black)
            .accessibilityLabel("Demo admin. Alarms triggered here are simulated.")
    }
}

struct AdminSignInView: View {
    @Environment(AdminStore.self) private var store
    @State private var address = ""
    @State private var secret = ""
    @State private var name = "Presenter"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.20:8080", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server address")
                } footer: {
                    Text("Printed in the server console when it starts.")
                }
                Section {
                    SecureField("Admin secret", text: $secret)
                    TextField("Your name", text: $name)
                } footer: {
                    Text("The secret is RIPPLE_ADMIN_SECRET on the server (default: ripple-demo).")
                }
                Section {
                    Button {
                        Task { _ = await store.signIn(address: address, secret: secret, name: name) }
                    } label: {
                        Text(store.pending ?? "Sign in").frame(maxWidth: .infinity)
                    }
                    .disabled(address.isEmpty || secret.isEmpty || store.pending != nil)
                }
                if let banner = store.banner, !banner.ok {
                    Section { Text(banner.text).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Ripple Demo Admin")
            .safeAreaInset(edge: .top) { DemoAdminBanner() }
        }
        .onAppear {
            if address.isEmpty { address = store.serverAddress }
        }
    }
}

struct WearerListView: View {
    @Environment(AdminStore.self) private var store
    @State private var code = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.wearers.isEmpty {
                        Text("No wearers paired yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.wearers) { wearer in
                        NavigationLink {
                            AdminDashboardView(userId: wearer.userId)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(wearer.displayName).font(.headline)
                                Text(summary(wearer))
                                    .font(.caption)
                                    .foregroundStyle(wearer.alarmOpen ? Color.red : Color.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Paired wearers")
                } footer: {
                    Text("You can only control wearers you've paired with.")
                }

                Section {
                    TextField("6-digit pairing code", text: $code)
                        .keyboardType(.numberPad)
                    Button("Pair") {
                        Task {
                            if await store.pair(code: code) { code = "" }
                        }
                    }
                    .disabled(code.filter(\.isNumber).count != 6 || store.pending != nil)
                } header: {
                    Text("Pair with a wearer")
                } footer: {
                    Text("The code is on the wearer's iPhone under Settings → Demo admin pairing code.")
                }

                if let banner = store.banner {
                    Section { Text(banner.text).foregroundStyle(banner.ok ? Color.green : Color.red) }
                }

                Section {
                    LabeledContent("Server", value: store.serverAddress)
                    LabeledContent("Signed in as", value: store.adminName)
                    Button("Sign out", role: .destructive) { store.signOut() }
                }
            }
            .navigationTitle("Ripple Demo Admin")
            .safeAreaInset(edge: .top) { DemoAdminBanner() }
            .refreshable { await store.loadWearers() }
            .task { await store.loadWearers() }
        }
    }

    private func summary(_ wearer: AdminWearerSummary) -> String {
        if wearer.alarmOpen { return "Alarm open" }
        let online = wearer.online ? "iPhone online" : "iPhone offline"
        return online + (wearer.monitoring ? " · monitoring" : " · not monitoring")
    }
}
