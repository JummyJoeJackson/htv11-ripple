import Crypto
import Foundation
import KazeEngine
import KazeKit
import Vapor

func routes(_ app: Application, engine: Engine, publicDirectory: String, twilioAuthToken: String?, baseURL: String) throws {
    app.get("health") { _ in "ok" }

    // Web pages for helpers and responders. No app install, no login.
    app.get("e", ":token") { _ in page("enroll.html", publicDirectory: publicDirectory) }
    app.get("r", ":token") { _ in page("respond.html", publicDirectory: publicDirectory) }

    let v1 = app.grouped("v1")

    // MARK: Wearer

    let wearer = v1.grouped("wearer")

    wearer.post("setup") { req async throws -> Response in
        let body = try decodeBody(SetupRequest.self, req)
        let result = try await engine.setup(body)
        return try json(result, status: .created)
    }

    wearer.get("state") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        return try json(try await engine.wearerState(userId: userId))
    }

    wearer.put("config") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(ConfigRequest.self, req)
        return try json(try await engine.updateConfig(userId: userId, body))
    }

    wearer.put("contacts") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(ContactsRequest.self, req)
        return try json(try await engine.replaceContacts(userId: userId, body))
    }

    wearer.put("pins") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(PinsRequest.self, req)
        return try json(try await engine.setPins(userId: userId, body))
    }

    wearer.post("session", "start") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(StartSessionRequest.self, req)
        return try json(try await engine.startSession(userId: userId, body, key: req.idempotencyKey))
    }

    wearer.post("session", "extend") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(ExtendSessionRequest.self, req)
        return try json(try await engine.extendSession(userId: userId, body, key: req.idempotencyKey))
    }

    wearer.post("session", "end") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        return try json(try await engine.endSession(userId: userId, key: req.idempotencyKey))
    }

    wearer.post("heartbeat") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(HeartbeatRequest.self, req)
        return try json(try await engine.heartbeat(userId: userId, body))
    }

    wearer.post("confirm") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(ConfirmRequest.self, req)
        return try json(try await engine.confirm(userId: userId, body, key: req.idempotencyKey))
    }

    wearer.post("help") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(HelpRequest.self, req)
        return try json(try await engine.help(userId: userId, body, key: req.idempotencyKey))
    }

    wearer.post("cancel") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(CancelRequest.self, req)
        return try json(try await engine.cancel(userId: userId, body, key: req.idempotencyKey))
    }

    wearer.post("coverage") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let body = try decodeBody(InviteHelperRequest.self, req)
        return try json(try await engine.inviteHelper(userId: userId, body, key: req.idempotencyKey), status: .created)
    }

    wearer.post("coverage", ":id", "revoke") { req async throws -> Response in
        let userId = try await engine.authenticateWearer(token: req.bearerToken)
        let id = try req.pathValue("id")
        return try json(try await engine.revokeCoverage(userId: userId, coverageId: id, key: req.idempotencyKey))
    }

    // MARK: Helper enrollment (scoped token)

    v1.get("enroll", ":token") { req async throws -> Response in
        try json(try await engine.enrollView(token: try req.pathValue("token")))
    }

    v1.post("enroll", ":token", "code") { req async throws -> Response in
        try json(try await engine.sendEnrollCode(token: try req.pathValue("token")))
    }

    v1.post("enroll", ":token", "verify") { req async throws -> Response in
        let body = try decodeBody(VerifyCodeRequest.self, req)
        return try json(try await engine.verifyEnrollCode(token: try req.pathValue("token"), body))
    }

    v1.post("enroll", ":token", "accept") { req async throws -> Response in
        let body = try decodeBody(AcceptCoverageRequest.self, req)
        return try json(try await engine.acceptCoverage(token: try req.pathValue("token"), body))
    }

    // MARK: Responder (scoped token)

    v1.get("respond", ":token") { req async throws -> Response in
        try json(try await engine.responderView(token: try req.pathValue("token")))
    }

    v1.post("respond", ":token", "action") { req async throws -> Response in
        let body = try decodeBody(ResponderActionRequest.self, req)
        return try json(try await engine.responderAction(token: try req.pathValue("token"), body, key: req.idempotencyKey))
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

    admin.post("wearers", ":id", "trigger-checkin") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        let body = try decodeBody(TriggerCheckInRequest.self, req)
        return try json(try await engine.triggerCheckIn(adminId: adminId, userId: try req.pathValue("id"), body, key: req.idempotencyKey))
    }

    admin.post("wearers", ":id", "trigger-help") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        return try json(try await engine.triggerHelp(adminId: adminId, userId: try req.pathValue("id"), key: req.idempotencyKey))
    }

    admin.post("wearers", ":id", "stop") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        let body = try decodeBody(StopRequest.self, req)
        return try json(try await engine.stopIncident(adminId: adminId, userId: try req.pathValue("id"), body, key: req.idempotencyKey))
    }

    admin.post("wearers", ":id", "reset") { req async throws -> Response in
        let adminId = try await engine.authenticateAdmin(token: req.bearerToken)
        return try json(try await engine.resetRun(adminId: adminId, userId: try req.pathValue("id"), key: req.idempotencyKey))
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
            await engine.recordProviderStatus(providerMessageId: sid, status: status, errorCode: params["ErrorCode"])
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
