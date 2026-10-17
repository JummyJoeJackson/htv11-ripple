import Foundation
import RippleKit
import XCTest
@testable import RippleEngine

final class TemporaryJoinTests: XCTestCase {
    var clock: TestClock!
    var engine: Engine!
    var userId = ""
    var runId = ""

    override func setUp() async throws {
        clock = TestClock()
        let clock = self.clock!
        engine = Engine(storageURL: nil, config: EngineConfig(publicBaseURL: "http://ripple.test", adminSecret: "secret"), clock: { clock.now })
        let setup = try await engine.setup(SetupRequest(displayName: "Alex"))
        userId = setup.userId
        runId = setup.runId
    }

    func invite(phone: String = "416 555 0199", shareLocation: Bool = false, key: String? = nil) async throws -> InviteTemporaryResponse {
        try await engine.inviteTemporary(userId: userId, InviteTemporaryRequest(name: "Riley", phone: phone, shareLocation: shareLocation), key: key)
    }

    func join(_ invitation: InviteTemporaryResponse, from: String? = nil) async throws -> JoinTemporaryResponse {
        try await engine.joinTemporary(userId: userId, JoinTemporaryRequest(runId: runId, code: invitation.joinCode, from: from))
    }

    func testInvitationIsPendingAndExplainsConsentWithoutAWebLink() async throws {
        let invitation = try await invite(shareLocation: true)
        XCTAssertEqual(invitation.contact.state, .invited)
        XCTAssertNil(invitation.contact.consentAt)
        XCTAssertNil(invitation.contact.expiresAt)
        XCTAssertEqual(JoinCode.code(in: invitation.invitationText), invitation.joinCode)
        XCTAssertTrue(invitation.invitationText.contains("one hour"))
        XCTAssertTrue(invitation.invitationText.contains("include the location"))
        XCTAssertFalse(invitation.invitationText.contains("http"))
        let other = try await invite(phone: "416 555 0198")
        XCTAssertNotEqual(invitation.joinCode, other.joinCode)
        XCTAssertTrue(other.invitationText.contains("Location will not be shared"))
        let outbound = await engine.tick()
        XCTAssertTrue(outbound.isEmpty, "Invitations are sent by the phone, never by the backend worker")
    }

    func testOneHourStartsWhenTheBackendAcceptsTheReply() async throws {
        let invitation = try await invite()
        clock.now = clock.now.addingTimeInterval(600)
        let acceptedAt = clock.now
        let response = try await join(invitation, from: "+14165550199")
        XCTAssertEqual(response.contact.state, .active)
        XCTAssertEqual(response.contact.consentAt, acceptedAt)
        XCTAssertEqual(response.contact.expiresAt, acceptedAt.addingTimeInterval(3600))
        XCTAssertEqual(response.contacts.filter { $0.isEligible(at: acceptedAt) }.map(\.id), [invitation.contact.id])
        let coordinator = AlarmCoordinator(config: RippleConfig.makeDefault(wearerName: "Alex"))
        coordinator.temporaryContacts = response.contacts
        coordinator.startMonitoring()
        coordinator.startAlarm(source: .phone)
        XCTAssertEqual(coordinator.alarm?.recipients.filter(\.temporary).map(\.id), [invitation.contact.id])
    }

