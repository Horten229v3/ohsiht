import SwiftUI

/// Roadside summary, uncategorised reports with five large buttons each, and
/// export. Also used as the detail screen for previous rides.
struct PostRideView: View {
    @EnvironmentObject private var model: AppModel
    let entry: RideIndexEntry
    let showsDone: Bool

    @State private var confirmDelete = false

    private var current: RideIndexEntry {
        model.rides.first { $0.rideId == entry.rideId } ?? entry
    }

    private var pending: [Report] {
        model.pendingReports(for: entry.rideId)
    }

    var body: some View {
        List {
            summarySection
            if !pending.isEmpty {
                reportsSection
            }
            exportSection
            if current.recovered {
                Section {
                    Label("This ride was not stopped cleanly and was reassembled on the next launch.", systemImage: "arrow.counterclockwise.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            if !showsDone {
                Section {
                    Button("Delete this ride", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(showsDone ? "Ride finished" : Format.dateTime.string(from: current.startedAt))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.screen = .home }
                        .font(.body.bold())
                }
            }
        }
        .confirmationDialog("Delete this ride and its log files?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RideStore.deleteRide(current)
                model.refresh()
            }
        }
    }

    private var summarySection: some View {
        let s = current.summary
        return Section("Summary") {
            row("Alerts fired", "\(s.alertsFired)")
            row("Mean time-to-hazard at trigger", Format.seconds(s.meanTimeToHazardSeconds))
            row("Mean distance at trigger", Format.meters(s.meanDistanceAtTriggerMeters))
            row("Mean audio latency", Format.milliseconds(s.meanPlaybackLatencySeconds))
            row("Reports", "\(s.reports)")
            row("Near-misses (in range, silent)", "\(s.nearMisses)")
            if s.alertsDropped > 0 {
                row("Alerts dropped", "\(s.alertsDropped)")
            }
            row("Duration", Format.duration(s.durationSeconds))
            row("Distance", Format.meters(s.distanceMeters))
            row("GPS fixes", "\(s.fixCount)")
            row("Longest GPS gap", Format.seconds(s.maxGapSeconds))
                .foregroundStyle(s.maxGapSeconds > 5 ? .orange : .primary)
            if s.gapsOver5s > 0 {
                row("Gaps over 5 s", "\(s.gapsOver5s)")
                    .foregroundStyle(.orange)
            }
            row("Max speed", "\(Format.kmh(s.maxSpeedMetersPerSecond)) km/h")
            if s.errors > 0 {
                row("Errors logged", "\(s.errors)")
                    .foregroundStyle(.red)
            }
        }
    }

    private var reportsSection: some View {
        Section {
            ForEach(pending) { report in
                ReportCategoriseRow(report: report)
            }
        } header: {
            Text("Reports to categorise (\(pending.count))")
        } footer: {
            Text("Each categorised report becomes a hazard that can alert on your next ride here. Discarded reports stay in the log but never alert.")
        }
    }

    private var exportSection: some View {
        Section("Export") {
            ShareLink(items: [RideStore.jsonURL(for: current), RideStore.gpxURL(for: current)]) {
                Label("Share ride log (JSON + GPX)", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: RideStore.jsonURL(for: current)) {
                Label("Share JSON only", systemImage: "doc.text")
            }
            ShareLink(item: RideStore.gpxURL(for: current)) {
                Label("Share GPX only", systemImage: "map")
            }
            Text("Files are also in the Files app under On My iPhone › Hazard POC › rides.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
}

/// One pending report: when it happened, and six large buttons.
struct ReportCategoriseRow: View {
    @EnvironmentObject private var model: AppModel
    let report: Report

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Format.time.string(from: report.tappedAt))
                    .font(.headline)
                Spacer()
                if let off = report.offset {
                    Text("\(Format.kmh(off.speed)) km/h · \(Format.number(off.course, decimals: 0))°")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if report.raw == nil {
                    Text("no GPS position")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(HazardCategory.allCases) { category in
                    Button {
                        model.categorise(report, as: category)
                    } label: {
                        Text(category.label)
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) {
                    model.discard(report)
                } label: {
                    Text("Discard")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}

/// All pending reports across rides, reachable from Home after a force-quit.
struct PendingReportsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.pendingReports.isEmpty {
                Text("Nothing to categorise.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.pendingReports) { report in
                ReportCategoriseRow(report: report)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categorise reports")
    }
}
