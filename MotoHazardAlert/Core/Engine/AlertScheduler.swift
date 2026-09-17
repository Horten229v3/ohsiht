import Foundation

/// Serialises alerts: never two at once, a fixed silence between them, and if
/// the queue grows past the limit, play only the nearest and drop the rest — a
/// rider cannot act on a list.
///
/// Time-driven and pure: the ride session calls `dequeue(now:...)` on each fix
/// and after each playback finishes.
struct AlertScheduler: Equatable {
    struct Pending: Equatable {
        var hazard: Hazard
        var event: AlertEvent
    }

    struct Decision: Equatable {
        var play: Pending?
        var dropped: [Pending]
    }

    private(set) var queue: [Pending] = []
    private(set) var isPlaying = false
    private(set) var lastFinishedAt: Date?

    var queuedCount: Int { queue.count }

    mutating func enqueue(_ pending: Pending) {
        var p = pending
        p.event.queueDepthAtTrigger = queue.count + (isPlaying ? 1 : 0)
        queue.append(p)
    }

    /// Decide what to do right now. Returns at most one alert to play, plus any
    /// alerts dropped by the overflow rule (already marked `dropped` with a reason).
    mutating func dequeue(
        now: Date,
        riderLat: Double,
        riderLon: Double,
        gapSeconds: TimeInterval,
        maxQueued: Int
    ) -> Decision {
        var dropped: [Pending] = []

        if queue.count > maxQueued {
            let nearestIndex = queue.indices.min { a, b in
                distance(queue[a], riderLat, riderLon) < distance(queue[b], riderLat, riderLon)
            }!
            let keep = queue[nearestIndex]
            for (i, p) in queue.enumerated() where i != nearestIndex {
                var d = p
                d.event.dropped = true
                d.event.dropReason = "queue overflow (\(queue.count) queued, limit \(maxQueued)); nearest kept"
                dropped.append(d)
            }
            queue = [keep]
        }

        guard !isPlaying, !queue.isEmpty else {
            return Decision(play: nil, dropped: dropped)
        }
        if let last = lastFinishedAt, now.timeIntervalSince(last) < gapSeconds {
            return Decision(play: nil, dropped: dropped)
        }

        let next = queue.removeFirst()
        isPlaying = true
        return Decision(play: next, dropped: dropped)
    }

    mutating func playbackFinished(at time: Date) {
        isPlaying = false
        lastFinishedAt = time
    }

    /// Playback never started (audio error). Do not hold the queue hostage.
    mutating func playbackFailed(at time: Date) {
        isPlaying = false
        lastFinishedAt = time
    }

    mutating func reset() {
        queue.removeAll()
        isPlaying = false
        lastFinishedAt = nil
    }

    private func distance(_ p: Pending, _ lat: Double, _ lon: Double) -> Double {
        Geo.distanceMeters(lat1: lat, lon1: lon, lat2: p.hazard.lat, lon2: p.hazard.lon)
    }
}
