import Foundation
import Combine

/// Persists the tunable constants and small app flags in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let settings = "tunableSettings.v1"
        static let disclaimerAccepted = "disclaimerAccepted.v1"
    }

    @Published var settings: TunableSettings {
        didSet { persist() }
    }

    @Published var disclaimerAccepted: Bool {
        didSet { UserDefaults.standard.set(disclaimerAccepted, forKey: Key.disclaimerAccepted) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.settings),
           let decoded = try? JSONCoding.decoder.decode(TunableSettings.self, from: data) {
            settings = decoded.clamped()
        } else {
            settings = .default
        }
        disclaimerAccepted = defaults.bool(forKey: Key.disclaimerAccepted)
    }

    func resetToDefaults() {
        settings = .default
    }

    private func persist() {
        if let data = try? JSONCoding.lineEncoder.encode(settings) {
            defaults.set(data, forKey: Key.settings)
        }
    }
}
