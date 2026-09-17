import XCTest

#if canImport(HazardCore)
@testable import HazardCore
#else
@testable import MotoHazardAlert
#endif

final class SpeedSmootherTests: XCTestCase {
    func testRollingMeanOverWindow() {
        var s = SpeedSmoother(window: 5)
        XCTAssertEqual(s.smoothed, 0)
        for v in [10.0, 20, 30] { s.add(v) }
        XCTAssertEqual(s.smoothed, 20, accuracy: 1e-9)
        for v in [40.0, 50, 60] { s.add(v) }
        XCTAssertEqual(s.smoothed, 40, accuracy: 1e-9, "window is the last five: 20,30,40,50,60")
        XCTAssertEqual(s.sampleCount, 5)
    }

    func testIgnoresInvalidSpeeds() {
        var s = SpeedSmoother(window: 5)
        s.add(20)
        s.add(-1)
        s.add(-1)
        XCTAssertEqual(s.smoothed, 20)
        XCTAssertEqual(s.sampleCount, 1)
    }
}

final class FiredHazardTrackerTests: XCTestCase {
    func testRearmsBeyondDistance() {
        var t = FiredHazardTracker()
        let rider = Fixture.rider()
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 100)
        t.markFired(h, at: Fixture.now)
        XCTAssertEqual(t.firedIDs, [h.id])

        // 900 m past the hazard: still armed off.
        let near = Geo.destination(lat: h.lat, lon: h.lon, bearingDegrees: 90, distanceMeters: 900)
        XCTAssertEqual(t.update(riderLat: near.lat, riderLon: near.lon, rearmDistanceMeters: 1000), [])
        XCTAssertEqual(t.firedIDs, [h.id])

        // 1100 m away: re-armed.
        let far = Geo.destination(lat: h.lat, lon: h.lon, bearingDegrees: 90, distanceMeters: 1100)
        XCTAssertEqual(t.update(riderLat: far.lat, riderLon: far.lon, rearmDistanceMeters: 1000), [h.id])
        XCTAssertTrue(t.isEmpty)
    }
}

final class AlertSchedulerTests: XCTestCase {
    private func pending(_ hazard: Hazard, at time: Date = Fixture.now) -> AlertScheduler.Pending {
        let e = AlertEvent(
            id: UUID(), hazardId: hazard.id, category: hazard.category, triggeredAt: time,
            playbackStartedAt: nil, outputLatencySeconds: nil,
            riderLat: Fixture.baseLat, riderLon: Fixture.baseLon, riderSpeed: 20, riderCourse: 90,
            distanceMeters: 100, timeToHazardSeconds: 5, triggerDistanceMeters: 220,
            queueDepthAtTrigger: 0, dropped: false, dropReason: nil
        )
        return AlertScheduler.Pending(hazard: hazard, event: e)
    }

