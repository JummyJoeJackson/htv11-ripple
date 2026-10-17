import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RippleAPIError: LocalizedError, Sendable {
    case server(status: Int, code: String, message: String)
    case transport(String)
    case decoding(String)
    case badServerURL

    public var errorDescription: String? {
        switch self {
        case .server(_, _, let message): return message
        case .transport(let message): return "Can't reach the Ripple server. \(message)"
        case .decoding(let message): return "Unexpected response from the server. \(message)"
        case .badServerURL: return "The server address isn't a valid URL."
        }
    }

    public var isUnauthorized: Bool {
        if case .server(let status, _, _) = self { return status == 401 }
        return false
    }
}

/// Thin async client for the Ripple backend.
public final class RippleAPI: @unchecked Sendable {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String?, timeout: TimeInterval = 6) {
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

    public func get<Out: Decodable>(_ path: String, as type: Out.Type = Out.self) async throws -> Out {
        let data = try await perform("GET", path, body: nil, idempotencyKey: nil)
        return try decode(Out.self, from: data)
    }

    public func send<In: Encodable, Out: Decodable>(_ method: String, _ path: String, body: In, idempotencyKey: String? = nil, as type: Out.Type = Out.self) async throws -> Out {
        let payload: Data
        do {
            payload = try RippleJSON.encoder.encode(body)
        } catch {
            throw RippleAPIError.decoding("Couldn't encode the request.")
        }
        let data = try await perform(method, path, body: payload, idempotencyKey: idempotencyKey)
        return try decode(Out.self, from: data)
    }

    private func decode<Out: Decodable>(_ type: Out.Type, from data: Data) throws -> Out {
        do {
            return try RippleJSON.decoder.decode(Out.self, from: data)
        } catch {
            throw RippleAPIError.decoding(String(describing: error))
        }
    }

    private func perform(_ method: String, _ path: String, body: Data?, idempotencyKey: String?) async throws -> Data {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/" + path) else { throw RippleAPIError.badServerURL }

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
            throw RippleAPIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RippleAPIError.transport("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? RippleJSON.decoder.decode(APIErrorBody.self, from: data) {
                throw RippleAPIError.server(status: http.statusCode, code: body.code, message: body.message)
            }
            throw RippleAPIError.server(status: http.statusCode, code: "http_\(http.statusCode)", message: "The server returned status \(http.statusCode).")
        }
        return data
    }
}

private struct EmptyBody: Codable {}

// MARK: - Wearer

public extension RippleAPI {
    func setup(_ body: SetupRequest) async throws -> SetupResponse {
        try await send("POST", "v1/wearer/setup", body: body)
    }

    /// The wearer iPhone's heartbeat: reports status and the alarm, receives
    /// admin commands, acknowledgments and backup sends.
    func sync(_ body: SyncRequest) async throws -> SyncResponse {
        try await send("POST", "v1/wearer/sync", body: body)
    }

    func inviteTemporary(_ body: InviteTemporaryRequest) async throws -> InviteTemporaryResponse {
        try await send("POST", "v1/wearer/temporary", body: body, idempotencyKey: RippleID.make())
    }

    func joinTemporary(_ body: JoinTemporaryRequest) async throws -> JoinTemporaryResponse {
        try await send("POST", "v1/wearer/temporary/join", body: body)
    }

    func removeTemporary(id: String) async throws -> TemporaryContactsResponse {
        try await send("POST", "v1/wearer/temporary/\(id)/remove", body: EmptyBody())
    }
}

// MARK: - Demo admin

public extension RippleAPI {
    func adminLogin(_ body: AdminLoginRequest) async throws -> AdminLoginResponse {
        try await send("POST", "v1/admin/login", body: body)
    }

    func pair(_ body: PairRequest) async throws -> PairResponse {
        try await send("POST", "v1/admin/pair", body: body)
    }

    func adminWearers() async throws -> [AdminWearerSummary] {
        try await get("v1/admin/wearers")
    }

    func adminView(userId: String) async throws -> AdminWearerView {
        try await get("v1/admin/wearers/\(userId)")
    }

    func sendCommand(userId: String, _ body: AdminCommandRequest) async throws -> AdminWearerView {
        try await send("POST", "v1/admin/wearers/\(userId)/commands", body: body, idempotencyKey: RippleID.make())
    }

    func expireTemporary(userId: String, _ body: ExpireTemporaryRequest) async throws -> AdminWearerView {
        try await send("POST", "v1/admin/wearers/\(userId)/expire-temporary", body: body)
    }

    func resetDemo(userId: String) async throws -> AdminWearerView {
        try await send("POST", "v1/admin/wearers/\(userId)/reset", body: EmptyBody(), idempotencyKey: RippleID.make())
    }
}
