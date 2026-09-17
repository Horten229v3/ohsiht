// swift-tools-version:5.9
//
// This package is NOT how the iOS app is built. Open MotoHazardAlert.xcodeproj
// for that.
//
// It exists so the platform-independent core (data model, trigger engine,
// reaction-time offset, exporters) can be compiled and unit-tested with plain
// `swift test` on any machine with a Swift toolchain, including Linux CI boxes
// that have no Xcode. The Xcode unit-test target compiles the very same files.
import PackageDescription

let package = Package(
    name: "HazardCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        .target(
            name: "HazardCore",
            path: "MotoHazardAlert/Core"
        ),
        .testTarget(
            name: "HazardCoreTests",
            dependencies: ["HazardCore"],
            path: "MotoHazardAlertTests"
        ),
    ]
)
