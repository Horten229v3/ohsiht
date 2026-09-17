import Foundation

/// Shared encoder/decoder configuration so every file the app writes looks the same.
///
/// Dates are ISO 8601 with fractional seconds (audio latency is measured in
/// milliseconds). Decoding also accepts whole-second timestamps, because the owner
/// will hand-write seed files.
enum JSONCoding {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let wholeSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? wholeSeconds.date(from: string)
    }

    static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(string(from: date))
        }
        var format: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { format.insert(.prettyPrinted) }
        e.outputFormatting = format
        return e
    }

    static let prettyEncoder = makeEncoder(pretty: true)
    static let lineEncoder = makeEncoder(pretty: false)

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = date(from: s) else {
                throw DecodingError.dataCorruptedError(
                    in: c,
                    debugDescription: "Expected ISO 8601 date, got \"\(s)\""
                )
            }
            return date
        }
        return d
    }()
}
