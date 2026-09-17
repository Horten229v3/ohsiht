import Foundation

/// One entry per finished ride, written next to the ride JSON so listing rides
/// does not require parsing every track.
struct RideIndexEntry: Codable, Identifiable, Equatable {
    var rideId: UUID
    var folderName: String
    var startedAt: Date
    var endedAt: Date
    var recovered: Bool
    var summary: RideSummary
    var jsonFileName: String
    var gpxFileName: String

    var id: UUID { rideId }
}

/// Files for one ride while it is running. Append-only: a crash loses at most
/// the line being written.
final class RideWriter {
    let folder: URL
    private let trackHandle: FileHandle
    private let eventsHandle: FileHandle

    init(folder: URL) throws {
        self.folder = folder
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let trackURL = folder.appendingPathComponent(RideStore.trackFile)
        let eventsURL = folder.appendingPathComponent(RideStore.eventsFile)
        if !fm.fileExists(atPath: trackURL.path) { fm.createFile(atPath: trackURL.path, contents: nil) }
        if !fm.fileExists(atPath: eventsURL.path) { fm.createFile(atPath: eventsURL.path, contents: nil) }
        trackHandle = try FileHandle(forWritingTo: trackURL)
        eventsHandle = try FileHandle(forWritingTo: eventsURL)
        _ = try trackHandle.seekToEnd()
        _ = try eventsHandle.seekToEnd()
    }

    func append(_ point: TrackPoint) {
        write(point, to: trackHandle)
    }

    func append(_ event: RideEventRecord) {
        write(event, to: eventsHandle)
    }

    func close() {
        try? trackHandle.synchronize()
        try? eventsHandle.synchronize()
        try? trackHandle.close()
        try? eventsHandle.close()
    }

    private func write<T: Encodable>(_ value: T, to handle: FileHandle) {
        do {
            var data = try JSONCoding.lineEncoder.encode(value)
            data.append(UInt8(ascii: "\n"))
            try handle.write(contentsOf: data)
        } catch {
            DiagnosticsLog.shared.error("Failed to append to ride file: \(error.localizedDescription)")
        }
    }
}

/// Ride folders under Documents/rides. Layout per ride:
///
///     rides/20260917-064400_1a2b3c4d/
///         meta.json      written at start
///         track.jsonl    appended per fix        (deleted after finalisation)
///         events.jsonl   appended per event      (deleted after finalisation)
///         hazardpoc_ride_20260917-064400.json    the deliverable
///         hazardpoc_ride_20260917-064400.gpx
///         index.json     summary for the ride list
enum RideStore {
    static let metaFile = "meta.json"
    static let trackFile = "track.jsonl"
    static let eventsFile = "events.jsonl"
    static let indexFile = "index.json"

    // MARK: Starting

    static func begin(meta: RideMeta) throws -> RideWriter {
        AppPaths.ensureDirectories()
        let folder = AppPaths.ridesDirectory.appendingPathComponent(folderName(for: meta), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metaData = try JSONCoding.prettyEncoder.encode(meta)
        try metaData.write(to: folder.appendingPathComponent(metaFile), options: .atomic)
        return try RideWriter(folder: folder)
    }

    // MARK: Finishing

    @discardableResult
    static func finalize(
        folder: URL,
        meta: RideMeta,
        track: [TrackPoint],
        events: [RideEventRecord],
        endedAt: Date,
        recovered: Bool
    ) throws -> (log: RideLog, entry: RideIndexEntry) {
        let log = RideLogAssembler.assemble(meta: meta, track: track, events: events, endedAt: endedAt, recovered: recovered)
        let entry = try write(log: log, in: folder)
        let fm = FileManager.default
        try? fm.removeItem(at: folder.appendingPathComponent(trackFile))
        try? fm.removeItem(at: folder.appendingPathComponent(eventsFile))
        return (log, entry)
    }

    /// Writes (or rewrites) the JSON, GPX and index entry for a ride.
    @discardableResult
    static func write(log: RideLog, in folder: URL) throws -> RideIndexEntry {
        let base = baseFileName(startedAt: log.startedAt)
        let jsonName = "\(base).json"
        let gpxName = "\(base).gpx"

        let data = try JSONCoding.prettyEncoder.encode(log)
        try data.write(to: folder.appendingPathComponent(jsonName), options: .atomic)
        try Data(GPXWriter.gpx(for: log).utf8).write(to: folder.appendingPathComponent(gpxName), options: .atomic)

        let entry = RideIndexEntry(
            rideId: log.rideId,
            folderName: folder.lastPathComponent,
            startedAt: log.startedAt,
            endedAt: log.endedAt,
            recovered: log.recovered,
            summary: log.summary,
            jsonFileName: jsonName,
            gpxFileName: gpxName
        )
        try JSONCoding.prettyEncoder.encode(entry).write(to: folder.appendingPathComponent(indexFile), options: .atomic)
        return entry
    }

    // MARK: Reading

    static func listRides() -> [RideIndexEntry] {
        AppPaths.ensureDirectories()
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: AppPaths.ridesDirectory, includingPropertiesForKeys: nil) else { return [] }
        var entries: [RideIndexEntry] = []
        for folder in folders {
            let indexURL = folder.appendingPathComponent(indexFile)
            guard let data = try? Data(contentsOf: indexURL),
                  let entry = try? JSONCoding.decoder.decode(RideIndexEntry.self, from: data) else { continue }
            entries.append(entry)
        }
        return entries.sorted { $0.startedAt > $1.startedAt }
    }

