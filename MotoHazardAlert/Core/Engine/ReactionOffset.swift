import Foundation

/// A rider taps *after* passing a hazard. Walk backwards through the recorded
/// track to where they were `reactionTimeSeconds` earlier, and use that position
/// and course for the report.
enum ReactionOffset {
    /// - Parameters:
    ///   - track: fixes in chronological order.
    ///   - tapTime: when the tap registered.
    ///   - reactionTimeSeconds: how far back to look.
    /// - Returns: the interpolated position, or `nil` if the track does not reach
    ///   back that far (ride just started) or is empty.
    static func position(in track: [TrackPoint], tapTime: Date, reactionTimeSeconds: Double) -> Position? {
        guard !track.isEmpty else { return nil }
        let target = tapTime.addingTimeInterval(-max(0, reactionTimeSeconds))

        guard let first = track.first, target >= first.timestamp else { return nil }

        // Walk backwards: the target is almost always within the last few fixes.
        var i = track.count - 1
        while i > 0, track[i].timestamp > target {
            i -= 1
        }
        // Now track[i].timestamp <= target (or i == 0).
        if i == track.count - 1 {
            // Target is at or after the last fix: the newest fix is our best estimate.
            // Also covers a tap that arrives slightly before the fix for the same second.
            return Position(track[i])
        }
        return Geo.interpolate(track[i], track[i + 1], at: target)
    }
}
