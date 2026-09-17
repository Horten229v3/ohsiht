import Foundation
import os

/// Errors and notable events are logged here, never shown to a moving rider.
/// Each entry goes to a text file in Documents, to the system log, and — during a
/// ride — into that ride's JSON via `rideSink`.
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "diagnostics")
    private let queue = DispatchQueue(label: "at.picaro.hazardpoc.diagnostics", qos: .utility)
    private let maxFileBytes = 5 * 1024 * 1024

    /// Set by the ride session while a ride is running.
    var rideSink: (@MainActor (DiagnosticEntry) -> Void)?

    private init() {}

    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }

    func log(_ level: DiagnosticEntry.Level, _ message: String) {
        let entry = DiagnosticEntry(timestamp: Date(), level: level, message: message)
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        // The ride session mutates its in-memory log on the main actor only.
        if rideSink != nil {
            MainThread.run { [weak self] in
                self?.rideSink?(entry)
            }
        }
        let line = "\(JSONCoding.string(from: entry.timestamp)) [\(level.rawValue.uppercased())] \(message)\n"
        queue.async { [weak self] in
            self?.append(line)
        }
    }

    private func append(_ line: String) {
        let url = AppPaths.diagnosticsLog
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > maxFileBytes {
            let rotated = url.deletingPathExtension().appendingPathExtension("1.log")
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }
        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Last lines of the log for the Settings screen.
    func tail(lines count: Int) -> [String] {
        guard let data = try? Data(contentsOf: AppPaths.diagnosticsLog),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(count).map(String.init)
    }
}
