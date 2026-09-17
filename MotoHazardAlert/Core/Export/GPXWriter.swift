import Foundation

/// GPX 1.1 export of a ride: the track, plus waypoints for every hazard, every
/// alert trigger point and every report (raw tap and reaction-offset point), so
/// the whole ride can be judged in any mapping tool at once.
enum GPXWriter {
    static func gpx(for ride: RideLog) -> String {
        var out = ""
        out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"Moto Hazard Alert POC \(escape(ride.appVersion))\""
        out += " xmlns=\"http://www.topografix.com/GPX/1/1\""
        out += " xmlns:mha=\"https://picaro.at/hazardpoc/gpx/1\">\n"

        out += "  <metadata>\n"
        out += "    <name>\(escape("Ride \(JSONCoding.string(from: ride.startedAt))"))</name>\n"
        out += "    <desc>\(escape(description(for: ride)))</desc>\n"
        out += "    <time>\(JSONCoding.string(from: ride.startedAt))</time>\n"
        out += "  </metadata>\n"

        for h in ride.hazards {
            let name = "HAZARD \(h.category.rawValue)"
            var desc = "id \(h.id.uuidString.prefix(8))"
            if let heading = h.heading {
                desc += " · heading \(fmt(heading))° ±\(fmt(h.resolvedHeadingTolerance(default: ride.settings.defaultHeadingTolerance)))°"
            } else {
                desc += " · all directions"
            }
            desc += " · \(h.source.rawValue)"
            if let note = h.note, !note.isEmpty { desc += " · \(note)" }
            out += waypoint(lat: h.lat, lon: h.lon, time: h.createdAt, name: name, desc: desc, type: "hazard")
        }

        for a in ride.alerts {
            let name = a.dropped ? "ALERT DROPPED \(a.category.rawValue)" : "ALERT \(a.category.rawValue)"
            var desc = "hazard \(a.hazardId.uuidString.prefix(8)) · dist \(fmt(a.distanceMeters)) m · trigger \(fmt(a.triggerDistanceMeters)) m"
            desc += " · speed \(fmt(a.riderSpeed * 3.6)) km/h"
            if let tth = a.timeToHazardSeconds { desc += " · tth \(fmt(tth, 1)) s" }
            if let lat = a.playbackLatencySeconds { desc += " · latency \(Int(lat * 1000)) ms" }
            if let reason = a.dropReason { desc += " · \(reason)" }
            out += waypoint(lat: a.riderLat, lon: a.riderLon, time: a.triggeredAt, name: name, desc: desc, type: a.dropped ? "alert-dropped" : "alert")
        }

        for r in ride.reports {
            let label = r.status == .discarded ? "discarded" : r.category.rawValue
            if let raw = r.raw {
                out += waypoint(lat: raw.lat, lon: raw.lon, time: r.tappedAt, name: "TAP raw (\(label))",
                                desc: "report \(r.id.uuidString.prefix(8)) · course \(fmt(raw.course))° · speed \(fmt(raw.speed * 3.6)) km/h", type: "report-raw")
            }
            if let off = r.offset {
                out += waypoint(lat: off.lat, lon: off.lon, time: off.timestamp, name: "REPORT \(label)",
                                desc: "report \(r.id.uuidString.prefix(8)) · offset \(fmt(r.reactionTimeSeconds, 1)) s · course \(fmt(off.course))°", type: "report-offset")
            }
        }

        out += "  <trk>\n"
        out += "    <name>Track</name>\n"
        out += "    <trkseg>\n"
        for p in ride.track {
            out += "      <trkpt lat=\"\(coord(p.lat))\" lon=\"\(coord(p.lon))\">\n"
            out += "        <time>\(JSONCoding.string(from: p.timestamp))</time>\n"
            out += "        <extensions>"
            out += "<mha:speed>\(fmt(p.speed, 2))</mha:speed>"
            out += "<mha:course>\(fmt(p.course, 1))</mha:course>"
            out += "<mha:hacc>\(fmt(p.horizontalAccuracy, 1))</mha:hacc>"
            out += "</extensions>\n"
            out += "      </trkpt>\n"
        }
        out += "    </trkseg>\n"
        out += "  </trk>\n"
        out += "</gpx>\n"
        return out
    }

    private static func description(for ride: RideLog) -> String {
        let s = ride.settings
        let sum = ride.summary
        var d = "lead \(fmt(s.leadTimeSeconds, 1)) s · min \(fmt(s.minDistanceMeters)) m · reaction \(fmt(s.reactionTimeSeconds, 1)) s · tolerance \(fmt(s.defaultHeadingTolerance))°"
        d += " · alerts \(sum.alertsFired) · reports \(sum.reports) · near-misses \(sum.nearMisses)"
        if ride.recovered { d += " · RECOVERED" }
        return d
    }

    private static func waypoint(lat: Double, lon: Double, time: Date, name: String, desc: String, type: String) -> String {
        var s = "  <wpt lat=\"\(coord(lat))\" lon=\"\(coord(lon))\">\n"
        s += "    <time>\(JSONCoding.string(from: time))</time>\n"
        s += "    <name>\(escape(name))</name>\n"
        s += "    <desc>\(escape(desc))</desc>\n"
        s += "    <type>\(escape(type))</type>\n"
        s += "  </wpt>\n"
        return s
    }

    static func escape(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "'": r += "&apos;"
            default: r.append(ch)
            }
        }
        return r
    }

    private static func coord(_ v: Double) -> String {
        String(format: "%.7f", v)
    }

    private static func fmt(_ v: Double, _ decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f", v)
    }
}
