import Foundation

/// The reasons a hazard is not alerted. Names are stable strings because they
/// end up in the ride log and the owner reads them.
enum Gate: String, Codable, CaseIterable, Equatable {
    /// Gate 1: `now >= expiresAt`.
    case expired
    /// Gate 2: fired already and not yet re-armed.
    case alreadyFired
    /// Gate 3: further away than the trigger distance.
    case outOfRange
    /// Gate 4: bearing to hazard is outside the ahead-cone around the rider's course.
    case notAhead
    /// Gate 5: rider's course is outside the hazard's heading tolerance.
    case headingMismatch
    /// Gates 4 and 5 cannot be evaluated: CoreLocation reports no valid course
    /// (typically stationary). Silence over a guess.
    case noCourse
}

enum Verdict: Equatable {
    case fire(distanceMeters: Double, triggerDistanceMeters: Double)
    case rejected(gates: [Gate], distanceMeters: Double, triggerDistanceMeters: Double)

    var fires: Bool {
        if case .fire = self { return true }
        return false
    }

    var distanceMeters: Double {
        switch self {
        case let .fire(d, _), let .rejected(_, d, _): return d
        }
    }

    var triggerDistanceMeters: Double {
        switch self {
        case let .fire(_, t), let .rejected(_, _, t): return t
        }
    }

    var rejectedGates: [Gate] {
        if case let .rejected(gates, _, _) = self { return gates }
        return []
    }
}

/// Pure trigger logic. No UI, no CoreLocation, no clock of its own: `now` is
/// passed in so tests are deterministic.
///
/// All five gates are evaluated on every call (no short-circuit) so a rejected
/// hazard reports every gate that failed, not just the first. That is what makes
/// near-miss records legible afterwards.
struct TriggerEngine: Equatable {
    var settings: TunableSettings

    init(settings: TunableSettings = .default) {
        self.settings = settings
    }

    func triggerDistance(smoothedSpeed: Double) -> Double {
        settings.triggerDistance(forSpeed: max(0, smoothedSpeed))
    }

    func evaluate(
        rider: TrackPoint,
        smoothedSpeed: Double,
        hazard: Hazard,
        alreadyFired: Set<UUID>,
        now: Date
    ) -> Verdict {
        let distance = Geo.distanceMeters(lat1: rider.lat, lon1: rider.lon, lat2: hazard.lat, lon2: hazard.lon)
        let trigger = triggerDistance(smoothedSpeed: smoothedSpeed)
        var failed: [Gate] = []

        // Gate 1 — not expired.
        if hazard.isExpired(at: now) {
            failed.append(.expired)
        }

        // Gate 2 — not already fired.
        if alreadyFired.contains(hazard.id) {
            failed.append(.alreadyFired)
        }

        // Gate 3 — within range.
        if distance >= trigger {
            failed.append(.outOfRange)
        }

        if let course = rider.validCourse {
            // Gate 4 — ahead, not behind.
            let bearingToHazard = Geo.bearingDegrees(lat1: rider.lat, lon1: rider.lon, lat2: hazard.lat, lon2: hazard.lon)
            if Geo.angularDifference(bearingToHazard, course) > settings.aheadConeDegrees {
                failed.append(.notAhead)
            }

            // Gate 5 — heading matches. Skipped for omnidirectional hazards.
            if let hazardHeading = hazard.heading {
                let tolerance = hazard.resolvedHeadingTolerance(default: settings.defaultHeadingTolerance)
                if Geo.angularDifference(course, hazardHeading) > tolerance {
                    failed.append(.headingMismatch)
                }
            }
        } else {
            failed.append(.noCourse)
        }

        if failed.isEmpty {
            return .fire(distanceMeters: distance, triggerDistanceMeters: trigger)
        }
        return .rejected(gates: failed, distanceMeters: distance, triggerDistanceMeters: trigger)
    }

    /// The signature from the spec. Uses the rider's own speed reading as the
    /// smoothed speed; the ride session calls `evaluate` with a real rolling mean.
    func shouldAlert(rider: TrackPoint, hazard: Hazard, alreadyFired: Set<UUID>, now: Date = Date()) -> Bool {
        evaluate(
            rider: rider,
            smoothedSpeed: rider.validSpeed ?? 0,
            hazard: hazard,
            alreadyFired: alreadyFired,
            now: now
        ).fires
    }
}
