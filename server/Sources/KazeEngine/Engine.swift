import Foundation
import KazeKit

public struct EngineConfig: Sendable {
    /// Base for links sent to responders, for example http://192.168.1.20:8080.
    public var publicBaseURL: String
    /// If set, messages to any other number are refused (designated demo recipients).
    public var demoRecipients: Set<String>?
    public var adminSecret: String

    public init(publicBaseURL: String, demoRecipients: Set<String>? = nil, adminSecret: String) {
        var base = publicBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        self.publicBaseURL = base
        self.demoRecipients = demoRecipients
        self.adminSecret = adminSecret
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
    static func gone(_ message: String) -> EngineError { EngineError(status: 410, code: "access_ended", message: message) }
    static func tooMany(_ message: String) -> EngineError { EngineError(status: 429, code: "rate_limited", message: message) }
    static let unauthorized = EngineError(status: 401, code: "unauthorized", message: "This device isn't signed in. Set it up again.")
    static let staleRun = EngineError(status: 409, code: "stale_run", message: "That response belongs to a demo run that was reset.")
}

/// A message the worker should hand to the messaging adapter.
public struct OutboundMessage: Sendable {
    public let deliveryId: String
    public let to: String
    public let body: String
}

public struct SendResult: Sendable {
    public var state: DeliveryState
    public var providerMessageId: String?
    public var error: String?

    public init(state: DeliveryState, providerMessageId: String? = nil, error: String? = nil) {
        self.state = state
        self.providerMessageId = providerMessageId
        self.error = error
    }
}

/// One working SMS route behind an adapter (PRD §5).
public protocol MessageSender: Sendable {
    var name: String { get }
    func send(to: String, body: String) async -> SendResult
}

/// The backend's single source of truth. Every state change happens inside
/// this actor, one at a time, so a response and a timeout can never both win.
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

    // MARK: Persistence

    static func load(from url: URL?) -> Database {
        guard let url, let data = try? Data(contentsOf: url) else { return Database() }
        do {
            return try KazeJSON.decoder.decode(Database.self, from: data)
        } catch {
            // Keep the unreadable file for inspection and start clean.
            let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            print("KAZE: could not read \(url.path) (\(error)). Moved it to \(backup.lastPathComponent) and started with empty data.")
            return Database()
        }
    }

    func persistIfDirty() {
        guard dirty else { return }
        dirty = false
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try KazeJSON.encoder.encode(db)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("KAZE: failed to save data: \(error)")
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
        if let record = db.idempotency[fullKey], let cached = try? KazeJSON.decoder.decode(T.self, from: record.response) {
            return cached
        }
        let result = try body()
        if let data = try? KazeJSON.encoder.encode(result) {
            db.idempotency[fullKey] = IdempotencyRecord(response: data, createdAt: now())
            dirty = true
        }
        persistIfDirty()
        return result
    }

    // MARK: Helpers

    func newId() -> String { UUID().uuidString.lowercased() }

    func bump(_ userId: String) {
        db.users[userId]?.revision += 1
        dirty = true
    }

    func requireUser(_ userId: String) throws -> UserRecord {
        guard let user = db.users[userId] else { throw EngineError.unauthorized }
        return user
    }

    func log(
        _ userId: String,
        session: String? = nil,
        incident: String? = nil,
        actor: ActorType,
        type: String,
        text: String,
        wearer: Bool,
        responders: Bool,
        simulated: Bool = false
    ) {
        let runId = db.users[userId]?.demoRunId ?? ""
        db.events.append(EventRecord(
            id: newId(),
            at: now(),
            userId: userId,
            demoRunId: runId,
            sessionId: session,
            incidentId: incident,
            actor: actor,
            type: type,
            text: text,
            visibleToWearer: wearer,
            visibleToResponders: responders,
            simulated: simulated
        ))
        dirty = true
    }

    func schedule(_ kind: JobKind, target: String, userId: String, at runAt: Date, key: String, version: Int? = nil) {
        if db.jobs.values.contains(where: { $0.dedupeKey == key && $0.state != .cancelled }) {
            return
        }
        let runId = db.users[userId]?.demoRunId ?? ""
        let job = JobRecord(
            id: newId(),
            kind: kind,
            targetId: target,
            userId: userId,
            demoRunId: runId,
            runAt: runAt,
            state: .pending,
            dedupeKey: key,
            version: version,
            createdAt: now(),
            finishedAt: nil,
            note: nil
        )
        db.jobs[job.id] = job
        dirty = true
    }

    func cancelJobs(note: String, where predicate: (JobRecord) -> Bool) {
        for (id, job) in db.jobs where job.state == .pending && predicate(job) {
            db.jobs[id]?.state = .cancelled
            db.jobs[id]?.finishedAt = now()
            db.jobs[id]?.note = note
            dirty = true
        }
    }

    func finish(_ jobId: String, _ state: JobState, note: String? = nil) {
        db.jobs[jobId]?.state = state
        db.jobs[jobId]?.finishedAt = now()
        if let note { db.jobs[jobId]?.note = note }
        dirty = true
    }

    func activeSession(for userId: String) -> SessionRecord? {
        db.sessions.values
            .filter { $0.userId == userId && $0.monitoring == .active }
            .max(by: { $0.startedAt < $1.startedAt })
    }

    func latestSession(for userId: String) -> SessionRecord? {
        db.sessions.values
            .filter { $0.userId == userId }
            .max(by: { $0.startedAt < $1.startedAt })
    }

    /// At most one open incident per wearer; new triggers attach to it.
    func openIncident(for userId: String) -> IncidentRecord? {
        db.incidents.values.first { $0.userId == userId && $0.status == .open }
    }

    func checkIns(for sessionId: String) -> [CheckInRecord] {
        db.checkIns.values.filter { $0.sessionId == sessionId }.sorted { $0.promptAt < $1.promptAt }
    }

    func awaitingCheckIn(for sessionId: String) -> CheckInRecord? {
        checkIns(for: sessionId).first { $0.state == .awaitingResponse }
    }

    func activeCoverage(for userId: String) -> CoverageRecord? {
        let t = now()
        return db.coverages.values.first {
            $0.userId == userId && $0.state == .accepted && $0.startsAt <= t && $0.endsAt > t
        }
    }

    func isActive(_ coverage: CoverageRecord) -> Bool {
        let t = now()
        return coverage.state == .accepted && coverage.startsAt <= t && coverage.endsAt > t
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
}
