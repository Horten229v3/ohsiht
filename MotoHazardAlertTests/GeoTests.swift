import XCTest

#if canImport(HazardCore)
@testable import HazardCore
#else
@testable import MotoHazardAlert
#endif

final class GeoTests: XCTestCase {
    func testDistanceOfKnownPair() {
        // Innsbruck Goldenes Dachl → Bergisel ski jump ≈ 2.8 km
        let d = Geo.distanceMeters(lat1: 47.2685, lon1: 11.3933, lat2: 47.2477, lon2: 11.3993)
        XCTAssertEqual(d, 2_360, accuracy: 60)
    }

    func testDistanceZeroForSamePoint() {
        XCTAssertEqual(Geo.distanceMeters(lat1: 47.21, lon1: 11.01, lat2: 47.21, lon2: 11.01), 0, accuracy: 0.001)
    }

    func testDestinationRoundTrip() {
        for bearing in stride(from: 0.0, to: 360, by: 37) {
            for distance in [10.0, 80, 350, 1200] {
                let d = Geo.destination(lat: 47.21, lon: 11.01, bearingDegrees: bearing, distanceMeters: distance)
                let back = Geo.distanceMeters(lat1: 47.21, lon1: 11.01, lat2: d.lat, lon2: d.lon)
                XCTAssertEqual(back, distance, accuracy: 0.01, "bearing \(bearing) distance \(distance)")
                let b = Geo.bearingDegrees(lat1: 47.21, lon1: 11.01, lat2: d.lat, lon2: d.lon)
                XCTAssertEqual(Geo.angularDifference(b, bearing), 0, accuracy: 0.01, "bearing \(bearing)")
            }
        }
    }

    func testAngularDifferenceWrapsAroundNorth() {
        XCTAssertEqual(Geo.angularDifference(350, 10), 20, accuracy: 1e-9)
        XCTAssertEqual(Geo.angularDifference(10, 350), 20, accuracy: 1e-9)
        XCTAssertEqual(Geo.angularDifference(0, 180), 180, accuracy: 1e-9)
        XCTAssertEqual(Geo.angularDifference(90, 90), 0, accuracy: 1e-9)
        XCTAssertEqual(Geo.angularDifference(-10, 10), 20, accuracy: 1e-9)
        XCTAssertEqual(Geo.angularDifference(720, 0), 0, accuracy: 1e-9)
    }

    func testInterpolationMidpoint() {
        let a = TrackPoint(timestamp: Fixture.now, lat: 47.0, lon: 11.0, speed: 10, course: 350, horizontalAccuracy: 5)
        let b = TrackPoint(timestamp: Fixture.now.addingTimeInterval(2), lat: 47.0002, lon: 11.0002, speed: 20, course: 10, horizontalAccuracy: 5)
        let p = Geo.interpolate(a, b, at: Fixture.now.addingTimeInterval(1))
        XCTAssertEqual(p.lat, 47.0001, accuracy: 1e-9)
        XCTAssertEqual(p.lon, 11.0001, accuracy: 1e-9)
        XCTAssertEqual(p.speed, 15, accuracy: 1e-9)
        XCTAssertEqual(p.course, 0, accuracy: 1e-9, "course must interpolate through north, not via 180")
    }

    func testInterpolationHandlesInvalidCourse() {
        let a = TrackPoint(timestamp: Fixture.now, lat: 47.0, lon: 11.0, speed: -1, course: -1, horizontalAccuracy: 5)
        let b = TrackPoint(timestamp: Fixture.now.addingTimeInterval(2), lat: 47.0002, lon: 11.0002, speed: 20, course: 45, horizontalAccuracy: 5)
        let p = Geo.interpolate(a, b, at: Fixture.now.addingTimeInterval(1))
        XCTAssertEqual(p.course, 45)
        XCTAssertEqual(p.speed, 20)
    }
}
