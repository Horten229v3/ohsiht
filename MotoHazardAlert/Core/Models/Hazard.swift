import Foundation

/// A point on a road, with a direction of travel, that produces an audio cue
/// before the rider reaches it.
struct Hazard: Codable, Identifiable, Equatable {
    var id: UUID
    /// WGS84 degrees.
    var lat: Double
    var lon: Double
    /// Direction of travel (0–359, degrees true) the hazard applies to.
    /// `nil` means the hazard applies in all directions.
    var heading: Double?
    /// Degrees either side of `heading`. `nil` means "use the app-wide default
    /// from Settings" (spec default 60). A value in the seed file wins.
    var headingTolerance: Double?
    var category: HazardCategory
    var createdAt: Date
    var expiresAt: Date
    var source: HazardSource
    /// Optional free-text landmark for the seed author ("exit of hairpin 3").
    /// Never shown while riding; copied into exports so logs are legible.
    var note: String?

    init(
        id: UUID = UUID(),
        lat: Double,
        lon: Double,
        heading: Double?,
        headingTolerance: Double? = nil,
        category: HazardCategory,
        createdAt: Date,
        expiresAt: Date? = nil,
        source: HazardSource,
        note: String? = nil
    ) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.heading = heading.map(Hazard.normalise)
        self.headingTolerance = headingTolerance
        self.category = category
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? HazardExpiry.expiry(for: category, createdAt: createdAt)
        self.source = source
        self.note = note
    }

    func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }

    func resolvedHeadingTolerance(default defaultTolerance: Double) -> Double {
        headingTolerance ?? defaultTolerance
    }

    static func normalise(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }
}

/// The seed file format is forgiving: `id`, `createdAt`, `expiresAt`, `source`
/// and `headingTolerance` may all be omitted. Missing `createdAt` becomes the
/// load time, so a bare template never expires between launches; missing
/// `expiresAt` is computed from the category table.
struct SeedHazardRecord: Codable {
    var id: UUID?
    var lat: Double
    var lon: Double
    var heading: Double?
    var headingTolerance: Double?
    var category: HazardCategory
    var createdAt: Date?
    var expiresAt: Date?
    var source: HazardSource?
    var note: String?

    func toHazard(loadedAt now: Date) -> Hazard {
        let created = createdAt ?? now
        return Hazard(
            id: id ?? UUID(),
            lat: lat,
            lon: lon,
            heading: heading,
            headingTolerance: headingTolerance,
            category: category,
            createdAt: created,
            expiresAt: expiresAt,
            source: source ?? .seeded,
            note: note
        )
    }
}

struct SeedFile: Codable {
    var name: String?
    var description: String?
    var hazards: [SeedHazardRecord]
}
