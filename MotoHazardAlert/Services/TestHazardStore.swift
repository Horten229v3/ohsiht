import Foundation

/// Hazards the owner places by hand while standing at a spot, to test when the
/// alert fires on the approach. Kept in their own file so they can be wiped
/// without touching the seed or the reported hazards.
enum TestHazardStore {
    static func load() -> [Hazard] {
        guard let data = try? Data(contentsOf: AppPaths.testHazards) else { return [] }
        do {
            return try JSONCoding.decoder.decode([Hazard].self, from: data)
        } catch {
            DiagnosticsLog.shared.error("test_hazards.json unreadable: \(error.localizedDescription)")
            return []
        }
    }

    static func save(_ hazards: [Hazard]) {
        do {
            if hazards.isEmpty {
                try? FileManager.default.removeItem(at: AppPaths.testHazards)
            } else {
                try JSONCoding.prettyEncoder.encode(hazards).write(to: AppPaths.testHazards, options: .atomic)
            }
        } catch {
            DiagnosticsLog.shared.error("Failed to save test hazards: \(error.localizedDescription)")
        }
    }

    static func add(_ hazard: Hazard) {
        var all = load()
        all.append(hazard)
        save(all)
        DiagnosticsLog.shared.info("Test hazard placed: \(hazard.category.rawValue) at \(hazard.lat), \(hazard.lon) heading \(hazard.heading.map { String(Int($0)) } ?? "any")")
    }

    static func remove(id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
    }

    static func removeAll() {
        save([])
        DiagnosticsLog.shared.info("All test hazards deleted")
    }
}
