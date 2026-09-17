import Foundation
import AVFoundation

/// Plays the bundled clips through whatever the phone's audio output is —
/// on the bike, a Bluetooth helmet intercom (standard A2DP; no SDK involved).
///
/// The session is configured and activated at ride start and kept active so
/// the first alert has no cold-start delay.
final class AudioService: NSObject {
    enum Clip {
        static let reportConfirm = "tone_report_confirm"
        static let testAlert = HazardCategory.other.audioClipName
        static var all: [String] {
            HazardCategory.allCases.map { $0.audioClipName } + [reportConfirm]
        }
    }

    /// Called on the main actor when an alert clip (not the confirm tone) finishes or fails.
    var onAlertPlaybackFinished: (@MainActor (Date) -> Void)?

    private(set) var isSessionActive = false
    private var players: [String: AVAudioPlayer] = [:]
    private var alertPlayer: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private let session = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        preload()
        observeSession()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Session

    func activateSession() {
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
            isSessionActive = true
            DiagnosticsLog.shared.info("Audio session active; output: \(routeDescription); output latency \(Int(session.outputLatency * 1000)) ms")
        } catch {
            isSessionActive = false
            DiagnosticsLog.shared.error("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    func deactivateSession() {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            DiagnosticsLog.shared.warning("Audio session deactivation failed: \(error.localizedDescription)")
        }
        isSessionActive = false
    }

    /// Delay the OS reports between "playback started" and sound at the output.
    var outputLatency: TimeInterval { session.outputLatency }

    var routeDescription: String {
        let outputs = session.currentRoute.outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }
        return outputs.isEmpty ? "none" : outputs.joined(separator: ", ")
    }

    // MARK: Playback

    /// Starts an alert clip. Returns the wall-clock time at which `play()` succeeded,
    /// or nil on failure. Exactly one alert plays at a time; the scheduler guarantees that.
    func playAlert(clip name: String) -> Date? {
        guard let player = players[name] else {
            DiagnosticsLog.shared.error("Missing audio clip \(name)")
            return nil
        }
        if let current = alertPlayer, current.isPlaying {
            current.stop()
        }
        player.currentTime = 0
        player.delegate = self
        alertPlayer = player
        guard player.play() else {
            DiagnosticsLog.shared.error("play() returned false for \(name)")
            alertPlayer = nil
            return nil
        }
        return Date()
    }

    /// Short confirmation for a report tap. Independent of the alert queue so it can
    /// overlap an alert; the rider must always know the tap registered.
    func playReportConfirm() {
        guard let player = players[Clip.reportConfirm] else { return }
        player.currentTime = 0
        if !player.play() {
            DiagnosticsLog.shared.error("Report confirm tone failed to play")
        }
    }

    // MARK: Internals

    private func preload() {
        for name in Clip.all {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                DiagnosticsLog.shared.error("Bundled clip not found: \(name).wav")
                continue
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                // Fixed relative volume. iOS does not let an app override the system
                // media volume; see README, "Known limitations".
                p.volume = 1.0
                p.numberOfLoops = 0
                p.prepareToPlay()
                players[name] = p
            } catch {
                DiagnosticsLog.shared.error("Failed to load clip \(name): \(error.localizedDescription)")
            }
        }
    }

    private func observeSession() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            DiagnosticsLog.shared.error("Media services were reset; reloading clips")
            self.players.removeAll()
            self.preload()
            if self.isSessionActive { self.activateSession() }
        })
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            DiagnosticsLog.shared.warning("Audio interrupted (call, Siri, …)")
            if let p = alertPlayer, p.isPlaying || p.currentTime > 0 {
                p.stop()
                alertPlayer = nil
                notifyAlertFinished(at: Date())
            }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            DiagnosticsLog.shared.info("Audio interruption ended (shouldResume: \(opts.contains(.shouldResume)))")
            if isSessionActive { activateSession() }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: raw) ?? .unknown
        let reasonText: String
        switch reason {
        case .newDeviceAvailable: reasonText = "new device available"
        case .oldDeviceUnavailable: reasonText = "device disconnected"
        case .categoryChange: reasonText = "category change"
        case .override: reasonText = "override"
        case .wakeFromSleep: reasonText = "wake from sleep"
        case .noSuitableRouteForCategory: reasonText = "no suitable route"
        case .routeConfigurationChange: reasonText = "route configuration change"
        default: reasonText = "unknown (\(raw))"
        }
        DiagnosticsLog.shared.info("Audio route changed (\(reasonText)); now: \(routeDescription); latency \(Int(session.outputLatency * 1000)) ms")
    }

    private func notifyAlertFinished(at time: Date) {
        MainThread.run { [weak self] in
            self?.onAlertPlaybackFinished?(time)
        }
    }
}

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === alertPlayer else { return }
        alertPlayer = nil
        if !flag { DiagnosticsLog.shared.warning("Alert clip did not finish successfully") }
        notifyAlertFinished(at: Date())
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === alertPlayer else { return }
        alertPlayer = nil
        DiagnosticsLog.shared.error("Audio decode error: \(error?.localizedDescription ?? "unknown")")
        notifyAlertFinished(at: Date())
    }
}
