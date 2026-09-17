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
        pendingReports = ReportStore.loadPending().sorted { $0.tappedAt > $1.tappedAt }
        rides = RideStore.listRides()
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
