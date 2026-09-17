import Foundation

/// Metadata written at ride start, before any fix arrives, so a ride that is
/// cut short by a crash can still be reconstructed.
struct RideMeta: Codable, Equatable {
    var rideId: UUID
    var startedAt: Date
    var appVersion: String
    var settings: TunableSettings
    var hazardSource: String
    var hazards: [Hazard]
}

/// One JSON file per ride. The deliverable.
struct RideLog: Codable, Equatable {
    var rideId: UUID
    var appVersion: String
    var startedAt: Date
    var endedAt: Date
    /// True when the app did not stop this ride cleanly and it was assembled on next launch.
    var recovered: Bool
    /// The constants in effect for this ride.
    var settings: TunableSettings
    /// Which file the hazards came from.
    var hazardSource: String
    /// Snapshot of every active hazard at ride start.
    var hazards: [Hazard]
    var track: [TrackPoint]
    var alerts: [AlertEvent]
    var nearMisses: [NearMissEvent]
    var reports: [Report]
    var diagnostics: [DiagnosticEntry]
    var summary: RideSummary
}

/// Roadside-readable numbers, computed from the log.
struct RideSummary: Codable, Equatable {
    var durationSeconds: Double
    var distanceMeters: Double
    var fixCount: Int
    /// Longest interval between consecutive fixes. The Milestone 0 pass criterion.
    var maxGapSeconds: Double
    var gapsOver5s: Int
    var maxSpeedMetersPerSecond: Double
    var meanMovingSpeedMetersPerSecond: Double
    var alertsFired: Int
    var alertsDropped: Int
    var meanTimeToHazardSeconds: Double?
    var meanDistanceAtTriggerMeters: Double?
    var meanPlaybackLatencySeconds: Double?
    var nearMisses: Int
    var reports: Int
    var errors: Int

    static func compute(
        track: [TrackPoint],
        alerts: [AlertEvent],
        nearMisses: [NearMissEvent],
        reports: [Report],
        diagnostics: [DiagnosticEntry],
        startedAt: Date,
        endedAt: Date
    ) -> RideSummary {
        var distance = 0.0
        var maxGap = 0.0
        var gapsOver5 = 0
        var maxSpeed = 0.0
        var movingSpeedSum = 0.0
        var movingCount = 0

        var previous: TrackPoint?
        for point in track {
            if let p = previous {
                distance += Geo.distanceMeters(lat1: p.lat, lon1: p.lon, lat2: point.lat, lon2: point.lon)
                let gap = point.timestamp.timeIntervalSince(p.timestamp)
                if gap > maxGap { maxGap = gap }
                if gap > 5 { gapsOver5 += 1 }
            }
            if let s = point.validSpeed {
                if s > maxSpeed { maxSpeed = s }
                if s > 1 {
                    movingSpeedSum += s
                    movingCount += 1
                }
            }
            previous = point
        }

        let played = alerts.filter { !$0.dropped }
        let dropped = alerts.count - played.count
        let tth = played.compactMap { $0.timeToHazardSeconds }
        let dist = played.map { $0.distanceMeters }
        let latency = played.compactMap { $0.playbackLatencySeconds }

        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        return RideSummary(
            durationSeconds: endedAt.timeIntervalSince(startedAt),
            distanceMeters: distance,
            fixCount: track.count,
            maxGapSeconds: maxGap,
            gapsOver5s: gapsOver5,
            maxSpeedMetersPerSecond: maxSpeed,
            meanMovingSpeedMetersPerSecond: movingCount > 0 ? movingSpeedSum / Double(movingCount) : 0,
            alertsFired: played.count,
            alertsDropped: dropped,
            meanTimeToHazardSeconds: mean(tth),
            meanDistanceAtTriggerMeters: mean(dist),
            meanPlaybackLatencySeconds: mean(latency),
            nearMisses: nearMisses.count,
            reports: reports.filter { $0.status != .discarded }.count,
            errors: diagnostics.filter { $0.level == .error }.count
        )
    }
}
