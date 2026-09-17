import Foundation

/// Display formatting for the few numbers the owner reads at the roadside.
enum Format {
    static func kmh(_ metersPerSecond: Double?) -> String {
        guard let v = metersPerSecond, v >= 0 else { return "—" }
        return String(format: "%.0f", v * 3.6)
    }

    static func meters(_ m: Double?) -> String {
        guard let m else { return "—" }
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        return String(format: "%.0f m", m)
    }

    static func seconds(_ s: Double?, decimals: Int = 1) -> String {
        guard let s else { return "—" }
        return String(format: "%.\(decimals)f s", s)
    }

    static func milliseconds(_ s: Double?) -> String {
        guard let s else { return "—" }
        return "\(Int((s * 1000).rounded())) ms"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    static func number(_ v: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", v)
    }
}
