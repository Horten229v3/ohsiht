import Foundation

struct HazardLoadResult {
    var hazards: [Hazard]
    /// Which file the seeded hazards came from, for the Home screen and the ride log.
    var sourceDescription: String
    var seededCount: Int
    var reportedCount: Int
    var testCount: Int
    var expiredDropped: Int
    var problems: [String]

    static let empty = HazardLoadResult(hazards: [], sourceDescription: "none", seededCount: 0, reportedCount: 0, testCount: 0, expiredDropped: 0, problems: [])
}

/// Loads the hazard set for a ride. Order of preference for seeded hazards:
/// `Documents/seed_hazards.json` (owner-supplied) → bundled `seed_hazards.json`.
/// A corrupt Documents file is logged and the bundle is used instead; the Home
/// screen shows which one won so a silent fallback cannot go unnoticed.
enum HazardStore {
    static func load(now: Date = Date()) -> HazardLoadResult {
        var result = HazardLoadResult.empty
        var seeded: [Hazard] = []

        let fm = FileManager.default
        if fm.fileExists(atPath: AppPaths.seedHazards.path) {
            switch loadSeedFile(at: AppPaths.seedHazards, now: now) {
            case .success(let hazards):
                seeded = hazards
                result.sourceDescription = "Documents/seed_hazards.json"
            case .failure(let error):
                let msg = "Documents/seed_hazards.json is unreadable, using bundled template instead: \(error)"
                DiagnosticsLog.shared.error(msg)
                result.problems.append(msg)
                seeded = loadBundledSeed(now: now, problems: &result.problems)
                result.sourceDescription = "bundled template (Documents file broken)"
            }
        } else {
            seeded = loadBundledSeed(now: now, problems: &result.problems)
            result.sourceDescription = "bundled template"
        }

        var reported: [Hazard] = []
        if fm.fileExists(atPath: AppPaths.reportedHazards.path) {
            do {
                let data = try Data(contentsOf: AppPaths.reportedHazards)
                reported = try JSONCoding.decoder.decode([Hazard].self, from: data)
            } catch {
                let msg = "reported_hazards.json is unreadable, ignoring it: \(error)"
                DiagnosticsLog.shared.error(msg)
                result.problems.append(msg)
            }
        }

        let test = TestHazardStore.load()

        let all = seeded + reported + test
        let active = all.filter { !$0.isExpired(at: now) }
        result.hazards = active
        result.seededCount = seeded.filter { !$0.isExpired(at: now) }.count
        result.reportedCount = reported.filter { !$0.isExpired(at: now) }.count
        result.testCount = test.filter { !$0.isExpired(at: now) }.count
        result.expiredDropped = all.count - active.count

        DiagnosticsLog.shared.info("Hazards loaded: \(active.count) active (\(result.seededCount) seeded from \(result.sourceDescription), \(result.reportedCount) reported, \(result.testCount) test), \(result.expiredDropped) expired dropped")
        return result
    }

    private static func loadBundledSeed(now: Date, problems: inout [String]) -> [Hazard] {
        guard let url = AppPaths.bundledSeed else {
            let msg = "Bundled seed_hazards.json missing from the app"
            DiagnosticsLog.shared.error(msg)
            problems.append(msg)
            return []
        }
        switch loadSeedFile(at: url, now: now) {
        case .success(let hazards):
            return hazards
        case .failure(let error):
            let msg = "Bundled seed_hazards.json is unreadable: \(error)"
            DiagnosticsLog.shared.error(msg)
            problems.append(msg)
            return []
        }
    }

    static func loadSeedFile(at url: URL, now: Date) -> Result<[Hazard], SeedError> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        do {
            let file = try JSONCoding.decoder.decode(SeedFile.self, from: data)
            return .success(file.hazards.map { $0.toHazard(loadedAt: now) })
        } catch {
            return .failure(.invalid(describe(error)))
        }
    }

    /// Copies the bundled template to Documents so the owner has a file to edit.
    static func copyBundledTemplateToDocuments(overwrite: Bool) throws {
        guard let src = AppPaths.bundledSeed else { throw SeedError.unreadable("bundled template missing") }
        let dst = AppPaths.seedHazards
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            guard overwrite else { return }
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
        DiagnosticsLog.shared.info("Copied bundled seed template to Documents")
    }

    enum SeedError: Error, CustomStringConvertible {
        case unreadable(String)
        case invalid(String)

        var description: String {
            switch self {
            case .unreadable(let s): return "cannot read file (\(s))"
            case .invalid(let s): return "invalid JSON (\(s))"
            }
        }
    }

    /// Turns a DecodingError into something the owner can act on ("hazards[3].category").
    private static func describe(_ error: Error) -> String {
        guard let d = error as? DecodingError else { return error.localizedDescription }
        func path(_ ctx: DecodingError.Context) -> String {
            ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        switch d {
        case .typeMismatch(_, let ctx): return "wrong type at \(path(ctx)): \(ctx.debugDescription)"
        case .valueNotFound(_, let ctx): return "missing value at \(path(ctx)): \(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx): return "missing key \"\(key.stringValue)\" at \(path(ctx))"
        case .dataCorrupted(let ctx): return "corrupted at \(path(ctx)): \(ctx.debugDescription)"
        @unknown default: return d.localizedDescription
        }
    }
}
