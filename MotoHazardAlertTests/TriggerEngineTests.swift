import XCTest

#if canImport(HazardCore)
@testable import HazardCore
#else
@testable import MotoHazardAlert
#endif

/// Synthetic tests for all five gates plus the stationary case.
///
/// Default rider: heading east (90°) at 20 m/s (72 km/h). With the default
/// settings the trigger distance is max(20 × 11, 80) = 220 m.
final class TriggerEngineTests: XCTestCase {
    let engine = TriggerEngine(settings: .default)
    let rider = Fixture.rider()

    private func verdict(_ hazard: Hazard, rider: TrackPoint? = nil, fired: Set<UUID> = [], now: Date = Fixture.now) -> Verdict {
        let r = rider ?? self.rider
        return engine.evaluate(rider: r, smoothedSpeed: r.speed, hazard: hazard, alreadyFired: fired, now: now)
    }

    // MARK: Trigger distance

    func testTriggerDistanceScalesWithSpeedAboveFloor() {
        XCTAssertEqual(engine.triggerDistance(smoothedSpeed: 20), 220, accuracy: 1e-9)
        XCTAssertEqual(engine.triggerDistance(smoothedSpeed: 36.1), 36.1 * 11, accuracy: 1e-9) // 130 km/h ≈ 397 m
    }

    func testTriggerDistanceFloorAtLowSpeed() {
        XCTAssertEqual(engine.triggerDistance(smoothedSpeed: 2), 80)
        XCTAssertEqual(engine.triggerDistance(smoothedSpeed: 0), 80)
        XCTAssertEqual(engine.triggerDistance(smoothedSpeed: -1), 80, "invalid speed must not produce a negative distance")
    }

    // MARK: Happy path