    func testPlaysOneAtATimeWithGap() {
        var s = AlertScheduler()
        let rider = Fixture.rider()
        let a = Fixture.hazard(from: rider, bearing: 90, distance: 100)
        let b = Fixture.hazard(from: rider, bearing: 90, distance: 150)
        s.enqueue(pending(a))
        s.enqueue(pending(b))

        let t0 = Fixture.now
        let d1 = s.dequeue(now: t0, riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertEqual(d1.play?.hazard.id, a.id)
        XCTAssertEqual(d1.play?.event.queueDepthAtTrigger, 0)
        XCTAssertTrue(d1.dropped.isEmpty)

        // While playing: nothing.
        let d2 = s.dequeue(now: t0.addingTimeInterval(1), riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertNil(d2.play)

        s.playbackFinished(at: t0.addingTimeInterval(1.5))

        // Within the 2 s gap: still nothing.
        let d3 = s.dequeue(now: t0.addingTimeInterval(2.5), riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertNil(d3.play)

        // After the gap: second alert.
        let d4 = s.dequeue(now: t0.addingTimeInterval(3.6), riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertEqual(d4.play?.hazard.id, b.id)
        XCTAssertEqual(d4.play?.event.queueDepthAtTrigger, 1)
    }

    func testOverflowKeepsNearestAndDropsRest() {
        var s = AlertScheduler()
        let rider = Fixture.rider()
        let far = Fixture.hazard(from: rider, bearing: 90, distance: 200)
        let near = Fixture.hazard(from: rider, bearing: 90, distance: 60)
        let mid1 = Fixture.hazard(from: rider, bearing: 90, distance: 120)
        let mid2 = Fixture.hazard(from: rider, bearing: 90, distance: 150)
        for h in [far, mid1, near, mid2] { s.enqueue(pending(h)) }
        XCTAssertEqual(s.queuedCount, 4)

        let d = s.dequeue(now: Fixture.now, riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertEqual(d.play?.hazard.id, near.id)
        XCTAssertEqual(Set(d.dropped.map { $0.hazard.id }), [far.id, mid1.id, mid2.id])
        XCTAssertTrue(d.dropped.allSatisfy { $0.event.dropped && $0.event.dropReason != nil })
        XCTAssertEqual(s.queuedCount, 0)
    }

    func testExactlyThreeQueuedIsNotOverflow() {
        var s = AlertScheduler()
        let rider = Fixture.rider()
        for d in [100.0, 150, 200] { s.enqueue(pending(Fixture.hazard(from: rider, bearing: 90, distance: d))) }
        let d = s.dequeue(now: Fixture.now, riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertNotNil(d.play)
        XCTAssertTrue(d.dropped.isEmpty)
        XCTAssertEqual(s.queuedCount, 2)
    }

    func testPlaybackFailureReleasesQueue() {
        var s = AlertScheduler()
        let rider = Fixture.rider()
        s.enqueue(pending(Fixture.hazard(from: rider, bearing: 90, distance: 100)))
        s.enqueue(pending(Fixture.hazard(from: rider, bearing: 90, distance: 150)))
        _ = s.dequeue(now: Fixture.now, riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        s.playbackFailed(at: Fixture.now)
        let d = s.dequeue(now: Fixture.now.addingTimeInterval(2.1), riderLat: rider.lat, riderLon: rider.lon, gapSeconds: 2, maxQueued: 3)
        XCTAssertNotNil(d.play)
    }
}

final class ReactionOffsetTests: XCTestCase {
    func testWalksBackAlongTrack() {
        // 20 m/s east, one fix per second, tap at t=30 with 2.5 s reaction → position at t=27.5 → 550 m along.
        let track = Fixture.straightTrack(seconds: 31, speed: 20)
        let tap = Fixture.now.addingTimeInterval(30)
        let p = ReactionOffset.position(in: track, tapTime: tap, reactionTimeSeconds: 2.5)
        XCTAssertNotNil(p)
        let along = Geo.distanceMeters(lat1: Fixture.baseLat, lon1: Fixture.baseLon, lat2: p!.lat, lon2: p!.lon)
        XCTAssertEqual(along, 550, accuracy: 0.5)
        XCTAssertEqual(p!.timestamp, tap.addingTimeInterval(-2.5))
        XCTAssertEqual(p!.course, 90, accuracy: 1e-9)
    }

    func testOffsetAtHundredKmhIsAboutSeventyMetres() {
        // The spec's example: 100 km/h ≈ 27.8 m/s, 2.5 s → ~69 m upstream of the tap.
        let speed = 100.0 / 3.6
        let track = Fixture.straightTrack(seconds: 61, speed: speed)
        let tap = Fixture.now.addingTimeInterval(60)
        let raw = track.last!
        let p = ReactionOffset.position(in: track, tapTime: tap, reactionTimeSeconds: 2.5)!
        let upstream = Geo.distanceMeters(lat1: raw.lat, lon1: raw.lon, lat2: p.lat, lon2: p.lon)
        XCTAssertEqual(upstream, speed * 2.5, accuracy: 0.5)
    }

    func testTapBeforeTrackReachesBackReturnsNil() {
        let track = Fixture.straightTrack(seconds: 2)
        XCTAssertNil(ReactionOffset.position(in: track, tapTime: Fixture.now.addingTimeInterval(1), reactionTimeSeconds: 2.5))
    }

    func testEmptyTrackReturnsNil() {
        XCTAssertNil(ReactionOffset.position(in: [], tapTime: Fixture.now, reactionTimeSeconds: 2.5))
    }

    func testZeroReactionTimeReturnsLatestPosition() {
        let track = Fixture.straightTrack(seconds: 10)
        let p = ReactionOffset.position(in: track, tapTime: Fixture.now.addingTimeInterval(9.4), reactionTimeSeconds: 0)!
        XCTAssertEqual(p.lat, track.last!.lat, accuracy: 1e-9)
    }

    func testUsesCourseAtOffsetPointNotAtTap() {
        // Straight east for 10 s, then a hard left to north for 10 s.
        var track = Fixture.straightTrack(seconds: 10, speed: 20, course: 90)
        let corner = track.last!
        for i in 1...10 {
            let d = Geo.destination(lat: corner.lat, lon: corner.lon, bearingDegrees: 0, distanceMeters: 20 * Double(i))
            track.append(TrackPoint(timestamp: corner.timestamp.addingTimeInterval(Double(i)), lat: d.lat, lon: d.lon, speed: 20, course: 0, horizontalAccuracy: 5))
        }
        let tap = track.last!.timestamp
        let p = ReactionOffset.position(in: track, tapTime: tap, reactionTimeSeconds: 12)!
        XCTAssertEqual(p.course, 90, accuracy: 1e-9)
    }
}

final class NearMissTrackerTests: XCTestCase {
    /// Drive an eastbound rider at 20 m/s past `hazard`, feeding real verdicts.
    private func drive(past hazard: Hazard, seconds: Int, fired: Set<UUID> = []) -> (closed: [NearMissEvent], tracker: NearMissTracker) {
        var tracker = NearMissTracker()
        let engine = TriggerEngine()
        var closed: [NearMissEvent] = []
        for i in 0..<seconds {
            let d = Geo.destination(lat: Fixture.baseLat, lon: Fixture.baseLon, bearingDegrees: 90, distanceMeters: 20 * Double(i))
            let r = Fixture.rider(lat: d.lat, lon: d.lon, time: Fixture.now.addingTimeInterval(Double(i)))
            let v = engine.evaluate(rider: r, smoothedSpeed: 20, hazard: hazard, alreadyFired: fired, now: r.timestamp)
            if let e = tracker.observe(hazard: hazard, verdict: v, rider: r, smoothedSpeed: 20, now: r.timestamp) {
                closed.append(e)
            }
        }
        return (closed, tracker)
    }

    func testOppositeDirectionHazardIsOneNearMissWithClosestApproach() {
        // Hazard for westbound riders 300 m ahead of an eastbound rider. It enters trigger
        // range (220 m) silent, is passed, and leaves range behind the rider.
        let h = Fixture.hazard(from: Fixture.rider(), bearing: 90, distance: 300, heading: 270)
        let (closed, tracker) = drive(past: h, seconds: 40)
        XCTAssertEqual(closed.count, 1)
        guard let e = closed.first else { return }
        XCTAssertEqual(e.outcome, .leftRange)
        XCTAssertLessThan(e.closestDistanceMeters, 1)
        XCTAssertTrue(e.rejectedBy.contains(.headingMismatch))
        XCTAssertNotNil(e.exitedAt)
        XCTAssertEqual(tracker.activeCount, 0)
    }

    func testNormalLifecycleIsNotANearMiss() {
        // Same-direction hazard: out of range → fires → already fired behind. Nothing to log.
        let h = Fixture.hazard(from: Fixture.rider(), bearing: 90, distance: 300, heading: 90)
        var tracker = NearMissTracker()
        let engine = TriggerEngine()
        var fired = FiredHazardTracker()
        var closed: [NearMissEvent] = []
        for i in 0..<40 {
            let d = Geo.destination(lat: Fixture.baseLat, lon: Fixture.baseLon, bearingDegrees: 90, distanceMeters: 20 * Double(i))
            let r = Fixture.rider(lat: d.lat, lon: d.lon, time: Fixture.now.addingTimeInterval(Double(i)))
            let v = engine.evaluate(rider: r, smoothedSpeed: 20, hazard: h, alreadyFired: fired.firedIDs, now: r.timestamp)
            if v.fires { fired.markFired(h, at: r.timestamp) }
            if let e = tracker.observe(hazard: h, verdict: v, rider: r, smoothedSpeed: 20, now: r.timestamp) { closed.append(e) }
        }
        XCTAssertTrue(closed.isEmpty, "got \(closed)")
        XCTAssertEqual(tracker.activeCount, 0)
    }

    func testOutOfRangeRejectionIsNotANearMiss() {
        var tracker = NearMissTracker()
        let rider = Fixture.rider()
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 400)
        let far = Verdict.rejected(gates: [.outOfRange, .headingMismatch], distanceMeters: 400, triggerDistanceMeters: 220)
        XCTAssertNil(tracker.observe(hazard: h, verdict: far, rider: rider, smoothedSpeed: 20, now: Fixture.now))
        XCTAssertEqual(tracker.activeCount, 0)
    }

    func testExpiredHazardInRangeIsANearMiss() {
        let h = Fixture.hazard(from: Fixture.rider(), bearing: 90, distance: 300, heading: 90, expiresAt: Fixture.now.addingTimeInterval(-1))
        let (closed, _) = drive(past: h, seconds: 40)
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first?.rejectedBy.first, .expired)
    }

    func testLateFireClosesEncounterAsFired() {
        var tracker = NearMissTracker()
        let rider = Fixture.rider()
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 200)
        let blocked = Verdict.rejected(gates: [.headingMismatch], distanceMeters: 200, triggerDistanceMeters: 220)
        XCTAssertNil(tracker.observe(hazard: h, verdict: blocked, rider: rider, smoothedSpeed: 20, now: Fixture.now))
        XCTAssertEqual(tracker.activeCount, 1)
        let fire = Verdict.fire(distanceMeters: 60, triggerDistanceMeters: 220)
        let e = tracker.observe(hazard: h, verdict: fire, rider: rider, smoothedSpeed: 20, now: Fixture.now.addingTimeInterval(7))
        XCTAssertEqual(e?.outcome, .fired)
        XCTAssertEqual(e?.closestDistanceMeters, 200, "closest silent distance, before it fired")
        XCTAssertEqual(tracker.activeCount, 0)
    }

    func testDrainClosesEverything() {
        var tracker = NearMissTracker()
        let rider = Fixture.rider()
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 100)
        _ = tracker.observe(hazard: h, verdict: .rejected(gates: [.headingMismatch], distanceMeters: 100, triggerDistanceMeters: 220), rider: rider, smoothedSpeed: 20, now: Fixture.now)
        let drained = tracker.drain(at: Fixture.now.addingTimeInterval(5))
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained[0].outcome, .rideEnded)
        XCTAssertEqual(tracker.activeCount, 0)
    }
}
