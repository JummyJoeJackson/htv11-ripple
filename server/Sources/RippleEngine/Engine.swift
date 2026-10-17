import Foundation
import RippleKit

public struct EngineConfig: Sendable {
    /// Base for acknowledge and consent links, for example http://192.168.1.20:8080.
    public var publicBaseURL: String
    /// If set, backup texts to any other number are refused (designated demo recipients).
    public var demoRecipients: Set<String>?
    public var adminSecret: String
    /// How long the phone may be quiet, or late with a send, before the backup steps in (PRD: 30 s).
    public var backupGraceSeconds: TimeInterval
    /// A one-hour temporary contact session.
    public var temporarySessionSeconds: TimeInterval

    public init(publicBaseURL: String, demoRecipients: Set<String>? = nil, adminSecret: String,
                backupGraceSeconds: TimeInterval = 30, temporarySessionSeconds: TimeInterval = 3600) {
        var base = publicBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        self.publicBaseURL = base
        self.demoRecipients = demoRecipients
        self.adminSecret = adminSecret
        self.backupGraceSeconds = backupGraceSeconds
        self.temporarySessionSeconds = temporarySessionSeconds
    }
}

public struct EngineError: Error, CustomStringConvertible, Sendable {
    public let status: Int
    public let code: String
    public let message: String

    public init(status: Int, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var description: String { "\(status) \(code): \(message)" }

    static func notFound(_ message: String) -> EngineError { EngineError(status: 404, code: "not_found", message: message) }
    static func invalid(_ message: String) -> EngineError { EngineError(status: 422, code: "invalid", message: message) }
    static func conflict(_ code: String, _ message: String) -> EngineError { EngineError(status: 409, code: code, message: message) }
    static func forbidden(_ message: String) -> EngineError { EngineError(status: 403, code: "forbidden", message: message) }
    static func gone(_ message: String) -> EngineError { EngineError(status: 410, code: "closed", message: message) }
    static let unauthorized = EngineError(status: 401, code: "unauthorized", message: "This device isn't signed in. Set it up again.")
}

/// A backup text for the worker to hand to the SMS provider.
public struct OutboundMessage: Sendable {
    public let messageId: String
    public let to: String
    public let body: String
}

public struct SendResult: Sendable {
    public var status: MessageStatus
    public var providerMessageId: String?
    public var error: String?

    public init(status: MessageStatus, providerMessageId: String? = nil, error: String? = nil) {
        self.status = status
        self.providerMessageId = providerMessageId
        self.error = error
    }
}

/// The backup SMS route (Twilio, or the Messages app on the server's Mac).
public protocol MessageSender: Sendable {
    var name: String { get }
    func send(to: String, body: String) async -> SendResult
}

/// The backend's single source of truth. Every change happens inside this
/// actor, one at a time, and is saved to a JSON file.
public actor Engine {
    var db: Database
    let storageURL: URL?
    let config: EngineConfig
    let clock: @Sendable () -> Date
    var dirty = false
    var lastPrune = Date.distantPast

    public init(storageURL: URL?, config: EngineConfig, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.storageURL = storageURL
        self.config = config
        self.clock = clock
        self.db = Engine.load(from: storageURL)
    }

    func now() -> Date { clock() }

    var grace: TimeInterval { config.backupGraceSeconds }

    // MARK: Persistence

    static func load(from url: URL?) -> Database {
        guard let url, let data = try? Data(contentsOf: url) else { return Database() }
        do {
            return try RippleJSON.decoder.decode(Database.self, from: data)
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            print("Ripple: could not read \(url.path) (\(error)). Moved it to \(backup.lastPathComponent) and started with empty data.")
            return Database()
        }
    }

    func persistIfDirty() {
        guard dirty else { return }
        dirty = false
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try RippleJSON.encoder.encode(db)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Ripple: failed to save data: \(error)")
        }
    }

    /// Runs a command at most once per idempotency key and returns the first result for repeats.
    func once<T: Codable>(_ key: String?, scope: String, _ body: () throws -> T) throws -> T {
        guard let key, !key.isEmpty else {
            let result = try body()
            persistIfDirty()
            return result
        }
        let fullKey = scope + ":" + key
        if let record = db.idempotency[fullKey], let cached = try? RippleJSON.decoder.decode(T.self, from: record.response) {
            return cached
        }
        let result = try body()
        if let data = try? RippleJSON.encoder.encode(result) {
            db.idempotency[fullKey] = IdempotencyRecord(response: data, createdAt: now())
            dirty = true
        }
        persistIfDirty()
        return result
    }

    // MARK: Helpers

    func newId() -> String { UUID().uuidString.lowercased() }

    func requireUser(_ userId: String) throws -> WearerRecord {
        guard let user = db.users[userId] else { throw EngineError.unauthorized }
        return user
    }

    func log(_ userId: String, _ text: String) {
        let runId = db.users[userId]?.runId ?? ""
        db.events.append(EventRecord(id: newId(), at: now(), userId: userId, runId: runId, text: text))
        dirty = true
    }

    func isOpen(_ record: AlarmRecord) -> Bool {
        record.snapshot.isOpen && !record.closedByAdmin
    }

    /// The phone is quiet when it hasn't synced within the grace period.
    func phoneSilent(_ user: WearerRecord, at t: Date) -> Bool {
        guard let last = user.lastSyncAt else { return true }
        return t.timeIntervalSince(last) > grace
    }

    func isOnline(_ user: WearerRecord, at t: Date) -> Bool {
        guard let last = user.lastSyncAt else { return false }
        return t.timeIntervalSince(last) <= 10
    }

    func temporaryEligible(_ id: String, at t: Date) -> Bool {
        guard let record = db.temporaryContacts[id] else { return false }
        return record.state == .active && (record.expiresAt ?? .distantPast) > t
    }

    func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }

    func link(_ path: String) -> String {
        config.publicBaseURL + path
    }

    /// The alarm's messages from the phone and the backend, keyed by id. Backup records win.
    func mergedMessages(_ record: AlarmRecord) -> [String: OutMessage] {
        var result: [String: OutMessage] = [:]
        for message in record.snapshot.messages {
            result[message.id] = message
        }
        for backup in db.backups.values where backup.message.alarmId == record.id {
            result[backup.message.id] = backup.message
        }
        return result
    }

    /// When Tier 1 was first actually texted, by either path. A phone alert
    /// that was queued but never handed to Shortcuts doesn't count, so the
    /// acknowledge window starts when someone could really have read a text.
    func alertTime(_ record: AlarmRecord) -> Date? {
        let backupAlerts = db.backups.values
            .filter { $0.message.alarmId == record.id && $0.message.kind == .alert && $0.message.status != .failed }
            .map { $0.message.createdAt }
        let phoneSent = record.snapshot.messages.contains { $0.kind == .alert && $0.path == .phone && $0.mayHaveBeenSent }
        let phoneAlert = phoneSent ? record.snapshot.alertedAt : nil
        return ([phoneAlert].compactMap { $0 } + backupAlerts).min()
    }
}
