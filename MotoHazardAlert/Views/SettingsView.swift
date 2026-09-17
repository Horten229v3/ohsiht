import SwiftUI

/// The tunables, a test alert, seed-file helpers and log export.
/// Not reachable during a ride.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: SettingsStore

    @State private var testResult: AppModel.TestAlertResult?
    @State private var seedMessage: String?
    @State private var confirmOverwriteSeed = false
    @State private var confirmDeleteReported = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            tunablesSection
            audioSection
            seedSection
            logsSection
            aboutSection
        }
        .navigationTitle("Settings")
        .confirmationDialog("Overwrite Documents/seed_hazards.json with the bundled template?", isPresented: $confirmOverwriteSeed, titleVisibility: .visible) {
            Button("Overwrite", role: .destructive) { copySeed(overwrite: true) }
        }
        .confirmationDialog("Delete all hazards created from your reports?", isPresented: $confirmDeleteReported, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ReportStore.deleteAllReportedHazards()
                model.refresh()
            }
        }
        .confirmationDialog("Reset all four constants to their defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
        }
    }

    // MARK: Tunables

    private var tunablesSection: some View {
        Section {
            tunable(
                title: "Lead time",
                detail: "Seconds of warning before reaching the hazard, at current speed.",
                value: $store.settings.leadTimeSeconds,
                range: TunableSettings.Range.leadTimeSeconds,
                step: 0.5,
                unit: "s",
                decimals: 1
            )
            tunable(
                title: "Minimum distance",
                detail: "Trigger distance never drops below this, however slow you go.",
                value: $store.settings.minDistanceMeters,
                range: TunableSettings.Range.minDistanceMeters,
                step: 10,
                unit: "m",
                decimals: 0
            )
            tunable(
                title: "Reaction time",
                detail: "How far back along the track a report is placed.",
                value: $store.settings.reactionTimeSeconds,
                range: TunableSettings.Range.reactionTimeSeconds,
                step: 0.1,
                unit: "s",
                decimals: 1
            )
            tunable(
                title: "Heading tolerance",
                detail: "Default ± degrees for hazards whose seed record has none.",
                value: $store.settings.defaultHeadingTolerance,
                range: TunableSettings.Range.headingTolerance,
                step: 5,
                unit: "°",
                decimals: 0
            )
            LabeledContent("Trigger distance at 60 / 100 / 130 km/h") {
                Text("\(Int(store.settings.triggerDistance(forSpeed: 60 / 3.6))) / \(Int(store.settings.triggerDistance(forSpeed: 100 / 3.6))) / \(Int(store.settings.triggerDistance(forSpeed: 130 / 3.6))) m")
                    .monospacedDigit()
            }
            .font(.footnote)
            Button("Reset to defaults", role: .destructive) { confirmReset = true }
        } header: {
            Text("Trigger constants")
        } footer: {
            Text("Recorded in every ride log. Change one thing between rides on the same road. Fixed for this build: ahead-cone ±\(Int(store.settings.aheadConeDegrees))°, re-arm \(Int(store.settings.rearmDistanceMeters)) m, speed smoothing over \(store.settings.speedSmoothingWindow) fixes, \(Format.number(store.settings.alertGapSeconds, decimals: 0)) s between alerts, max \(store.settings.maxQueuedAlerts) queued.")
        }
    }

    private func tunable(
        title: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        decimals: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: value, in: range, step: step) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(Format.number(value.wrappedValue, decimals: decimals)) \(unit)")
                        .monospacedDigit()
                        .font(.body.bold())
                }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Audio

    private var audioSection: some View {
        Section {
            Button {
                testResult = model.playTestAlert()
            } label: {
                Label("Play test alert", systemImage: "speaker.wave.2.fill")
            }
            .disabled(model.session.isRiding)
            if let r = testResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.succeeded ? "Played." : "Playback failed — see diagnostics.")
                        .foregroundStyle(r.succeeded ? .primary : .red)
                    Text("play() call: \(r.playCallMilliseconds) ms · output latency: \(r.outputLatencyMilliseconds) ms")
                    Text("Output: \(r.route)")
                }
                .font(.footnote)
            }
        } header: {
            Text("Audio")
        } footer: {
            Text("Connect the helmet first, then test. iOS does not let an app override the media volume: set it on the phone or the intercom before riding.")
        }
    }

    // MARK: Seed file

    private var seedSection: some View {
        Section {
            LabeledContent("In use", value: model.hazardLoad.sourceDescription)
                .font(.footnote)
            if FileManager.default.fileExists(atPath: AppPaths.seedHazards.path) {
                Button("Replace Documents seed file with bundled template") { confirmOverwriteSeed = true }
            } else {
                Button("Copy bundled template to Documents for editing") { copySeed(overwrite: false) }
            }
            Button("Reload hazards") {
                model.refresh()
                seedMessage = "Loaded \(model.hazardLoad.hazards.count) active hazards from \(model.hazardLoad.sourceDescription)."
            }
            if model.hazardLoad.reportedCount > 0 || FileManager.default.fileExists(atPath: AppPaths.reportedHazards.path) {
                Button("Delete hazards created from my reports", role: .destructive) { confirmDeleteReported = true }
            }
            if let seedMessage {
                Text(seedMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Hazard file")
        } footer: {
            Text("Put your own seed_hazards.json in Files › On My iPhone › Hazard POC. It replaces the bundled template without rebuilding. Hazards are reloaded every time a ride starts.")
        }
    }

    private func copySeed(overwrite: Bool) {
        do {
            try HazardStore.copyBundledTemplateToDocuments(overwrite: overwrite)
            model.refresh()
            seedMessage = "Template copied to Documents/seed_hazards.json."
        } catch {
            seedMessage = "Copy failed: \(error.localizedDescription)"
            DiagnosticsLog.shared.error("Seed copy failed: \(error.localizedDescription)")
        }
    }

    // MARK: Logs

    private var logsSection: some View {
        Section {
            NavigationLink("Ride logs (\(model.rides.count))") { RideListView() }
            if FileManager.default.fileExists(atPath: AppPaths.diagnosticsLog.path) {
                ShareLink(item: AppPaths.diagnosticsLog) {
                    Label("Share diagnostics log", systemImage: "square.and.arrow.up")
                }
            }
            NavigationLink("View recent diagnostics") { DiagnosticsTailView() }
        } header: {
            Text("Logs")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppInfo.version)
            LabeledContent("Bundle ID", value: AppInfo.bundleIdentifier)
                .font(.footnote)
            Text("Experimental software. Hazard data may be wrong or out of date. Ride to the conditions you can see.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct DiagnosticsTailView: View {
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if lines.isEmpty {
                    Text("Empty.").foregroundStyle(.secondary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(lineColor(line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Diagnostics")
        .onAppear { lines = DiagnosticsLog.shared.tail(lines: 200) }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("[ERROR]") { return .red }
        if line.contains("[WARNING]") { return .orange }
        return .primary
    }
}
