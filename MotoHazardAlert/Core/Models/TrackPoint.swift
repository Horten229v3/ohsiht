import Foundation

/// One GPS fix. Follows CoreLocation conventions: a negative `speed` or
/// `course` means "not available" (typically when stationary).
struct TrackPoint: Codable, Equatable {
    var timestamp: Date
    var lat: Double
    var lon: Double
    /// Metres per second. Negative = invalid.
    var speed: Double
    /// Degrees true, 0–359. Negative = invalid.
    var course: Double
    /// Metres. Negative = invalid.
    var horizontalAccuracy: Double

    var validSpeed: Double? { speed >= 0 ? speed : nil }
    var validCourse: Double? { course >= 0 ? course : nil }
    var hasFix: Bool { horizontalAccuracy >= 0 }
}

/// A position snapshot used for reports (raw tap and reaction-offset point).
struct Position: Codable, Equatable {
    var timestamp: Date
    var lat: Double
    var lon: Double
    var speed: Double
    var course: Double

    init(timestamp: Date, lat: Double, lon: Double, speed: Double, course: Double) {
        self.timestamp = timestamp
        self.lat = lat
        self.lon = lon
        self.speed = speed
        self.course = course
    }

    init(_ point: TrackPoint) {
        self.init(timestamp: point.timestamp, lat: point.lat, lon: point.lon, speed: point.speed, course: point.course)
    }
}
