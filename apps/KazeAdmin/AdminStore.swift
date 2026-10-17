import Foundation
import KazeKit
import Observation

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

/// The demo admin app's state. Commands run through the same backend as the
/// real flow; nothing here simulates timers locally.
@MainActor
@Observable
final class AdminStore {
    private(set) var serverAddress: String
    private(set) var adminToken: String?
    private(set) var adminName: String
    private(set) var wearers: [AdminWearerSummary] = []
    private(set) var selectedUserId: String?
    private(set) var view: AdminView?
    private(set) var connection: AdminConnection = .unknown
    private(set) var pending: String?
    var banner: AdminBanner?
    private(set) var serverOffset: TimeInterval = 0

    @ObservationIgnored private var api: KazeAPI?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private enum Keys {
        static let server = "kaze.admin.serverAddress"
        static let token = "kaze.admin.token"
        static let name = "kaze.admin.name"
    }

    var isSignedIn: Bool { adminToken != nil }

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        adminToken = UserDefaults.standard.string(forKey: Keys.token)
        adminName = UserDefaults.standard.string(forKey: Keys.name) ?? ""
        rebuildAPI()
    }

    private func rebuildAPI() {
        if let adminToken, let url = KazeAPI.normalizedURL(from: serverAddress) {
            api = KazeAPI(baseURL: url, token: adminToken)
        } else {
            api = nil
        }
    }

    // MARK: Sign in

    func signIn(address: String, secret: String, name: String) async -> Bool {
        guard let url = KazeAPI.normalizedURL(from: address) else {
            banner = AdminBanner(text: "Enter the server address printed in the server console.", ok: false)
            return false
        }
        pending = "Signing in…"
        defer { pending = nil }
        do {
            let response = try await KazeAPI(baseURL: url, token: nil).adminLogin(AdminLoginRequest(secret: secret, name: name))
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
        } catch let error as KazeAPIError where error.isUnauthorized {
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
                await self?.refreshView()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func refreshView() async {
        guard let api, let userId = selectedUserId else { return }
        do {
            let fresh = try await api.adminView(userId: userId)
            guard selectedUserId == userId else { return }
            view = fresh
            serverOffset = fresh.serverTime.timeIntervalSince(Date())
            connection = .online
        } catch {
            connection = .offline(describe(error))
        }
    }

    // MARK: Demo commands

    @discardableResult
    private func command(_ pendingText: String, success: String, _ action: @escaping (KazeAPI, String) async throws -> AdminView?) async -> Bool {
        guard let api, let userId = selectedUserId else { return false }
        pending = pendingText
        defer { pending = nil }
        do {
            if let fresh = try await action(api, userId) {
                view = fresh
            }
            banner = AdminBanner(text: success, ok: true)
            await refreshView()
            return true
        } catch {
            banner = AdminBanner(text: "Not confirmed. \(describe(error))", ok: false)
            await refreshView()
            return false
        }
    }

    func triggerCheckIn(window: Int) async {
        await command("Starting check-in…", success: "Simulated event: check-in sent to the watch.") { api, userId in
            try await api.triggerCheckIn(userId: userId, TriggerCheckInRequest(responseWindowSeconds: window))
        }
    }

    func triggerHelp() async {
        await command("Requesting help…", success: "Simulated help request sent.") { api, userId in
            try await api.triggerHelp(userId: userId)
        }
    }

    func stop(reason: String) async {
        await command("Stopping alert…", success: "Alert stopped. Contacted responders get an update.") { api, userId in
            try await api.stopIncident(userId: userId, StopRequest(reason: reason))
        }
    }

    func reset() async {
        await command("Resetting…", success: "Demo reset. Start a new session on the wearer's iPhone.") { api, userId in
            _ = try await api.resetRun(userId: userId)
            return nil
        }
    }

    func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
