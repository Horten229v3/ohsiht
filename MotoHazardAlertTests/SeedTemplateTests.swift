import XCTest

#if canImport(HazardCore)
@testable import HazardCore
#else
@testable import MotoHazardAlert
#endif

/// Validates the bundled template so a broken seed never ships silently.
final class SeedTemplateTests: XCTestCase {
    /// In Xcode the host app bundle has the file (works on a real device too);
    /// under SwiftPM there is no app bundle, so fall back to the source tree.
    private var templateURL: URL {
        if let bundled = Bundle.main.url(forResource: "seed_hazards", withExtension: "json") {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MotoHazardAlert/Resources/seed_hazards.json")
    }

    func testTemplateDecodesAndIsPlausible() throws {
        let data = try Data(contentsOf: templateURL)
        let file = try JSONCoding.decoder.decode(SeedFile.self, from: data)
        let hazards = file.hazards.map { $0.toHazard(loadedAt: Fixture.now) }

        XCTAssertTrue((15...20).contains(hazards.count), "spec asks for 15–20 hazards, got \(hazards.count)")

        // All on the Kühtai west ramp.
        for h in hazards {
            XCTAssertTrue((47.20...47.24).contains(h.lat), "lat \(h.lat) off the template road")
            XCTAssertTrue((10.94...11.02).contains(h.lon), "lon \(h.lon) off the template road")
            if let heading = h.heading {
                XCTAssertTrue((0..<360).contains(heading))
            }
            XCTAssertEqual(h.source, .seeded)
            XCTAssertFalse(h.isExpired(at: Fixture.now))
        }

        let withHeading = hazards.filter { $0.heading != nil }.count
        XCTAssertGreaterThanOrEqual(withHeading, hazards.count - 2, "direction filtering is under test: most hazards must carry a heading")
        XCTAssertTrue(hazards.contains { $0.heading == nil }, "keep one omnidirectional example")
        XCTAssertTrue(hazards.contains { $0.headingTolerance != nil }, "keep one explicit tolerance example")

        // Consecutive hazards should be spaced for one alert at a time at ~70 km/h.
        for (a, b) in zip(hazards, hazards.dropFirst()) {
            let d = Geo.distanceMeters(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
            XCTAssertGreaterThan(d, 150, "hazards \(a.note ?? "") and \(b.note ?? "") are only \(Int(d)) m apart")
        }

        let text = String(decoding: data, as: UTF8.self).lowercased()
        for banned in ["police", "polizei", "radar", "speed camera", "blitzer"] {
            XCTAssertFalse(text.contains(banned), "excluded category in seed: \(banned)")
        }
    }
}
