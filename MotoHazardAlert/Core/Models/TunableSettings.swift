import Foundation

/// Every number that is a guess lives here, is editable in Settings where the
/// spec asks for it, and is written into every ride log so rides at different
/// settings can be compared.
struct TunableSettings: Codable, Equatable {
    // MARK: Editable in-app (the four the spec names)

    /// Seconds of warning before the rider reaches the hazard at current speed.
    var leadTimeSeconds: Double = 11
    /// Floor for the trigger distance so alerts still fire at walking pace.
    var minDistanceMeters: Double = 80
    /// How far back in the track to look for the position of a reported hazard.
    var reactionTimeSeconds: Double = 2.5
    /// Applied to hazards whose seed record omits `headingTolerance`.
    var defaultHeadingTolerance: Double = 60

    // MARK: Fixed for the POC but recorded so nothing is hidden

    /// Gate 4: bearing to hazard must be within ± this of the rider's course.
    var aheadConeDegrees: Double = 45
    /// A fired hazard re-arms once the rider is further away than this.
    var rearmDistanceMeters: Double = 1000
    /// Rolling window (fixes) for the smoothed speed used in the trigger distance.
    var speedSmoothingWindow: Int = 5
    /// Silence between consecutive alerts.
    var alertGapSeconds: Double = 2
    /// If more than this many alerts are queued, play the nearest and drop the rest.
    var maxQueuedAlerts: Int = 3

    static let `default` = TunableSettings()

    func triggerDistance(forSpeed speedMetersPerSecond: Double) -> Double {
        max(speedMetersPerSecond * leadTimeSeconds, minDistanceMeters)
    }

    /// Ranges the Settings screen enforces. Wide on purpose: the owner is meant
    /// to explore, but not to type something that silences the app by accident.
    enum Range {
        static let leadTimeSeconds: ClosedRange<Double> = 3...30
        static let minDistanceMeters: ClosedRange<Double> = 20...500
        static let reactionTimeSeconds: ClosedRange<Double> = 0...10
        static let headingTolerance: ClosedRange<Double> = 10...180
    }

    func clamped() -> TunableSettings {
        var s = self
        s.leadTimeSeconds = min(max(s.leadTimeSeconds, Range.leadTimeSeconds.lowerBound), Range.leadTimeSeconds.upperBound)
        s.minDistanceMeters = min(max(s.minDistanceMeters, Range.minDistanceMeters.lowerBound), Range.minDistanceMeters.upperBound)
        s.reactionTimeSeconds = min(max(s.reactionTimeSeconds, Range.reactionTimeSeconds.lowerBound), Range.reactionTimeSeconds.upperBound)
        s.defaultHeadingTolerance = min(max(s.defaultHeadingTolerance, Range.headingTolerance.lowerBound), Range.headingTolerance.upperBound)
        return s
    }
}
