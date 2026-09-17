import Foundation

/// Every file the app touches, in one place. All under Documents so the Files
/// app (and Finder) can see them: `UIFileSharingEnabled` is on.
enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Owner-replaceable hazard file. If present it wins over the bundled template.
    static var seedHazards: URL { documents.appendingPathComponent("seed_hazards.json") }

    /// Hazards created from categorised rider reports.
    static var reportedHazards: URL { documents.appendingPathComponent("reported_hazards.json") }

    /// Reports awaiting categorisation, across launches.
    static var pendingReports: URL { documents.appendingPathComponent("pending_reports.json") }

    /// Free-text error/info log across all rides.
    static var diagnosticsLog: URL { documents.appendingPathComponent("diagnostics.log") }

    static var ridesDirectory: URL { documents.appendingPathComponent("rides", isDirectory: true) }

    static var bundledSeed: URL? {
        bundledResource("seed_hazards", extension: "json", subdirectory: "Resources")
    }

    /// Synced folders normally copy resources flat into the bundle; fall back to the
    /// source subdirectory in case the folder structure was preserved.
    static func bundledResource(_ name: String, extension ext: String, subdirectory: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(subdirectory)")
    }

    static func ensureDirectories() {
        try? FileManager.default.createDirectory(at: ridesDirectory, withIntermediateDirectories: true)
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "?"
    }
}