    func testDuplicateRepliesCannotExtendTheHourAndExpiryIsSilent() async throws {
        let invitation = try await invite()
        let first = try await join(invitation)
        clock.now = clock.now.addingTimeInterval(1800)
        let second = try await join(invitation)
        XCTAssertEqual(second.contact.consentAt, first.contact.consentAt)
        XCTAssertEqual(second.contact.expiresAt, first.contact.expiresAt)
        clock.now = first.contact.expiresAt!
        let views = await engine.temporaryViews(userId)
        XCTAssertEqual(views.first?.state, .expired)
        XCTAssertFalse(views.first!.isEligible(at: clock.now))
        let outbound = await engine.tick()
        XCTAssertTrue(outbound.isEmpty, "No join confirmation, expiry notice, or reminder is queued")
        do {
            _ = try await join(invitation)
            XCTFail("A late repeat must not renew the session")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 410)
        }
    }

    func testWrongCodeWearerRunAndKnownSenderAreRejected() async throws {
        let invitation = try await invite()
        let wrong = invitation.joinCode == "000000" ? "111111" : "000000"
        let other = try await engine.setup(SetupRequest(displayName: "Other wearer"))
        let cases: [(String, JoinTemporaryRequest, Int)] = [
            (userId, JoinTemporaryRequest(runId: runId, code: "12345"), 422),
            (userId, JoinTemporaryRequest(runId: runId, code: wrong), 404),
            (other.userId, JoinTemporaryRequest(runId: other.runId, code: invitation.joinCode), 404),
            (userId, JoinTemporaryRequest(runId: "previous-run", code: invitation.joinCode), 410),
            (userId, JoinTemporaryRequest(runId: runId, code: invitation.joinCode, from: "+14165550198"), 403),
        ]
        for (wearer, request, status) in cases {
            do {
                _ = try await engine.joinTemporary(userId: wearer, request)
                XCTFail("Expected rejection")
            } catch let error as EngineError {
                XCTAssertEqual(error.status, status)
            }
        }
        let views = await engine.temporaryViews(userId)
        XCTAssertEqual(views.first?.state, .invited)
    }

    func testNewPendingInvitationWithdrawsTheOldCode() async throws {
        let old = try await invite()
        let latest = try await invite()
        XCTAssertNotEqual(old.joinCode, latest.joinCode)
        do {
            _ = try await join(old)
            XCTFail("The replaced invitation must not activate")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 410)
        }
        let joined = try await join(latest)
        XCTAssertEqual(joined.contacts.filter { $0.isEligible(at: clock.now) }.map(\.id), [latest.contact.id])
        do {
            _ = try await invite()
            XCTFail("A new invitation must not extend an already active session")
        } catch let error as EngineError {
            XCTAssertEqual(error.code, "already_active")
        }
    }

    func testRemovedInvitationCannotJoin() async throws {
        let invitation = try await invite()
        _ = try await engine.removeTemporary(userId: userId, contactId: invitation.contact.id)
        do {
            _ = try await join(invitation)
            XCTFail("Removed invitation must not activate")
        } catch let error as EngineError {
            XCTAssertEqual(error.status, 410)
        }
    }

    func testInvitationCreationIsIdempotent() async throws {
        let first = try await invite(key: "same-invitation")
        let repeated = try await invite(key: "same-invitation")
        XCTAssertEqual(first.contact.id, repeated.contact.id)
        XCTAssertEqual(first.joinCode, repeated.joinCode)
        XCTAssertEqual(first.invitationText, repeated.invitationText)
    }

    func testLegacyActiveSessionsSurviveAndLinkTokensAreDiscarded() async throws {
        let invitation = try await invite()
        let joined = try await join(invitation)
        let database = await engine.db
        var json = try JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(database)) as! [String: Any]
        var contacts = json["temporaryContacts"] as! [String: [String: Any]]
        contacts[invitation.contact.id]?.removeValue(forKey: "joinCodeHash")
        json["temporaryContacts"] = contacts
        json["inviteTokens"] = ["old-web-token-hash": invitation.contact.id]
        let restored = try RippleJSON.decoder.decode(Database.self, from: JSONSerialization.data(withJSONObject: json))
        let record = try XCTUnwrap(restored.temporaryContacts[invitation.contact.id])
        XCTAssertEqual(record.expiresAt, joined.contact.expiresAt)
        let active = await engine.temporaryView(record, at: clock.now)
        XCTAssertTrue(active.isEligible(at: clock.now))
        let saved = try JSONSerialization.jsonObject(with: RippleJSON.encoder.encode(restored)) as! [String: Any]
        XCTAssertNil(saved["inviteTokens"])
        var pending = record
        pending.state = .invited
        pending.consentAt = nil
        pending.expiresAt = nil
        let retired = await engine.temporaryView(pending, at: clock.now)
        XCTAssertEqual(retired.state, .expired)
    }

    func testAcceptedSessionKeepsItsExpiryAcrossServerRestarts() async throws {
        let invitation = try await invite()
        let joined = try await join(invitation)
        let database = await engine.db
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ripple-join-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: path) }
        try RippleJSON.encoder.encode(database).write(to: path)
        clock.now = clock.now.addingTimeInterval(120)
        let clock = self.clock!
        engine = Engine(storageURL: path, config: EngineConfig(publicBaseURL: "http://ripple.test", adminSecret: "secret"), clock: { clock.now })
        let repeated = try await join(invitation)
        XCTAssertEqual(repeated.contact.expiresAt, joined.contact.expiresAt)
        XCTAssertEqual(repeated.contact.consentAt, joined.contact.consentAt)
    }
}
