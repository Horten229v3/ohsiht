import Foundation
import XCTest

#if canImport(HazardCore)
@testable import HazardCore
#else
@testable import MotoHazardAlert
#endif

/// Deterministic fixtures. Everything is anchored on a point near Kühtai, Tyrol.
enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let baseLat = 47.2100
    static let baseLon = 11.0100

    static func rider(
        lat: Double = baseLat,
        lon: Double = baseLon,
        speed: Double = 20,
        course: Double = 90,
        time: Date = now,
        accuracy: Double = 5
    ) -> TrackPoint {
        TrackPoint(timestamp: time, lat: lat, lon: lon, speed: speed, course: course, horizontalAccuracy: accuracy)
    }

    /// A hazard `distance` metres from the rider along `bearing`.
    static func hazard(
        from rider: TrackPoint,
        bearing: Double,
        distance: Double,
        heading: Double? = 90,
        tolerance: Double? = nil,
        category: HazardCategory = .gravel,
        createdAt: Date = now.addingTimeInterval(-3600),
        expiresAt: Date? = nil,
        id: UUID = UUID()
    ) -> Hazard {
        let dest = Geo.destination(lat: rider.lat, lon: rider.lon, bearingDegrees: bearing, distanceMeters: distance)
        return Hazard(
            id: id,
            lat: dest.lat,
            lon: dest.lon,
            heading: heading,
            headingTolerance: tolerance,
            category: category,
            createdAt: createdAt,
            expiresAt: expiresAt,
            source: .seeded
        )
    }

    /// A straight track heading east at constant speed, one fix per second.
    static func straightTrack(seconds: Int, speed: Double = 20, course: Double = 90, start: Date = now) -> [TrackPoint] {
        (0..<seconds).map { i in
            let d = Geo.destination(lat: baseLat, lon: baseLon, bearingDegrees: course, distanceMeters: speed * Double(i))
            return TrackPoint(
                timestamp: start.addingTimeInterval(Double(i)),
                lat: d.lat, lon: d.lon,
                speed: speed, course: course, horizontalAccuracy: 5
            )
        }
    }
}
