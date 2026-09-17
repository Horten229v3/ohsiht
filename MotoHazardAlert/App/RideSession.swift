import Foundation
import Combine
import UIKit

/// Runs one ride: feeds fixes through the trigger engine, plays alerts through
/// the scheduler, records taps, and writes everything to disk as it happens.
@MainActor
final class RideSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case riding
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var displaySpeedKmh: Double?
    @Published private(set) var hazardCount = 0
    @Published private(set) var alertsFired = 0
    @Published private(set) var reportsThisRide = 0
    @Published private(set) var hasFix = false

    private let audio: AudioService

    private var meta: RideMeta?
    private var writer: RideWriter?
    private var track: [TrackPoint] = []
    private var events: [RideEventRecord] = []
    private var hazards: [Hazard] = []
    private var engine = TriggerEngine()
    private var smoother = SpeedSmoother()
    private var fired = FiredHazardTracker()
    private var scheduler = AlertScheduler()
    private var nearMisses = NearMissTracker()
    private var settings = TunableSettings.default
    private var lastRider: TrackPoint?
    private var pumpWorkItem: DispatchWorkItem?

    init(audio: AudioService) {
        self.audio = audio
        audio.onAlertPlaybackFinished = { [weak self] finished in
            self?.alertPlaybackFinished(at: finished)
        }
    }

    var isRiding: Bool { phase == .riding }

    // MARK: Lifecycle

    func start(hazards: [Hazard], hazardSource: String, settings: TunableSettings) {
        guard phase == .idle else { return }
        let now = Date()
        self.settings = settings
        self.hazards = hazards
        engine = TriggerEngine(settings: settings)
        smoother = SpeedSmoother(window: settings.speedSmoothingWindow)
        fired.reset()
        scheduler.reset()
        nearMisses = NearMissTracker()
        track.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        lastRider = nil
        alertsFired = 0
        reportsThisRide = 0
        hazardCount = hazards.count
        displaySpeedKmh = nil
        hasFix = false

        let meta = RideMeta(
            rideId: UUID(),
            startedAt: now,
            appVersion: AppInfo.version,
            settings: settings,
            hazardSource: hazardSource,
            hazards: hazards
        )
        self.meta = meta

        do {
            writer = try RideStore.begin(meta: meta)
        } catch {
            // Riding without a writer would silently produce no log; that defeats the POC.
            // Still log it and continue in memory so stop() can try to write a file.
            writer = nil
            DiagnosticsLog.shared.error("Could not create ride files: \(error.localizedDescription)")
        }

        DiagnosticsLog.shared.rideSink = { [weak self] entry in
            self?.record(.diagnostic(entry))
        }
        DiagnosticsLog.shared.info("Ride started; \(hazards.count) hazards from \(hazardSource); settings lead=\(settings.leadTimeSeconds)s min=\(settings.minDistanceMeters)m reaction=\(settings.reactionTimeSeconds)s tolerance=\(settings.defaultHeadingTolerance)°")

        audio.activateSession()
        UIApplication.shared.isIdleTimerDisabled = true
        phase = .riding
    }

    /// Stops the ride and returns the finished log entry (nil only if writing failed entirely).
    func stop() -> RideIndexEntry? {
        guard phase == .riding, let meta else { return nil }
        let now = Date()
        pumpWorkItem?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false

        for closed in nearMisses.drain(at: now) {
            record(.nearMiss(closed))
        }
        // Anything still queued never played.
        for pending in scheduler.queue {
            var ev = pending.event
            ev.dropped = true
            ev.dropReason = "ride ended before playback"
            record(.alert(ev))
        }
        scheduler.reset()

        DiagnosticsLog.shared.info("Ride stopped; \(track.count) fixes, \(alertsFired) alerts, \(reportsThisRide) reports")
        DiagnosticsLog.shared.rideSink = nil
        audio.deactivateSession()
        writer?.close()

        var entry: RideIndexEntry?
        let folder = writer?.folder ?? AppPaths.ridesDirectory.appendingPathComponent(RideStore.folderName(for: meta), isDirectory: true)
        do {
            entry = try RideStore.finalize(folder: folder, meta: meta, track: track, events: events, endedAt: now, recovered: false).entry
        } catch {
            DiagnosticsLog.shared.error("Failed to write ride log: \(error.localizedDescription)")
        }

        writer = nil
        self.meta = nil
        phase = .idle
        return entry
    }

    // MARK: Fixes

    func handleFix(_ point: TrackPoint) {
        guard phase == .riding else { return }
        if let last = track.last, point.timestamp <= last.timestamp { return }

        track.append(point)
        writer?.append(point)
        lastRider = point
        hasFix = true
        smoother.add(point.speed)
        displaySpeedKmh = point.validSpeed.map { $0 * 3.6 }

        let now = Date()
        let speed = smoother.smoothed
        let rearmed = fired.update(riderLat: point.lat, riderLon: point.lon, rearmDistanceMeters: settings.rearmDistanceMeters)
        if !rearmed.isEmpty {
            DiagnosticsLog.shared.info("Re-armed \(rearmed.count) hazard(s)")
        }

        for hazard in hazards {
            let verdict = engine.evaluate(rider: point, smoothedSpeed: speed, hazard: hazard, alreadyFired: fired.firedIDs, now: now)

            if let closed = nearMisses.observe(hazard: hazard, verdict: verdict, rider: point, smoothedSpeed: speed, now: now, radiusMeters: settings.nearMissRadiusMeters) {
                record(.nearMiss(closed))
            }

            guard verdict.fires else { continue }
            fired.markFired(hazard, at: now)
            let event = AlertEvent(
                id: UUID(),
                hazardId: hazard.id,
                category: hazard.category,
                triggeredAt: now,
                playbackStartedAt: nil,
                outputLatencySeconds: nil,
                riderLat: point.lat,
                riderLon: point.lon,
                riderSpeed: speed,
                riderCourse: point.course,
                distanceMeters: verdict.distanceMeters,
                timeToHazardSeconds: speed > 0.5 ? verdict.distanceMeters / speed : nil,
                triggerDistanceMeters: verdict.triggerDistanceMeters,
                queueDepthAtTrigger: 0,
                dropped: false,
                dropReason: nil
            )
            scheduler.enqueue(AlertScheduler.Pending(hazard: hazard, event: event))
        }

        pumpScheduler(now: now)
    }

    // MARK: Alerts

    private func pumpScheduler(now: Date) {
        guard phase == .riding, let rider = lastRider else { return }
        let decision = scheduler.dequeue(
            now: now,
            riderLat: rider.lat,
            riderLon: rider.lon,
            gapSeconds: settings.alertGapSeconds,
            maxQueued: settings.maxQueuedAlerts
        )
        for dropped in decision.dropped {
            record(.alert(dropped.event))
        }
        guard let play = decision.play else { return }

        var event = play.event
        if let started = audio.playAlert(clip: play.hazard.category.audioClipName) {
            event.playbackStartedAt = started
            event.outputLatencySeconds = audio.outputLatency
            alertsFired += 1
            record(.alert(event))
        } else {
            event.dropped = true
            event.dropReason = "audio playback failed"
            record(.alert(event))
            scheduler.playbackFailed(at: now)
            schedulePump(after: settings.alertGapSeconds)
        }
    }

    private func alertPlaybackFinished(at time: Date) {
        guard phase == .riding else { return }
        scheduler.playbackFinished(at: time)
        // The next fix will pump too, but GPS may be slow; do not let a queued alert wait on it.
        schedulePump(after: settings.alertGapSeconds + 0.05)
    }

    private func schedulePump(after delay: TimeInterval) {
        pumpWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pumpScheduler(now: Date())
            }
        }
        pumpWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: Reports

    /// A tap anywhere on the riding screen. Non-visual feedback only.
    func reportTap() {
        guard phase == .riding, let meta else { return }
        let now = Date()
        audio.playReportConfirm()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let raw = lastRider.map(Position.init)
        let offset = ReactionOffset.position(in: track, tapTime: now, reactionTimeSeconds: settings.reactionTimeSeconds)
        let report = Report(
            id: UUID(),
            rideId: meta.rideId,
            tappedAt: now,
            raw: raw,
            offset: offset,
            reactionTimeSeconds: settings.reactionTimeSeconds,
            category: .other,
            status: .pending,
            categorisedAt: nil,
            hazardId: nil
        )
        reportsThisRide += 1
        record(.report(report))
        ReportStore.addPending(report)
        if raw == nil {
            DiagnosticsLog.shared.warning("Report tap with no GPS fix yet; position unknown")
        }
    }

    // MARK: Recording

    private func record(_ event: RideEventRecord) {
        events.append(event)
        writer?.append(event)
    }
}
