import Foundation

/// Rolling mean of the last N valid speed readings. Raw GPS speed is noisy;
/// using it directly makes the trigger distance jitter by tens of metres.
struct SpeedSmoother: Equatable {
    let window: Int
    private var samples: [Double] = []

    init(window: Int = 5) {
        self.window = max(1, window)
    }

    /// Ignores negative (invalid) speeds so a single dropout does not drag the mean to zero.
    mutating func add(_ speed: Double) {
        guard speed >= 0 else { return }
        samples.append(speed)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }
    }

    /// Mean of the window, or 0 before the first valid sample.
    var smoothed: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var sampleCount: Int { samples.count }

    mutating func reset() {
        samples.removeAll()
    }
}
