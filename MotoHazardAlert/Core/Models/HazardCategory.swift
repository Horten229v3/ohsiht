import Foundation

/// The hazard categories in scope for the POC.
///
/// Police / speed-camera / radar reporting is deliberately absent and must not
/// be added, even as a hidden option. See README, "Out of scope".
enum HazardCategory: String, Codable, CaseIterable, Identifiable {
    case gravel
    case cattle
    case accident
    case surface
    case other

    var id: String { rawValue }

    /// Human label for post-ride categorisation buttons. Never shown while riding.
    var label: String {
        switch self {
        case .gravel: return "Gravel"
        case .cattle: return "Cattle"
        case .accident: return "Accident"
        case .surface: return "Surface"
        case .other: return "Other"
        }
    }

    /// Bundled audio clip (without extension) spoken when this category alerts.
    /// Cues describe what is there; they never instruct the rider.
    var audioClipName: String {
        switch self {
        case .gravel: return "gravel_ahead"
        case .cattle: return "cattle_ahead"
        case .accident: return "accident_ahead"
        case .surface: return "rough_surface_ahead"
        case .other: return "hazard_ahead"
        }
    }
}

enum HazardSource: String, Codable {
    case seeded
    case reported
    /// Placed by hand at the rider's current position from the Home screen (test mode).
    case manual
}

/// Single table of expiry defaults. These are guesses and will change; edit here only.
enum HazardExpiry {
    static let defaults: [HazardCategory: TimeInterval] = [
        .accident: 3 * 3600,
        .gravel: 14 * 86_400,
        .cattle: 7 * 86_400,
        .surface: 90 * 86_400,
        .other: 7 * 86_400,
    ]

    static func duration(for category: HazardCategory) -> TimeInterval {
        defaults[category] ?? 7 * 86_400
    }

    static func expiry(for category: HazardCategory, createdAt: Date) -> Date {
        createdAt.addingTimeInterval(duration(for: category))
    }
}
