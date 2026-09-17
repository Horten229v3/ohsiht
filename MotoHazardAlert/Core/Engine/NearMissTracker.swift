import Foundation

/// Tracks hazards that are close but not firing, one record per approach.
/// Logging every 1 Hz rejection would bury the signal; logging nothing would hide
/// the false-negative side of the timing question.
struct NearMissTracker: Equatable {
    private var active: [UUID: NearMissEvent] = [:]

    var activeCount: Int { active.count }

    /// Feed one verdict for one hazard. Returns a completed encounter if this
    /// observation closed one.
    mutating func observe(
        hazard: Hazard,
        verdict: Verdict,
        rider: TrackPoint,
        smoothedSpeed: Double,
        now: Date,
        radiusMeters: Double
    ) -> NearMissEvent? {
        let distance = verdict.distanceMeters

        if verdict.fires {
            // The hazard fired after all: close any open encounter as such.
            if var open = active.removeValue(forKey: hazard.id) {
                open.exitedAt = now
                open.outcome = .fired
                return open
            }
            return nil
        }

        let gates = verdict.rejectedGates
        // "Already fired and nothing else wrong" is the normal state right after an
        // alert, not a near-miss.
        let onlyAlreadyFired = gates == [.alreadyFired]

        if distance <= radiusMeters, !onlyAlreadyFired {
            if var open = active[hazard.id] {
                if distance < open.closestDistanceMeters {
                    open.closestDistanceMeters = distance
                    open.closestAt = now
                    open.riderLatAtClosest = rider.lat
                    open.riderLonAtClosest = rider.lon
                    open.riderSpeedAtClosest = smoothedSpeed
                    open.riderCourseAtClosest = rider.course
                    open.triggerDistanceAtClosest = verdict.triggerDistanceMeters
                    open.rejectedBy = gates
                }
                active[hazard.id] = open
            } else {
                active[hazard.id] = NearMissEvent(
                    id: UUID(),
                    hazardId: hazard.id,
                    category: hazard.category,
                    enteredAt: now,
                    exitedAt: nil,
                    closestDistanceMeters: distance,
                    closestAt: now,
                    riderLatAtClosest: rider.lat,
                    riderLonAtClosest: rider.lon,
                    riderSpeedAtClosest: smoothedSpeed,
                    riderCourseAtClosest: rider.course,
                    triggerDistanceAtClosest: verdict.triggerDistanceMeters,
                    rejectedBy: gates,
                    outcome: .leftRadius
                )
            }
            return nil
        }

        if var open = active.removeValue(forKey: hazard.id) {
            open.exitedAt = now
            open.outcome = .leftRadius
            return open
        }
        return nil
    }

    /// Close every open encounter (ride ended).
    mutating func drain(at now: Date) -> [NearMissEvent] {
        let closed = active.values.map { open -> NearMissEvent in
            var e = open
            e.exitedAt = now
            e.outcome = .rideEnded
            return e
        }
        active.removeAll()
        return closed.sorted { $0.enteredAt < $1.enteredAt }
    }
}
