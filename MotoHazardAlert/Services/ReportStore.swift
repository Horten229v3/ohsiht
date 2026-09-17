import Foundation

/// Reports waiting for categorisation, and the hazards created from them.
/// Never loses a report: a pending report survives force-quit as `other` and is
/// shown again on next launch.
enum ReportStore {
    static func loadPending() -> [Report] {
        guard let data = try? Data(contentsOf: AppPaths.pendingReports) else { return [] }
        do {
            return try JSONCoding.decoder.decode([Report].self, from: data)
        } catch {
            DiagnosticsLog.shared.error("pending_reports.json unreadable: \(error.localizedDescription)")
            return []
        }
    }

    static func savePending(_ reports: [Report]) {
        do {
            try JSONCoding.prettyEncoder.encode(reports).write(to: AppPaths.pendingReports, options: .atomic)
        } catch {
            DiagnosticsLog.shared.error("Failed to save pending reports: \(error.localizedDescription)")
        }
    }

    static func addPending(_ report: Report) {
        var all = loadPending()
        all.removeAll { $0.id == report.id }
        all.append(report)
        savePending(all)
    }

    /// Assigns a category, persists the change into the ride log, and creates a live
    /// hazard at the offset position (falling back to the raw tap) so it can alert
    /// on the next lap.
    @discardableResult
    static func categorise(_ report: Report, as category: HazardCategory, now: Date = Date()) -> Report {
        var updated = report
        updated.category = category
        updated.status = .categorised
        updated.categorisedAt = now

        if let pos = report.offset ?? report.raw {
            let hazard = Hazard(
                lat: pos.lat,
                lon: pos.lon,
                heading: pos.course >= 0 ? pos.course : nil,
                headingTolerance: nil,
                category: category,
                createdAt: report.tappedAt,
                expiresAt: nil,
                source: .reported,
                note: "reported \(JSONCoding.string(from: report.tappedAt))"
            )
            appendReportedHazard(hazard)
            updated.hazardId = hazard.id
        } else {
            DiagnosticsLog.shared.warning("Report \(report.id) has no position; categorised but no hazard created")
        }

        removePending(report.id)
        RideStore.updateReport(updated)
        return updated
    }

    @discardableResult
    static func discard(_ report: Report, now: Date = Date()) -> Report {
        var updated = report
        updated.status = .discarded
        updated.categorisedAt = now
        removePending(report.id)
        RideStore.updateReport(updated)
        return updated
    }

    private static func removePending(_ id: UUID) {
        var all = loadPending()
        all.removeAll { $0.id == id }
        savePending(all)
    }

    static func loadReportedHazards() -> [Hazard] {
        guard let data = try? Data(contentsOf: AppPaths.reportedHazards) else { return [] }
        return (try? JSONCoding.decoder.decode([Hazard].self, from: data)) ?? []
    }

    private static func appendReportedHazard(_ hazard: Hazard) {
        var all = loadReportedHazards()
        all.append(hazard)
        do {
            try JSONCoding.prettyEncoder.encode(all).write(to: AppPaths.reportedHazards, options: .atomic)
        } catch {
            DiagnosticsLog.shared.error("Failed to save reported hazard: \(error.localizedDescription)")
        }
    }

    static func deleteAllReportedHazards() {
        try? FileManager.default.removeItem(at: AppPaths.reportedHazards)
        DiagnosticsLog.shared.info("Deleted all reported hazards")
    }
}
