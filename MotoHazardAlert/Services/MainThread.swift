import Foundation

/// Runs main-actor work from callbacks that arrive on arbitrary threads
/// (CoreLocation, AVFoundation delegates), preserving order when already on main.
enum MainThread {
    static func run(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(body)
            }
        }
    }
}
