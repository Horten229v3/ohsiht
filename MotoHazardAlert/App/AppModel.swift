import Foundation
import Combine
import SwiftUI

/// Top-level state: which screen is showing, what is loaded, and the services.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case home
        case riding
        case postRide(RideIndexEntry)
    }

    @Published var screen: Screen = .home
    @Published private(set) var hazardLoad: HazardLoadResult = .empty
    @Published private(set) var testHazards: [Hazard] = []
    @Published private(set) var pendingReports: [Report] = []
    @Published private(set) var rides: [RideIndexEntry] = []
    @Published private(set) var recoveredOnLaunch: [RideIndexEntry] = []

    let settingsStore: SettingsStore
    let location: LocationService
    let audio: AudioService
    let session: RideSession

    private var cancellables: Set<AnyCancellable> = []

    init() {
        settingsStore = SettingsStore()
        location = LocationService()
        audio = AudioService()
        session = RideSession(audio: audio)

        AppPaths.ensureDirectories()
        DiagnosticsLog.shared.info("App launched, version \(AppInfo.version), bundle \(AppInfo.bundleIdentifier)")

        recoveredOnLaunch = RideStore.recoverOrphans()
        refresh()

        location.onFix = { [weak self] point in
            self?.session.handleFix(point)
        }
        // Nested ObservableObjects do not propagate; forward their changes.
        session.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
        location.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        hazardLoad = HazardStore.load()
        testHazards = TestHazardStore.load().sorted { $0.createdAt > $1.createdAt }
        pendingReports = ReportStore.loadPending().sorted { $0.tappedAt > $1.tappedAt }
        rides = RideStore.listRides()
    }

    // MARK: Test hazards (placed by hand at the current position)

    enum PlacementError: Error, LocalizedError {
        case noFix
        case poorAccuracy(Double)

        var errorDescription: String? {
            switch self {
            case .noFix: return "No GPS fix yet. Wait a few seconds with a clear view of the sky."
            case .poorAccuracy(let m): return "GPS accuracy is ±\(Int(m)) m; wait for better than ±\(Int(AppModel.maxPlacementAccuracy)) m."
            }
        }
    }

    static let maxPlacementAccuracy = 30.0

    /// Creates a hazard at the latest fix. `heading` nil = all directions.
    @discardableResult
    func placeTestHazard(category: HazardCategory, heading: Double?) throws -> Hazard {
        guard let fix = location.latest, Date().timeIntervalSince(fix.timestamp) < 15 else {
            throw PlacementError.noFix
        }
        guard fix.horizontalAccuracy <= AppModel.maxPlacementAccuracy else {
            throw PlacementError.poorAccuracy(fix.horizontalAccuracy)
        }
        let now = Date()
        let hazard = Hazard(
            lat: fix.lat,
            lon: fix.lon,
            heading: heading,
            headingTolerance: nil,
            category: category,
            createdAt: now,
            expiresAt: nil,
            source: .manual,
            note: "test hazard placed \(Format.dateTime.string(from: now)), GPS ±\(Int(fix.horizontalAccuracy)) m"
        )
        TestHazardStore.add(hazard)
        refresh()
        return hazard
    }

    func deleteTestHazard(_ hazard: Hazard) {
        TestHazardStore.remove(id: hazard.id)
        refresh()
    }

    func deleteAllTestHazards() {
        TestHazardStore.removeAll()
        refresh()
    }

    // MARK: Ride control

    var canStartRide: Bool {
        location.hasAnyAuthorization && !session.isRiding
    }

    func startRide() {
        guard canStartRide else { return }
        // Reload so a seed file dropped in via the Files app takes effect without relaunch.
        hazardLoad = HazardStore.load()
        session.start(hazards: hazardLoad.hazards, hazardSource: hazardLoad.sourceDescription, settings: settingsStore.settings)
        location.startUpdating()
        screen = .riding
    }

    func stopRide() {
        location.stopUpdating()
        let entry = session.stop()
        refresh()
        if let entry {
            screen = .postRide(entry)
        } else {
            screen = .home
        }
    }

    // MARK: Reports

    func categorise(_ report: Report, as category: HazardCategory) {
        ReportStore.categorise(report, as: category)
        refresh()
    }

    func discard(_ report: Report) {
        ReportStore.discard(report)
        refresh()
    }

    func pendingReports(for rideId: UUID) -> [Report] {
        pendingReports.filter { $0.rideId == rideId }
    }

    // MARK: Test alert (Settings)

    struct TestAlertResult {
        var playCallMilliseconds: Int
        var outputLatencyMilliseconds: Int
        var route: String
        var succeeded: Bool
    }

    func playTestAlert() -> TestAlertResult {
        let wasActive = audio.isSessionActive
        if !wasActive { audio.activateSession() }
        let before = Date()
        let started = audio.playAlert(clip: AudioService.Clip.testAlert)
        let callMs = Int((started ?? Date()).timeIntervalSince(before) * 1000)
        let result = TestAlertResult(
            playCallMilliseconds: callMs,
            outputLatencyMilliseconds: Int(audio.outputLatency * 1000),
            route: audio.routeDescription,
            succeeded: started != nil
        )
        DiagnosticsLog.shared.info("Test alert: play() took \(callMs) ms, output latency \(result.outputLatencyMilliseconds) ms, route \(result.route), ok=\(result.succeeded)")
        return result
    }
}
