import Foundation
import RippleKit

extension Engine {
    func temporaryViews(_ userId: String) -> [TemporaryContactView] {
        guard let user = db.users[userId] else { return [] }
        return db.temporaryContacts.values
            .filter { $0.userId == userId && $0.runId == user.runId }
            .sorted { $0.invitedAt < $1.invitedAt }
            .map { temporaryView($0, at: now()) }
    }

    func temporaryView(_ record: TemporaryContactRecord, at t: Date) -> TemporaryContactView {
        var state = record.state
        if state == .active, (record.expiresAt ?? .distantPast) <= t {
            state = .expired
        } else if state == .invited, record.joinCodeHash == nil {
            // Retired web invitations cannot activate a session. Active legacy
            // sessions retain their original consent and expiry timestamps.
            state = .expired
        }
        return TemporaryContactView(
            id: record.id, name: record.name, phone: record.phone, shareLocation: record.shareLocation, state: state,
            invitedAt: record.invitedAt, consentAt: record.consentAt, expiresAt: record.expiresAt
        )
    }

    public func inviteTemporary(userId: String, _ request: InviteTemporaryRequest, key: String?) throws -> InviteTemporaryResponse {
        try once(key, scope: "\(userId):invite") {
            let user = try requireUser(userId)
            let name = request.name.trimmed
            guard !name.isEmpty else { throw EngineError.invalid("Enter the temporary contact's name.") }
            guard let phone = Phone.normalize(request.phone) else {
                throw EngineError.invalid("That phone number doesn't look right. Include the area code.")
            }
            let existing = db.temporaryContacts.values.filter { $0.userId == userId && $0.runId == user.runId }
            guard !existing.contains(where: { $0.phone == phone && temporaryEligible($0.id, at: now()) }) else {
                throw EngineError.conflict("already_active", "This person is already an active one-hour contact.")
            }
            // A new invitation to the same number withdraws any older pending one.
            for old in existing where old.phone == phone && old.state == .invited {
                db.temporaryContacts[old.id]?.state = .removed
            }
            var code: String
            repeat {
                code = Secrets.randomDigits(6)
            } while existing.contains(where: { $0.joinCodeHash == Secrets.hash(code) })
            let record = TemporaryContactRecord(
                id: newId(), userId: userId, runId: user.runId, name: String(name.prefix(60)), phone: phone,
                shareLocation: request.shareLocation, state: .invited, invitedAt: now(), consentAt: nil, expiresAt: nil,
                joinCodeHash: Secrets.hash(code)
            )
            db.temporaryContacts[record.id] = record
            log(userId, "Invited \(record.name) by text. Not active until their Ripple join reply is accepted.")
            dirty = true
            let location = request.shareLocation
                ? "Alerts to you will include the location recorded when the alert starts."
                : "Location will not be shared with you."
            let text = """
            RIPPLE INVITATION: \(user.displayName) invited you to be a temporary safety contact for one hour.

            If you agree, you may receive Ripple safety alerts during that hour. \(location)

            Reply "Ripple join \(code)" to join. Your one hour starts when your reply is accepted.
            """
            return InviteTemporaryResponse(contact: temporaryView(record, at: now()), joinCode: code, invitationText: text)
        }
    }

    /// The authenticated wearer's phone forwards the reply. Duplicate replies
    /// return the original expiry; joining never sends a confirmation text.
    public func joinTemporary(userId: String, _ request: JoinTemporaryRequest) throws -> JoinTemporaryResponse {
        let user = try requireUser(userId)
        guard request.runId == user.runId else { throw EngineError.gone("This invitation belongs to an earlier session.") }
        guard request.code.count == 6, request.code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw EngineError.invalid("That message has no valid six-digit Ripple join code.")
        }
        let hash = Secrets.hash(request.code)
        guard var record = db.temporaryContacts.values.first(where: {
            $0.userId == userId && $0.runId == user.runId && $0.joinCodeHash == hash
        }) else { throw EngineError.notFound("That Ripple join code doesn't match a current invitation.") }
        if let sender = request.from, let phone = Phone.normalize(sender), phone != record.phone {
            throw EngineError.forbidden("That reply came from a different number than \(record.name)'s.")
        }
        let t = now()
        if record.state == .invited {
            record.state = .active
            record.consentAt = t
            record.expiresAt = t.addingTimeInterval(config.temporarySessionSeconds)
            db.temporaryContacts[record.id] = record
            log(userId, "\(record.name) joined by text until \(timeText(record.expiresAt!)). They join Tier 1 until then.")
            dirty = true
            persistIfDirty()
        } else if !temporaryEligible(record.id, at: t) {
            throw EngineError.gone("This invitation was removed or its one-hour session has expired.")
        }
        return JoinTemporaryResponse(contact: temporaryView(record, at: t), contacts: temporaryViews(userId))
    }

    public func removeTemporary(userId: String, contactId: String) throws -> TemporaryContactsResponse {
        guard var record = db.temporaryContacts[contactId], record.userId == userId else {
            throw EngineError.notFound("That temporary contact doesn't exist.")
        }
        if record.state == .invited || record.state == .active {
            record.state = .removed
            db.temporaryContacts[contactId] = record
            log(userId, "\(record.name) was removed as a temporary contact. They won't receive new alerts.")
            dirty = true
        }
        persistIfDirty()
        return TemporaryContactsResponse(contacts: temporaryViews(userId))
    }
}
