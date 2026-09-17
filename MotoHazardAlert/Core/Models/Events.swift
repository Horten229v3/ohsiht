import Foundation

/// Written every time the trigger decided to alert. The primary output of the POC.
struct AlertEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var hazardId: UUID
    var category: HazardCategory
    /// When the trigger logic decided to fire.
    var triggeredAt: Date
    /// When audio playback actually started. `nil` if it never did (dropped, or audio failure).
    var playbackStartedAt: Date?
    /// Reported by the audio session: extra delay between "started" and sound at the output
    /// (Bluetooth adds a lot). Not included in `playbackLatencySeconds`.
    var outputLatencySeconds: Double?
    var riderLat: Double
    var riderLon: Double
    /// Smoothed speed (m/s) used for the trigger distance.
    var riderSpeed: Double
    var riderCourse: Double
    var distanceMeters: Double
    /// distance / smoothed speed. `nil` when practically stationary.
    var timeToHazardSeconds: Double?
    var triggerDistanceMeters: Double
    /// Queue position when enqueued (0 = played immediately).
    var queueDepthAtTrigger: Int
    /// True if the queue overflow rule dropped this alert instead of playing it.
    var dropped: Bool
    var dropReason: String?

    var playbackLatencySeconds: Double? {
        playbackStartedAt.map { $0.timeIntervalSince(triggeredAt) }
    }
}

/// A hazard that was within trigger distance but did not fire. One record per
/// approach ("encounter"), closed when the hazard leaves range or fires after all.
struct NearMissEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var hazardId: UUID
    var category: HazardCategory
    var enteredAt: Date
    var exitedAt: Date?
    var closestDistanceMeters: Double
    var closestAt: Date
    var riderLatAtClosest: Double
    var riderLonAtClosest: Double
    var riderSpeedAtClosest: Double
    var riderCourseAtClosest: Double
    var triggerDistanceAtClosest: Double
    /// Gates that rejected the hazard at the moment of closest approach.
    var rejectedBy: [Gate]
    /// How the encounter ended: left trigger range, the hazard fired after all, or ride ended.
    var outcome: Outcome

    enum Outcome: String, Codable {
        case leftRange
        case fired
        case rideEnded
    }
}

/// A rider tap. Categorised after the ride.
struct Report: Codable, Identifiable, Equatable {
    var id: UUID
    var rideId: UUID
    var tappedAt: Date
    /// Where the rider was when the tap registered.
    var raw: Position?
    /// Where the rider was `reactionTimeSeconds` before the tap, interpolated from the track.
    var offset: Position?
    var reactionTimeSeconds: Double
    /// Pending reports carry `.other` so nothing is ever lost if the app is force-quit.
    var category: HazardCategory
    var status: Status
    var categorisedAt: Date?
    /// Set when the categorised report was turned into a live `Hazard`.
    var hazardId: UUID?

    enum Status: String, Codable {
        case pending
        case categorised
        case discarded
    }
}

/// Something went wrong or something notable happened. Logged, never shown mid-ride.
struct DiagnosticEntry: Codable, Equatable {
    var timestamp: Date
    var level: Level
    var message: String

    enum Level: String, Codable {
        case info
        case warning
        case error
    }
}
