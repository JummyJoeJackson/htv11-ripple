import Foundation

/// What a responder may see about the wearer during an alert (PRD §3).
public struct SharePermissions: Codable, Hashable, Sendable {
    public var name: Bool
    public var venue: Bool
    public var location: Bool
    public var contactInfo: Bool
    public var helpCard: Bool

    public init(name: Bool = true, venue: Bool = true, location: Bool = true, contactInfo: Bool = true, helpCard: Bool = true) {
        self.name = name
        self.venue = venue
        self.location = location
        self.contactInfo = contactInfo
        self.helpCard = helpCard
    }

    /// Trusted contacts see everything by default.
    public static let contactDefault = SharePermissions()
    /// Temporary helpers don't get the wearer's phone number by default.
    public static let helperDefault = SharePermissions(name: true, venue: true, location: true, contactInfo: false, helpCard: true)

    /// Plain-language list of what is shared, for enrollment pages and settings.
    public var labels: [String] {
        var result: [String] = []
        if name { result.append("Their chosen name") }
        if venue { result.append("The venue") }
        if location { result.append("Last-known location, only during an alert") }
        if contactInfo { result.append("Their phone number") }
        if helpCard { result.append("Their help card") }
        return result
    }
}

/// All timings are configurable (PRD §4). The defaults are demo settings,
/// not medically validated values.
public struct TimingSettings: Codable, Hashable, Sendable {
    /// Seconds after the expected end before the check-in prompt.
    public var graceSeconds: Int
    /// Seconds the wearer has to answer a check-in.
    public var responseWindowSeconds: Int
    /// Seconds a responder has to acknowledge before the next one is alerted.
    public var ackWindowSeconds: Int
    /// Seconds without progress after an acknowledgment before escalating again.
    public var followUpWindowSeconds: Int
    /// Seconds without iPhone heartbeats or watch contact before an alert. 0 turns this off.
    public var connectionGraceSeconds: Int
    /// Extra attempts after a failed message submission.
    public var maxRetries: Int

    public init(graceSeconds: Int, responseWindowSeconds: Int, ackWindowSeconds: Int, followUpWindowSeconds: Int, connectionGraceSeconds: Int, maxRetries: Int) {
        self.graceSeconds = graceSeconds
        self.responseWindowSeconds = responseWindowSeconds
        self.ackWindowSeconds = ackWindowSeconds
        self.followUpWindowSeconds = followUpWindowSeconds
        self.connectionGraceSeconds = connectionGraceSeconds
        self.maxRetries = maxRetries
    }

    /// Suggested filming settings from PRD §4.
    public static let demo = TimingSettings(
        graceSeconds: 5,
        responseWindowSeconds: 15,
        ackWindowSeconds: 15,
        followUpWindowSeconds: 30,
        connectionGraceSeconds: 45,
        maxRetries: 1
    )
}

public struct LocationFix: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyMeters: Double
    public var capturedAt: Date

    public init(latitude: Double, longitude: Double, accuracyMeters: Double, capturedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.capturedAt = capturedAt
    }
}