    static func folder(for entry: RideIndexEntry) -> URL {
        AppPaths.ridesDirectory.appendingPathComponent(entry.folderName, isDirectory: true)
    }

    static func jsonURL(for entry: RideIndexEntry) -> URL {
        folder(for: entry).appendingPathComponent(entry.jsonFileName)
    }

    static func gpxURL(for entry: RideIndexEntry) -> URL {
        folder(for: entry).appendingPathComponent(entry.gpxFileName)
    }

    static func loadLog(for entry: RideIndexEntry) throws -> RideLog {
        let data = try Data(contentsOf: jsonURL(for: entry))
        return try JSONCoding.decoder.decode(RideLog.self, from: data)
    }

    static func entry(for rideId: UUID) -> RideIndexEntry? {
        listRides().first { $0.rideId == rideId }
    }

    /// Replaces a report inside a finished ride's JSON (post-ride categorisation) and
    /// regenerates the GPX so waypoint labels match.
    static func updateReport(_ report: Report) {
        guard let entry = entry(for: report.rideId) else {
            DiagnosticsLog.shared.warning("Cannot update report \(report.id): ride \(report.rideId) not found")
            return
        }
        do {
            var log = try loadLog(for: entry)
            if let i = log.reports.firstIndex(where: { $0.id == report.id }) {
                log.reports[i] = report
            } else {
                log.reports.append(report)
            }
            log.summary = RideSummary.compute(
                track: log.track, alerts: log.alerts, nearMisses: log.nearMisses,
                reports: log.reports, diagnostics: log.diagnostics,
                startedAt: log.startedAt, endedAt: log.endedAt
            )
            try write(log: log, in: folder(for: entry))
        } catch {
            DiagnosticsLog.shared.error("Failed to update report in ride log: \(error.localizedDescription)")
        }
    }

    static func deleteRide(_ entry: RideIndexEntry) {
        try? FileManager.default.removeItem(at: folder(for: entry))
    }

    // MARK: Crash recovery

    /// Any ride folder with a meta.json but no index.json was not stopped cleanly.
    /// Reassemble it from the append-only files so nothing is lost.
    @discardableResult
    static func recoverOrphans() -> [RideIndexEntry] {
        AppPaths.ensureDirectories()
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: AppPaths.ridesDirectory, includingPropertiesForKeys: nil) else { return [] }
        var recovered: [RideIndexEntry] = []
        for folder in folders {
            let metaURL = folder.appendingPathComponent(metaFile)
            guard fm.fileExists(atPath: metaURL.path),
                  !fm.fileExists(atPath: folder.appendingPathComponent(indexFile).path) else { continue }
            do {
                let meta = try JSONCoding.decoder.decode(RideMeta.self, from: Data(contentsOf: metaURL))
                let trackData = (try? Data(contentsOf: folder.appendingPathComponent(trackFile))) ?? Data()
                let eventData = (try? Data(contentsOf: folder.appendingPathComponent(eventsFile))) ?? Data()
                let track = RideLogAssembler.decodeLines(TrackPoint.self, from: trackData)
                var events = RideLogAssembler.decodeLines(RideEventRecord.self, from: eventData).values
                let endedAt = track.values.last?.timestamp ?? meta.startedAt
                events.append(.diagnostic(DiagnosticEntry(
                    timestamp: Date(),
                    level: .warning,
                    message: "Ride was not stopped cleanly (app terminated). Reassembled on next launch; \(track.skipped) torn track line(s) skipped."
                )))
                let result = try finalize(folder: folder, meta: meta, track: track.values, events: events, endedAt: endedAt, recovered: true)
                recovered.append(result.entry)
                DiagnosticsLog.shared.warning("Recovered orphaned ride \(meta.rideId) with \(track.values.count) fixes")
            } catch {
                DiagnosticsLog.shared.error("Failed to recover ride in \(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return recovered
    }

    // MARK: Naming

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    static func folderName(for meta: RideMeta) -> String {
        "\(stampFormatter.string(from: meta.startedAt))_\(meta.rideId.uuidString.prefix(8).lowercased())"
    }

    static func baseFileName(startedAt: Date) -> String {
        "hazardpoc_ride_\(stampFormatter.string(from: startedAt))"
    }
}
