import XCTest

#if canImport(HazardCore)
@testable import HazardCore
#else
@testable import MotoHazardAlert
#endif

final class SeedFileTests: XCTestCase {
    func testMinimalSeedRecordFillsDefaults() throws {
        let json = """
        { "name": "t", "hazards": [
          { "lat": 47.21, "lon": 11.01, "heading": 120, "category": "gravel" },
          { "lat": 47.22, "lon": 11.02, "heading": null, "category": "accident", "createdAt": "2026-09-17T06:00:00Z" },
          { "lat": 47.23, "lon": 11.03, "heading": 380, "headingTolerance": 30, "category": "cattle", "expiresAt": "2030-01-01T00:00:00.000Z", "note": "farm gate" }
        ] }
        """
        let file = try JSONCoding.decoder.decode(SeedFile.self, from: Data(json.utf8))
        let now = Fixture.now
        let hazards = file.hazards.map { $0.toHazard(loadedAt: now) }

        XCTAssertEqual(hazards[0].createdAt, now)
        XCTAssertEqual(hazards[0].expiresAt, now.addingTimeInterval(14 * 86_400))
        XCTAssertEqual(hazards[0].source, .seeded)
        XCTAssertNil(hazards[0].headingTolerance)
        XCTAssertEqual(hazards[0].resolvedHeadingTolerance(default: 60), 60)

        XCTAssertNil(hazards[1].heading)
        XCTAssertEqual(hazards[1].createdAt, JSONCoding.date(from: "2026-09-17T06:00:00Z"))
        XCTAssertEqual(hazards[1].expiresAt, hazards[1].createdAt.addingTimeInterval(3 * 3600))

        XCTAssertEqual(hazards[2].heading, 20, "380° normalises to 20°")
        XCTAssertEqual(hazards[2].headingTolerance, 30)
        XCTAssertEqual(hazards[2].expiresAt, JSONCoding.date(from: "2030-01-01T00:00:00Z"))
        XCTAssertEqual(hazards[2].note, "farm gate")
    }

    func testUnknownCategoryFailsLoudlyInDecoder() {
        let json = """
        { "hazards": [ { "lat": 47.21, "lon": 11.01, "heading": 120, "category": "police" } ] }
        """
        XCTAssertThrowsError(try JSONCoding.decoder.decode(SeedFile.self, from: Data(json.utf8)))
    }

    func testDateRoundTripKeepsMilliseconds() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.123)
        let s = JSONCoding.string(from: date)
        XCTAssertTrue(s.hasSuffix(".123Z"), s)
        XCTAssertEqual(JSONCoding.date(from: s)!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.0005)
    }
}

final class RideLogAssemblyTests: XCTestCase {
    private func meta() -> RideMeta {
        RideMeta(rideId: UUID(), startedAt: Fixture.now, appVersion: "0.1.0 (1)", settings: .default, hazardSource: "bundle", hazards: [])
    }

    func testSummaryGapsAndDistance() {
        var track = Fixture.straightTrack(seconds: 10, speed: 20)
        // Insert a 7 s hole.
        let last = track.last!
        let d = Geo.destination(lat: last.lat, lon: last.lon, bearingDegrees: 90, distanceMeters: 140)
        track.append(TrackPoint(timestamp: last.timestamp.addingTimeInterval(7), lat: d.lat, lon: d.lon, speed: 20, course: 90, horizontalAccuracy: 5))

        let log = RideLogAssembler.assemble(meta: meta(), track: track, events: [], endedAt: track.last!.timestamp, recovered: false)
        XCTAssertEqual(log.summary.fixCount, 11)
        XCTAssertEqual(log.summary.maxGapSeconds, 7, accuracy: 1e-9)
        XCTAssertEqual(log.summary.gapsOver5s, 1)
        XCTAssertEqual(log.summary.distanceMeters, 9 * 20 + 140, accuracy: 0.5)
        XCTAssertEqual(log.summary.maxSpeedMetersPerSecond, 20)
        XCTAssertEqual(log.summary.durationSeconds, 16, accuracy: 1e-9)
    }

