import Foundation
import RippleKit

// The temporary contact consent page. No app, account or login.

extension Engine {
    func inviteAccess(_ raw: String) throws -> TemporaryContactRecord {
        guard let id = db.inviteTokens[Secrets.hash(raw)], let record = db.temporaryContacts[id] else {
            throw EngineError.notFound("This invitation link isn't valid.")
        }
        guard db.users[record.userId]?.runId == record.runId, record.state != .removed else {
            throw EngineError.gone("This invitation was withdrawn.")
        }
        return record
    }

    func inviteView(_ record: TemporaryContactRecord) -> TemporaryInviteView {
        let view = temporaryView(record, at: now())
        return TemporaryInviteView(
            wearerName: db.users[record.userId]?.displayName ?? "A Ripple user",
            contactName: record.name,
            phoneHint: Phone.hint(record.phone),
            shareLocation: record.shareLocation,
            state: view.state,
            durationMinutes: Int(config.temporarySessionSeconds / 60),
            expiresAt: record.expiresAt
        )
    }

    public func invitePage(token raw: String) throws -> TemporaryInviteView {
        inviteView(try inviteAccess(raw))
    }

    /// Records consent and starts the one-hour session.
    public func acceptInvite(token raw: String) throws -> TemporaryInviteView {
        var record = try inviteAccess(raw)
        guard record.state == .invited else { return inviteView(record) }
        let t = now()
        record.state = .active
        record.consentAt = t
        record.expiresAt = t.addingTimeInterval(config.temporarySessionSeconds)
        db.temporaryContacts[record.id] = record
        log(record.userId, "\(record.name) agreed to be a temporary contact until \(timeText(record.expiresAt!)). They join Tier 1 until then.")
        dirty = true
        persistIfDirty()
        return inviteView(record)
    }
}
