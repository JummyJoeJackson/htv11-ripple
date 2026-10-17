import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum KazeAPIError: LocalizedError, Sendable {
    case server(status: Int, code: String, message: String)
    case transport(String)
    case decoding(String)
    case badServerURL

    public var errorDescription: String? {
        switch self {
        case .server(_, _, let message): return message
        case .transport(let message): return "Can't reach the KAZE server. \(message)"
        case .decoding(let message): return "Unexpected response from the server. \(message)"
        case .badServerURL: return "The server address isn't a valid URL."
        }
    }

    public var isUnauthorized: Bool {
        if case .server(let status, _, _) = self { return status == 401 }
        return false
    }

    /// True when the request may never have reached the server.
    public var isTransport: Bool {
        if case .transport = self { return true }
        return false
    }
}

/// Thin async client for the KAZE backend. One instance per server address and token.
public final class KazeAPI: @unchecked Sendable {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String?, timeout: TimeInterval = 8) {
        self.baseURL = baseURL
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// Accepts "192.168.1.20:8080", "http://192.168.1.20:8080" or an https tunnel URL.
    public static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    // MARK: Core

    public func get<Out: Decodable>(_ path: String, as type: Out.Type = Out.self) async throws -> Out {
        let data = try await perform("GET", path, body: nil, idempotencyKey: nil)
        return try decode(Out.self, from: data)
    }

    public func send<In: Encodable, Out: Decodable>(_ method: String, _ path: String, body: In, idempotencyKey: String? = UUID().uuidString, as type: Out.Type = Out.self) async throws -> Out {
        let payload: Data
        do {
            payload = try KazeJSON.encoder.encode(body)
        } catch {
            throw KazeAPIError.decoding("Couldn't encode the request.")
        }
        let data = try await perform(method, path, body: payload, idempotencyKey: idempotencyKey)
        return try decode(Out.self, from: data)
    }

    private func decode<Out: Decodable>(_ type: Out.Type, from data: Data) throws -> Out {
        do {
            return try KazeJSON.decoder.decode(Out.self, from: data)
        } catch {
            throw KazeAPIError.decoding(String(describing: error))
        }
    }

    private func perform(_ method: String, _ path: String, body: Data?, idempotencyKey: String?) async throws -> Data {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/" + path) else { throw KazeAPIError.badServerURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw KazeAPIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw KazeAPIError.transport("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? KazeJSON.decoder.decode(APIErrorBody.self, from: data) {
                throw KazeAPIError.server(status: http.statusCode, code: body.code, message: body.message)
            }
            throw KazeAPIError.server(status: http.statusCode, code: "http_\(http.statusCode)", message: "The server returned status \(http.statusCode).")
        }
        return data
    }
}

// MARK: - Wearer endpoints

public extension KazeAPI {
    func setup(_ body: SetupRequest) async throws -> SetupResponse {
        try await send("POST", "v1/wearer/setup", body: body)
    }

    func wearerState() async throws -> WearerState {
        try await get("v1/wearer/state")
    }

    func updateConfig(_ body: ConfigRequest) async throws -> WearerState {
        try await send("PUT", "v1/wearer/config", body: body)
    }

    func replaceContacts(_ body: ContactsRequest) async throws -> WearerState {
        try await send("PUT", "v1/wearer/contacts", body: body)
    }

    func setPins(_ body: PinsRequest) async throws -> WearerState {
        try await send("PUT", "v1/wearer/pins", body: body)
    }

    func startSession(_ body: StartSessionRequest) async throws -> WearerState {
        try await send("POST", "v1/wearer/session/start", body: body)
    }

    func extendSession(_ body: ExtendSessionRequest) async throws -> WearerState {
        try await send("POST", "v1/wearer/session/extend", body: body)
    }

    func endSession() async throws -> WearerState {
        try await send("POST", "v1/wearer/session/end", body: MessageResponse(message: "end"))
    }

    func heartbeat(_ body: HeartbeatRequest) async throws -> HeartbeatResponse {
        try await send("POST", "v1/wearer/heartbeat", body: body, idempotencyKey: nil)
    }

    func confirm(_ body: ConfirmRequest, key: String = UUID().uuidString) async throws -> ConfirmResponse {
        try await send("POST", "v1/wearer/confirm", body: body, idempotencyKey: key)
    }

    func help(_ body: HelpRequest, key: String = UUID().uuidString) async throws -> MessageResponse {
        try await send("POST", "v1/wearer/help", body: body, idempotencyKey: key)
    }

    func cancel(_ body: CancelRequest) async throws -> MessageResponse {
        try await send("POST", "v1/wearer/cancel", body: body)
    }

    func inviteHelper(_ body: InviteHelperRequest) async throws -> InviteHelperResponse {
        try await send("POST", "v1/wearer/coverage", body: body)
    }

    func revokeCoverage(id: String) async throws -> WearerState {
        try await send("POST", "v1/wearer/coverage/\(id)/revoke", body: MessageResponse(message: "revoke"))
    }
}

// MARK: - Admin endpoints

public extension KazeAPI {
    func adminLogin(_ body: AdminLoginRequest) async throws -> AdminLoginResponse {
        try await send("POST", "v1/admin/login", body: body)
    }

    func pair(_ body: PairRequest) async throws -> PairResponse {
        try await send("POST", "v1/admin/pair", body: body)
    }

    func adminWearers() async throws -> [AdminWearerSummary] {
        try await get("v1/admin/wearers")
    }

    func adminView(userId: String) async throws -> AdminView {
        try await get("v1/admin/wearers/\(userId)")
    }

    func triggerCheckIn(userId: String, _ body: TriggerCheckInRequest) async throws -> AdminView {
        try await send("POST", "v1/admin/wearers/\(userId)/trigger-checkin", body: body)
    }

    func triggerHelp(userId: String) async throws -> AdminView {
        try await send("POST", "v1/admin/wearers/\(userId)/trigger-help", body: MessageResponse(message: "help"))
    }

    func stopIncident(userId: String, _ body: StopRequest) async throws -> AdminView {
        try await send("POST", "v1/admin/wearers/\(userId)/stop", body: body)
    }

    func resetRun(userId: String) async throws -> ResetResponse {
        try await send("POST", "v1/admin/wearers/\(userId)/reset", body: MessageResponse(message: "reset"))
    }
}