    func testEventsAreSplitAndReportsDeduped() {
        let m = meta()
        let hazardId = UUID()
        var alert = AlertEvent(
            id: UUID(), hazardId: hazardId, category: .gravel, triggeredAt: Fixture.now.addingTimeInterval(5),
            playbackStartedAt: Fixture.now.addingTimeInterval(5.25), outputLatencySeconds: 0.2,
            riderLat: 47, riderLon: 11, riderSpeed: 20, riderCourse: 90,
            distanceMeters: 200, timeToHazardSeconds: 10, triggerDistanceMeters: 220,
            queueDepthAtTrigger: 0, dropped: false, dropReason: nil
        )
        var dropped = alert
        dropped.id = UUID()
        dropped.dropped = true
        dropped.timeToHazardSeconds = 99
        alert.timeToHazardSeconds = 10

        let reportId = UUID()
        let pending = Report(id: reportId, rideId: m.rideId, tappedAt: Fixture.now.addingTimeInterval(8), raw: nil, offset: nil,
                             reactionTimeSeconds: 2.5, category: .other, status: .pending, categorisedAt: nil, hazardId: nil)
        var categorised = pending
        categorised.category = .cattle
        categorised.status = .categorised

        let events: [RideEventRecord] = [
            .alert(alert), .alert(dropped), .report(pending),
            .diagnostic(DiagnosticEntry(timestamp: Fixture.now, level: .error, message: "boom")),
            .report(categorised),
        ]
        let log = RideLogAssembler.assemble(meta: m, track: [], events: events, endedAt: Fixture.now.addingTimeInterval(10), recovered: true)

        XCTAssertEqual(log.alerts.count, 2)
        XCTAssertEqual(log.summary.alertsFired, 1)
        XCTAssertEqual(log.summary.alertsDropped, 1)
        XCTAssertEqual(log.summary.meanTimeToHazardSeconds, 10, "dropped alerts do not count towards timing")
        XCTAssertEqual(log.summary.meanPlaybackLatencySeconds!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(log.reports.count, 1)
        XCTAssertEqual(log.reports[0].category, .cattle)
        XCTAssertEqual(log.summary.errors, 1)
        XCTAssertTrue(log.recovered)
    }

    func testEventRecordRoundTrip() throws {
        let entry = RideEventRecord.diagnostic(DiagnosticEntry(timestamp: Fixture.now, level: .warning, message: "x"))
        let data = try JSONCoding.lineEncoder.encode(entry)
        let back = try JSONCoding.decoder.decode(RideEventRecord.self, from: data)
        XCTAssertEqual(back, entry)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\n"), "line encoder must be single-line")
    }

    func testDecodeLinesSkipsTornTail() {
        let good = try! JSONCoding.lineEncoder.encode(Fixture.rider())
        var data = Data()
        data.append(good); data.append(UInt8(ascii: "\n"))
        data.append(good); data.append(UInt8(ascii: "\n"))
        data.append(Data("{\"timestamp\":\"2026-".utf8))
        let r = RideLogAssembler.decodeLines(TrackPoint.self, from: data)
        XCTAssertEqual(r.values.count, 2)
        XCTAssertEqual(r.skipped, 1)
    }

    func testRideLogJSONRoundTrip() throws {
        let m = meta()
        let track = Fixture.straightTrack(seconds: 3)
        let log = RideLogAssembler.assemble(meta: m, track: track, events: [], endedAt: Fixture.now.addingTimeInterval(3), recovered: false)
        let data = try JSONCoding.prettyEncoder.encode(log)
        let back = try JSONCoding.decoder.decode(RideLog.self, from: data)
        XCTAssertEqual(back, log)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"leadTimeSeconds\" : 11"), "settings must be in the log")
    }
}

final class GPXWriterTests: XCTestCase {
    func testGPXContainsTrackAndWaypoints() {
        let rider = Fixture.rider()
        let h = Fixture.hazard(from: rider, bearing: 90, distance: 100, note: "after <bridge> & gate")
        let m = RideMeta(rideId: UUID(), startedAt: Fixture.now, appVersion: "0.1.0", settings: .default, hazardSource: "bundle", hazards: [h])
        let alert = AlertEvent(
            id: UUID(), hazardId: h.id, category: .gravel, triggeredAt: Fixture.now.addingTimeInterval(1),
            playbackStartedAt: Fixture.now.addingTimeInterval(1.1), outputLatencySeconds: nil,
            riderLat: rider.lat, riderLon: rider.lon, riderSpeed: 20, riderCourse: 90,
            distanceMeters: 100, timeToHazardSeconds: 5, triggerDistanceMeters: 220, queueDepthAtTrigger: 0, dropped: false, dropReason: nil
        )
        let report = Report(id: UUID(), rideId: m.rideId, tappedAt: Fixture.now.addingTimeInterval(2),
                            raw: Position(rider), offset: Position(rider), reactionTimeSeconds: 2.5,
                            category: .cattle, status: .categorised, categorisedAt: nil, hazardId: nil)
        let log = RideLogAssembler.assemble(meta: m, track: Fixture.straightTrack(seconds: 3), events: [.alert(alert), .report(report)], endedAt: Fixture.now.addingTimeInterval(3), recovered: false)

        let gpx = GPXWriter.gpx(for: log)
        XCTAssertTrue(gpx.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\""))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt ").count - 1, 3)
        XCTAssertEqual(gpx.components(separatedBy: "<wpt ").count - 1, 4, "hazard + alert + raw tap + offset report")
        XCTAssertTrue(gpx.contains("HAZARD gravel"))
        XCTAssertTrue(gpx.contains("ALERT gravel"))
        XCTAssertTrue(gpx.contains("REPORT cattle"))
        XCTAssertTrue(gpx.contains("after &lt;bridge&gt; &amp; gate"))
        XCTAssertFalse(gpx.contains("<bridge>"))
        XCTAssertTrue(gpx.hasSuffix("</gpx>\n"))
    }
}

private extension Fixture {
    static func hazard(from rider: TrackPoint, bearing: Double, distance: Double, note: String) -> Hazard {
        var h = hazard(from: rider, bearing: bearing, distance: distance)
        h.note = note
        return h
    }
}
