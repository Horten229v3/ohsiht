import Foundation

/// Tracks hazards that are **in range but silent**: closer than the trigger
/// distance, yet rejected by a gate other than "already fired". One record per
/// approach ("encounter"), closed when the hazard leaves range, fires after all,
/// or the ride ends.
///
/// The normal lifecycle — approaching while out of range, then passing an alerted
/// hazard — is deliberately not logged; it would bury the false-negative signal.
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
        now: Date
    ) -> NearMissEvent? {
        if verdict.fires {
            // The hazard fired after all (e.g. the heading matched once the rider
            // rounded a corner). The record shows how long the gate held it back.
            if var open = active.removeValue(forKey: hazard.id) {
                open.exitedAt = now
                open.outcome = .fired
                return open
            }
            return nil
        }

        let gates = verdict.rejectedGates
        let distance = verdict.distanceMeters
        let inRange = !gates.contains(.outOfRange)
        let silentForAReason = !gates.contains(.alreadyFired)

        if inRange, silentForAReason {
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
                    outcome: .leftRange
                )
            }
            return nil
        }

        if var open = active.removeValue(forKey: hazard.id) {
            open.exitedAt = now
            open.outcome = .leftRange
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
