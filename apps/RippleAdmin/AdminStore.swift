import Foundation
import Observation
import RippleKit

struct AdminBanner: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var ok: Bool
}

enum AdminConnection: Equatable {
    case unknown, online
    case offline(String)

    var offlineReason: String? {
        if case .offline(let reason) = self { return reason }
        return nil
    }
}

/// The demo admin app. Commands go through the backend to the wearer's
/// iPhone and exercise the same alarm behaviour as the wearer's own actions.
@MainActor
@Observable
final class AdminStore {
    private(set) var serverAddress: String
    private(set) var adminToken: String?
    private(set) var adminName: String
    private(set) var wearers: [AdminWearerSummary] = []
    private(set) var selectedUserId: String?
    private(set) var view: AdminWearerView?
    private(set) var connection: AdminConnection = .unknown
    private(set) var pending: String?
    var banner: AdminBanner?

    @ObservationIgnored private var api: RippleAPI?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private enum Keys {
        static let server = "ripple.admin.serverAddress"
        static let token = "ripple.admin.token"
        static let name = "ripple.admin.name"
    }

    var isSignedIn: Bool { adminToken != nil }

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        adminToken = UserDefaults.standard.string(forKey: Keys.token)
        adminName = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        rebuildAPI()
    }

    private func rebuildAPI() {
        if let adminToken, let url = RippleAPI.normalizedURL(from: serverAddress) {
            api = RippleAPI(baseURL: url, token: adminToken)
        } else {
            api = nil
        }
    }

    // MARK: Sign in

    func signIn(address: String, secret: String, name: String) async -> Bool {
        guard let url = RippleAPI.normalizedURL(from: address) else {
            banner = AdminBanner(text: "Enter the server address printed in the server console.", ok: false)
            return false
        }
        pending = "Signing in…"
        defer { pending = nil }
        do {
            let response = try await RippleAPI(baseURL: url, token: nil).adminLogin(AdminLoginRequest(secret: secret, name: name))
            serverAddress = url.absoluteString
            adminToken = response.adminToken
            adminName = name
            UserDefaults.standard.set(serverAddress, forKey: Keys.server)
            UserDefaults.standard.set(response.adminToken, forKey: Keys.token)
            UserDefaults.standard.set(name, forKey: Keys.name)
            rebuildAPI()
            banner = nil
            await loadWearers()
            return true
        } catch {
            banner = AdminBanner(text: describe(error), ok: false)
            return false
        }
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        adminToken = nil
        wearers = []
        view = nil
        selectedUserId = nil
        UserDefaults.standard.removeObject(forKey: Keys.token)
        rebuildAPI()
    }

    // MARK: Wearers

    func loadWearers() async {
        guard let api else { return }
        do {
            wearers = try await api.adminWearers()
            connection = .online
        } catch let error as RippleAPIError where error.isUnauthorized {
            connection = .offline("The server doesn't recognize this admin. Sign in again.")
        } catch {
            connection = .offline(describe(error))
        }
    }

    func pair(code: String) async -> Bool {
        guard let api else { return false }
        pending = "Pairing…"
        defer { pending = nil }
        do {
            let response = try await api.pair(PairRequest(pairingCode: code))
            banner = AdminBanner(text: "Paired with \(response.wearer.displayName).", ok: true)
            await loadWearers()
            return true
        } catch {
            banner = AdminBanner(text: describe(error), ok: false)
            return false
        }
    }

    // MARK: Live view

    func select(_ userId: String?) {
        selectedUserId = userId
        view = nil
        pollTask?.cancel()
        pollTask = nil
        guard userId != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func refresh() async {
        guard let api, let userId = selectedUserId else { return }
        do {
            let fresh = try await api.adminView(userId: userId)
            guard selectedUserId == userId else { return }
            view = fresh
            connection = .online
        } catch {
            connection = .offline(describe(error))
        }
    }

    // MARK: Demo controls

    private func run(_ pendingText: String, success: String, _ action: @escaping (RippleAPI, String) async throws -> AdminWearerView) async {
        guard let api, let userId = selectedUserId else { return }
        pending = pendingText
        defer { pending = nil }
        do {
            view = try await action(api, userId)
            banner = AdminBanner(text: success, ok: true)
        } catch {
            banner = AdminBanner(text: "Not done. \(describe(error))", ok: false)
        }
    }

    func triggerAlarm(countdown: Int) async {
        await run("Sending…", success: "Trigger sent. Watch the command reach the iPhone below.") { api, userId in
            try await api.sendCommand(userId: userId, AdminCommandRequest(kind: .triggerAlarm, countdownSeconds: countdown))
        }
    }

    /// Stands in for Apple Watch recording a fall or heart alert in Apple Health.
    /// The wearer's settings still decide whether it starts a check-in.
    func simulateHealthAlert(_ kind: HealthAlertKind) async {
        await run("Sending…", success: "Simulated \(kind.label.lowercased()) sent. The iPhone checks in if that alert is on.") { api, userId in
            try await api.sendCommand(userId: userId, AdminCommandRequest(kind: .simulateHealthAlert, healthAlert: kind))
        }
    }

    func cutConnection(seconds: Int) async {
        await run("Sending…", success: "Cut sent. The iPhone stops heartbeats and sending for \(seconds) s.") { api, userId in
            try await api.sendCommand(userId: userId, AdminCommandRequest(kind: .cutConnection, durationSeconds: seconds))
        }
    }

    func disableAlarm() async {
        await run("Disabling…", success: "Alarm disabled. Pending backup texts are cancelled.") { api, userId in
            try await api.sendCommand(userId: userId, AdminCommandRequest(kind: .disableAlarm))
        }
    }

    func setTimers(countdown: Int, ackWindow: Int) async {
        await run("Sending…", success: "Timers sent to the iPhone.") { api, userId in
            try await api.sendCommand(userId: userId, AdminCommandRequest(kind: .setTimers, countdownSeconds: countdown, ackWindowSeconds: ackWindow))
        }
    }

    func expireTemporary() async {
        await run("Expiring…", success: "Temporary contact expired. They won't get new alerts.") { api, userId in
            try await api.expireTemporary(userId: userId, ExpireTemporaryRequest(contactId: nil))
        }
    }

    func reset() async {
        await run("Resetting…", success: "Demo reset. Old alarms and timers are gone.") { api, userId in
            try await api.resetDemo(userId: userId)
        }
    }

    func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
