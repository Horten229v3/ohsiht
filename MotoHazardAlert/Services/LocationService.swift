import Foundation
import Combine
import CoreLocation

/// Thin wrapper around CLLocationManager configured for continuous 1 Hz fixes
/// with the screen off. Delivers `TrackPoint`s on the main thread.
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var latest: TrackPoint?
    @Published private(set) var isUpdating = false
    /// Foreground-only fixes + compass for placing test hazards on the Home screen.
    @Published private(set) var isPlacing = false
    /// Degrees true (magnetic if true heading is unavailable). nil when the compass is off or unreliable.
    @Published private(set) var compassHeading: Double?

    /// Called on the main actor for every accepted fix while updating.
    var onFix: (@MainActor (TrackPoint) -> Void)?

    private let manager: CLLocationManager
    private var lastAcceptedTimestamp: Date?
    private var staleFixesDropped = 0

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        // The single most common cause of multi-minute gaps: iOS pausing updates
        // because it thinks the user stopped. Never let it.
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    var hasAlwaysAuthorization: Bool { authorizationStatus == .authorizedAlways }

    var hasAnyAuthorization: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Not asked yet"
        case .restricted: return "Restricted by device policy"
        case .denied: return "Denied — enable in iOS Settings"
        case .authorizedWhenInUse: return "While Using only — set to Always in iOS Settings"
        case .authorizedAlways: return accuracyAuthorization == .fullAccuracy ? "Always, precise" : "Always, but Precise Location is OFF"
        @unknown default: return "Unknown"
        }
    }

    /// Ask on the Home screen, never during a ride. From `.notDetermined` iOS shows the
    /// While-Using prompt and grants Always provisionally; from `.authorizedWhenInUse`
    /// it shows the one-time "Change to Always Allow?" prompt.
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startUpdating() {
        guard !isUpdating else { return }
        lastAcceptedTimestamp = nil
        staleFixesDropped = 0
        // Requires the `location` background mode in Info.plist; crashes otherwise.
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isUpdating = true
        DiagnosticsLog.shared.info("Location updates started (auth: \(statusDescription))")
    }

    func stopUpdating() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isUpdating = false
        DiagnosticsLog.shared.info("Location updates stopped; stale fixes dropped: \(staleFixesDropped)")
        if isPlacing { manager.startUpdatingLocation() }
    }

    /// Fixes and compass while the placement sheet is open. Foreground only; does not
    /// touch the ride's background configuration.
    func startPlacementUpdates() {
        guard !isPlacing else { return }
        isPlacing = true
        if !isUpdating {
            lastAcceptedTimestamp = nil
            manager.startUpdatingLocation()
        }
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 2
            manager.headingOrientation = .portrait
            manager.startUpdatingHeading()
        }
    }

    func stopPlacementUpdates() {
        guard isPlacing else { return }
        isPlacing = false
        manager.stopUpdatingHeading()
        compassHeading = nil
        if !isUpdating { manager.stopUpdatingLocation() }
    }

    private func handle(_ locations: [CLLocation]) {
        let now = Date()
        for loc in locations {
            // Invalid fix.
            guard loc.horizontalAccuracy >= 0 else { continue }
            // CoreLocation replays a cached fix on start; a fix older than the ride is misleading.
            if now.timeIntervalSince(loc.timestamp) > 10 {
                staleFixesDropped += 1
                continue
            }
            // Out-of-order or duplicate.
            if let last = lastAcceptedTimestamp, loc.timestamp <= last { continue }
            lastAcceptedTimestamp = loc.timestamp

            let point = TrackPoint(
                timestamp: loc.timestamp,
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                speed: loc.speed,
                course: loc.course,
                horizontalAccuracy: loc.horizontalAccuracy
            )
            latest = point
            if let onFix {
                MainThread.run { onFix(point) }
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.accuracyAuthorization = accuracy
            DiagnosticsLog.shared.info("Location authorization changed: \(self.statusDescription)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Delivered on the main thread because the manager was created there; keep
        // the FIFO guarantee if that ever changes.
        if Thread.isMainThread {
            handle(locations)
        } else {
            DispatchQueue.main.async { self.handle(locations) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negative accuracy means the compass needs calibration; treat as unavailable.
        let value: Double? = newHeading.headingAccuracy < 0
            ? nil
            : (newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
        DispatchQueue.main.async { self.compassHeading = value }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Only ever relevant on the Home screen; never during a ride (no modal UI while riding).
        return isPlacing && !isUpdating
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiagnosticsLog.shared.error("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        // Should never happen with pausesLocationUpdatesAutomatically = false; if it does, it explains a gap.
        DiagnosticsLog.shared.warning("iOS paused location updates")
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        DiagnosticsLog.shared.warning("iOS resumed location updates")
    }
}
