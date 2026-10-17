import Crypto
import Foundation
import RippleEngine
import RippleKit
import Vapor

func routes(_ app: Application, engine: Engine, publicDirectory: String, twilioAuthToken: String?, baseURL: String) throws {
    app.get("health") { _ in "ok" }

    // Temporary-contact consent. No app, account or login.
    app.get("t", ":token") { _ in page("invite.html", publicDirectory: publicDirectory) }

    let v1 = app.grouped("v1")

    // MARK: Wearer iPhone

    let wearer = v1.grouped("wearer")

    wearer.post("setup") { req async throws -> Response in
        let body = try decodeBody(SetupRequest.self, req)
        return try json(try await engine.setup(body), status: .created)
    }

    wearer.post("sync") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(SyncRequest.self, req)
        return try json(try await engine.sync(userId: userId, body))
    }

    wearer.post("temporary") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(InviteTemporaryRequest.self, req)
        return try json(try await engine.inviteTemporary(userId: userId, body, key: req.idempotencyKey), status: .created)
    }

    wearer.post("temporary", ":id", "remove") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        return try json(try await engine.removeTemporary(userId: userId, contactId: try req.pathValue("id")))
    }

    // MARK: Temporary contact consent page

    v1.get("temporary", ":token") { req async throws -> Response in
        try json(try await engine.invitePage(token: try req.pathValue("token")))
    }

    v1.post("temporary", ":token", "accept") { req async throws -> Response in
        try json(try await engine.acceptInvite(token: try req.pathValue("token")))
    }

    // MARK: Demo admin

    let admin = v1.grouped("admin")

    admin.post("login") { req async throws -> Response in
        let body = try decodeBody(AdminLoginRequest.self, req)
        return try json(try await engine.adminLogin(body))
    }

    admin.post("pair") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        let body = try decodeBody(PairRequest.self, req)
        return try json(try await engine.pair(adminId: adminId, body))
    }

    admin.get("wearers") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        return try json(await engine.adminWearers(adminId: adminId))
    }

    admin.get("wearers", ":id") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        return try json(try await engine.adminView(adminId: adminId, userId: try req.pathValue("id")))
    }

    admin.post("wearers", ":id", "commands") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        let body = try decodeBody(AdminCommandRequest.self, req)
        return try json(try await engine.sendCommand(adminId: adminId, userId: try req.pathValue("id"), body, key: req.idempotencyKey))
    }

    admin.post("wearers", ":id", "expire-temporary") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        let body = try decodeBody(ExpireTemporaryRequest.self, req)
        return try json(try await engine.expireTemporary(adminId: adminId, userId: try req.pathValue("id"), body))
    }

    admin.post("wearers", ":id", "reset") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        return try json(try await engine.resetDemo(adminId: adminId, userId: try req.pathValue("id"), key: req.idempotencyKey))
    }

    // MARK: Twilio delivery status callback

    v1.post("webhooks", "twilio") { req async throws -> Response in
        let params = (try? req.content.decode([String: String].self)) ?? [:]
        if let authToken = twilioAuthToken {
            let signature = req.headers.first(name: "X-Twilio-Signature") ?? ""
            let url = baseURL + "/v1/webhooks/twilio"
            guard TwilioSignature.isValid(signature: signature, url: url, params: params, authToken: authToken) else {
                return Response(status: .forbidden)
            }
        }
        if let sid = params["MessageSid"], let status = params["MessageStatus"] {
            await engine.recordProviderStatus(providerMessageId: sid, status: status)
        }
        return Response(status: .noContent)
    }
}

enum TwilioSignature {
    /// https://www.twilio.com/docs/usage/security#validating-requests
    static func isValid(signature: String, url: String, params: [String: String], authToken: String) -> Bool {
        let payload = url + params.keys.sorted().map { $0 + (params[$0] ?? "") }.joined()
        let key = SymmetricKey(data: Data(authToken.utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(mac).base64EncodedString() == signature
    }
}
