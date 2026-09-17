import Foundation

/// Great-circle geometry on a spherical Earth. Accurate to well under a metre
/// over the distances this app cares about (tens to hundreds of metres).
enum Geo {
    static let earthRadiusMeters = 6_371_008.8

    static func distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dφ = (lat2 - lat1) * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadiusMeters * c
    }

    /// Initial bearing from point 1 to point 2, degrees true in [0, 360).
    static func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let θ = atan2(y, x) * 180 / .pi
        return normaliseDegrees(θ)
    }

    /// Smallest absolute difference between two headings, in [0, 180].
    static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(normaliseDegrees(a) - normaliseDegrees(b))
        return d > 180 ? 360 - d : d
    }

    static func normaliseDegrees(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    /// Destination point given start, bearing and distance. Used by tests and the
    /// seed-template generator; not needed on the hot path.
    static func destination(lat: Double, lon: Double, bearingDegrees: Double, distanceMeters: Double) -> (lat: Double, lon: Double) {
        let δ = distanceMeters / earthRadiusMeters
        let θ = bearingDegrees * .pi / 180
        let φ1 = lat * .pi / 180
        let λ1 = lon * .pi / 180
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        return (φ2 * 180 / .pi, normaliseLongitude(λ2 * 180 / .pi))
    }

    static func normaliseLongitude(_ degrees: Double) -> Double {
        var d = degrees
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    /// Linear interpolation between two fixes at `time`. Course is interpolated on
    /// the circle so 350° → 10° passes through 0°, not 180°.
    static func interpolate(_ a: TrackPoint, _ b: TrackPoint, at time: Date) -> Position {
        let span = b.timestamp.timeIntervalSince(a.timestamp)
        guard span > 0 else { return Position(b) }
        let t = min(max(time.timeIntervalSince(a.timestamp) / span, 0), 1)
        let lat = a.lat + (b.lat - a.lat) * t
        let lon = a.lon + (b.lon - a.lon) * t

        let speed: Double
        switch (a.validSpeed, b.validSpeed) {
        case let (sa?, sb?): speed = sa + (sb - sa) * t
        case let (sa?, nil): speed = sa
        case let (nil, sb?): speed = sb
        default: speed = -1
        }

        let course: Double
        switch (a.validCourse, b.validCourse) {
        case let (ca?, cb?):
            var delta = cb - ca
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            course = normaliseDegrees(ca + delta * t)
        case let (ca?, nil): course = ca
        case let (nil, cb?): course = cb
        default: course = -1
        }

        return Position(timestamp: time, lat: lat, lon: lon, speed: speed, course: course)
    }
}