    func testFiresForHazardAheadInRangeWithMatchingHeading() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: 90)
        let v = verdict(h)
        XCTAssertTrue(v.fires)
        XCTAssertEqual(v.distanceMeters, 150, accuracy: 0.05)
        XCTAssertEqual(v.triggerDistanceMeters, 220, accuracy: 1e-9)
    }

    func testFiresJustInsideTriggerDistance() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 219)
        XCTAssertTrue(verdict(h).fires)
    }

    // MARK: Gate 1 — expiry

    func testRejectsExpiredHazard() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150, expiresAt: Fixture.now.addingTimeInterval(-1))
        let v = verdict(h)
        XCTAssertFalse(v.fires)
        XCTAssertEqual(v.rejectedGates, [.expired])
    }

    func testExpiryIsInclusiveAtTheBoundary() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150, expiresAt: Fixture.now)
        XCTAssertEqual(verdict(h).rejectedGates, [.expired], "now == expiresAt counts as expired: no 'possibly stale' alerts")
    }

    func testAccidentExpiresAfterThreeHoursByDefault() {
        let created = Fixture.now
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150, category: .accident, createdAt: created)
        XCTAssertEqual(h.expiresAt, created.addingTimeInterval(3 * 3600))
        XCTAssertTrue(verdict(h, now: created.addingTimeInterval(3 * 3600 - 1)).fires)
        XCTAssertEqual(verdict(h, now: created.addingTimeInterval(3 * 3600)).rejectedGates, [.expired])
    }

    // MARK: Gate 2 — already fired

    func testRejectsAlreadyFiredHazard() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150)
        let v = verdict(h, fired: [h.id])
        XCTAssertEqual(v.rejectedGates, [.alreadyFired])
    }

    // MARK: Gate 3 — range

    func testRejectsHazardBeyondTriggerDistance() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 221)
        XCTAssertEqual(verdict(h).rejectedGates, [.outOfRange])
    }

    func testRangeGrowsWithSpeed() {
        let fast = Fixture.rider(speed: 36) // ~130 km/h → 396 m
        let h = Fixture.hazard(from: fast, bearing: 90, distance: 350)
        XCTAssertTrue(verdict(h, rider: fast).fires)
        XCTAssertEqual(verdict(h).rejectedGates, [.outOfRange], "same hazard is out of range at 72 km/h")
    }

    func testFloorAppliesAtWalkingPace() {
        let slow = Fixture.rider(speed: 1.5)
        let near = Fixture.hazard(from: slow, bearing: 90, distance: 70)
        let far = Fixture.hazard(from: slow, bearing: 90, distance: 90)
        XCTAssertTrue(verdict(near, rider: slow).fires)
        XCTAssertEqual(verdict(far, rider: slow).rejectedGates, [.outOfRange])
    }

    // MARK: Gate 4 — ahead, not behind

    func testRejectsHazardBehindRider() {
        let behind = Fixture.hazard(from: rider, bearing: 270, distance: 100, heading: 90)
        XCTAssertEqual(verdict(behind).rejectedGates, [.notAhead])
    }

    func testRejectsHazardAbeam() {
        let left = Fixture.hazard(from: rider, bearing: 0, distance: 100, heading: 90)
        let right = Fixture.hazard(from: rider, bearing: 180, distance: 100, heading: 90)
        XCTAssertEqual(verdict(left).rejectedGates, [.notAhead])
        XCTAssertEqual(verdict(right).rejectedGates, [.notAhead])
    }

    func testAheadConeBoundary() {
        let inside = Fixture.hazard(from: rider, bearing: 90 + 44, distance: 100, heading: 90)
        let outside = Fixture.hazard(from: rider, bearing: 90 + 46, distance: 100, heading: 90)
        XCTAssertTrue(verdict(inside).fires)
        XCTAssertEqual(verdict(outside).rejectedGates, [.notAhead])
    }

    func testJustPassedHazardIsSilent() {
        // Rider has gone 30 m past the hazard: bearing to it is now ~270.
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 100, heading: 90)
        let moved = Geo.destination(lat: rider.lat, lon: rider.lon, bearingDegrees: 90, distanceMeters: 130)
        let passed = Fixture.rider(lat: moved.lat, lon: moved.lon)
        XCTAssertEqual(verdict(h, rider: passed).rejectedGates, [.notAhead])
    }

    // MARK: Gate 5 — heading

    func testRejectsHazardForOppositeDirectionOfTravel() {
        // Hazard applies to westbound riders; we are eastbound. It is ahead and in range.
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: 270)
        XCTAssertEqual(verdict(h).rejectedGates, [.headingMismatch])
    }

    func testHeadingToleranceBoundaryUsesDefaultFromSettings() {
        let inside = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: 90 + 59)
        let outside = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: 90 + 61)
        XCTAssertTrue(verdict(inside).fires)
        XCTAssertEqual(verdict(outside).rejectedGates, [.headingMismatch])
    }

    func testPerHazardToleranceOverridesDefault() {
        let tight = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: 90 + 30, tolerance: 20)
        XCTAssertEqual(verdict(tight).rejectedGates, [.headingMismatch])
        let wide = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: 90 + 100, tolerance: 120)
        XCTAssertTrue(verdict(wide).fires)
    }

    func testOmnidirectionalHazardSkipsHeadingGate() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150, heading: nil)
        XCTAssertTrue(verdict(h).fires)
        // ...but is still subject to the ahead gate.
        let behind = Fixture.hazard(from: rider, bearing: 270, distance: 100, heading: nil)
        XCTAssertEqual(verdict(behind).rejectedGates, [.notAhead])
    }

    func testHeadingWrapsAroundNorth() {
        let north = Fixture.rider(course: 5)
        let h = Fixture.hazard(from: north, bearing: 5, distance: 150, heading: 355)
        XCTAssertTrue(verdict(h, rider: north).fires)
    }

    // MARK: No course

    func testStationaryRiderWithoutCourseIsSilent() {
        let stopped = Fixture.rider(speed: 0, course: -1)
        let h = Fixture.hazard(from: stopped, bearing: 90, distance: 50, heading: nil)
        let v = verdict(h, rider: stopped)
        XCTAssertFalse(v.fires)
        XCTAssertEqual(v.rejectedGates, [.noCourse])
    }

    // MARK: All gates reported

    func testAllFailingGatesAreReported() {
        let h = Fixture.hazard(from: rider, bearing: 270, distance: 500, heading: 270, expiresAt: Fixture.now.addingTimeInterval(-10))
        let v = verdict(h, fired: [h.id])
        XCTAssertEqual(v.rejectedGates, [.expired, .alreadyFired, .outOfRange, .notAhead, .headingMismatch])
    }

    // MARK: Spec signature

    func testShouldAlertWrapper() {
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 150)
        XCTAssertTrue(engine.shouldAlert(rider: rider, hazard: h, alreadyFired: [], now: Fixture.now))
        XCTAssertFalse(engine.shouldAlert(rider: rider, hazard: h, alreadyFired: [h.id], now: Fixture.now))
    }

    // MARK: Settings

    func testLeadTimeChangeMovesTriggerPoint() {
        var s = TunableSettings.default
        s.leadTimeSeconds = 8
        let short = TriggerEngine(settings: s)
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 200)
        XCTAssertTrue(verdict(h).fires, "220 m at 11 s")
        let v = short.evaluate(rider: rider, smoothedSpeed: 20, hazard: h, alreadyFired: [], now: Fixture.now)
        XCTAssertEqual(v.rejectedGates, [.outOfRange], "160 m at 8 s")
    }
}
