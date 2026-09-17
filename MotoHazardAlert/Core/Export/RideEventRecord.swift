import Foundation

/// One line in a ride's `events.jsonl`. Everything except track points goes
/// through here so a ride can be reassembled after a crash from two append-only
/// files and the meta written at start.
enum RideEventRecord: Codable, Equatable {
    case alert(AlertEvent)
    case nearMiss(NearMissEvent)
    case report(Report)
    case diagnostic(DiagnosticEntry)

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum Kind: String, Codable {
        case alert
        case nearMiss
        case report
        case diagnostic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .alert: self = .alert(try c.decode(AlertEvent.self, forKey: .data))
        case .nearMiss: self = .nearMiss(try c.decode(NearMissEvent.self, forKey: .data))
        case .report: self = .report(try c.decode(Report.self, forKey: .data))
        case .diagnostic: self = .diagnostic(try c.decode(DiagnosticEntry.self, forKey: .data))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .alert(v):
            try c.encode(Kind.alert, forKey: .type)
            try c.encode(v, forKey: .data)
        case let .nearMiss(v):
            try c.encode(Kind.nearMiss, forKey: .type)
            try c.encode(v, forKey: .data)
        case let .report(v):
            try c.encode(Kind.report, forKey: .type)
            try c.encode(v, forKey: .data)
        case let .diagnostic(v):
            try c.encode(Kind.diagnostic, forKey: .type)
            try c.encode(v, forKey: .data)
        }
    }
}

/// Builds the final single-file ride log from the parts written during a ride.
enum RideLogAssembler {
    static func assemble(
        meta: RideMeta,
        track: [TrackPoint],
        events: [RideEventRecord],
        endedAt: Date,
        recovered: Bool
    ) -> RideLog {
        var alerts: [AlertEvent] = []
        var nearMisses: [NearMissEvent] = []
        var reports: [Report] = []
        var diagnostics: [DiagnosticEntry] = []

        for e in events {
            switch e {
            case let .alert(v): alerts.append(v)
            case let .nearMiss(v): nearMisses.append(v)
            case let .report(v): reports.append(v)
            case let .diagnostic(v): diagnostics.append(v)
            }
        }

        // A report may be written twice (pending, then categorised); keep the last.
        var reportsById: [UUID: Report] = [:]
        var reportOrder: [UUID] = []
        for r in reports {
            if reportsById[r.id] == nil { reportOrder.append(r.id) }
            reportsById[r.id] = r
        }
        let dedupedReports = reportOrder.compactMap { reportsById[$0] }

        let sortedTrack = track.sorted { $0.timestamp < $1.timestamp }
        let summary = RideSummary.compute(
            track: sortedTrack,
            alerts: alerts,
            nearMisses: nearMisses,
            reports: dedupedReports,
            diagnostics: diagnostics,
            startedAt: meta.startedAt,
            endedAt: endedAt
        )

        return RideLog(
            rideId: meta.rideId,
            appVersion: meta.appVersion,
            startedAt: meta.startedAt,
            endedAt: endedAt,
            recovered: recovered,
            settings: meta.settings,
            hazardSource: meta.hazardSource,
            hazards: meta.hazards,
            track: sortedTrack,
            alerts: alerts.sorted { $0.triggeredAt < $1.triggeredAt },
            nearMisses: nearMisses.sorted { $0.enteredAt < $1.enteredAt },
            reports: dedupedReports,
            diagnostics: diagnostics,
            summary: summary
        )
    }

    /// Parses newline-delimited JSON leniently: a torn final line (crash mid-write)
    /// is skipped, not fatal.
    static func decodeLines<T: Decodable>(_ type: T.Type, from data: Data) -> (values: [T], skipped: Int) {
        var values: [T] = []
        var skipped = 0
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if line.isEmpty { continue }
            if let v = try? JSONCoding.decoder.decode(type, from: Data(line)) {
                values.append(v)
            } else {
                skipped += 1
            }
        }
        return (values, skipped)
    }
}
