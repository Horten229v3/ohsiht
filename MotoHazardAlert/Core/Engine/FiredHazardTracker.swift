import Foundation

/// Remembers which hazards have fired and re-arms them once the rider is far
/// enough away, so a hazard alerts again on a return leg or a second lap but
/// not repeatedly on a single approach.
struct FiredHazardTracker: Equatable {
    private struct Entry: Equatable {
        var lat: Double
        var lon: Double
        var firedAt: Date
    }

    private var entries: [UUID: Entry] = [:]

    var firedIDs: Set<UUID> { Set(entries.keys) }

    var isEmpty: Bool { entries.isEmpty }

    mutating func markFired(_ hazard: Hazard, at time: Date) {
        entries[hazard.id] = Entry(lat: hazard.lat, lon: hazard.lon, firedAt: time)
    }

    /// Call on every fix. Returns the ids that were re-armed on this update.
    @discardableResult
    mutating func update(riderLat: Double, riderLon: Double, rearmDistanceMeters: Double) -> [UUID] {
        var rearmed: [UUID] = []
        for (id, entry) in entries {
            let d = Geo.distanceMeters(lat1: riderLat, lon1: riderLon, lat2: entry.lat, lon2: entry.lon)
            if d > rearmDistanceMeters {
                rearmed.append(id)
            }
        }
        for id in rearmed {
            entries.removeValue(forKey: id)
        }
        return rearmed
    }

    mutating func reset() {
        entries.removeAll()
    }
}
