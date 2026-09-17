import SwiftUI
import UIKit
import CoreLocation

/// Planning screen. Everything that needs reading or tapping small things
/// happens here, before the ride.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPlaceHazard = false

    var body: some View {
        NavigationStack {
            List {
                startSection
                hazardsSection
                testHazardSection
                locationSection
                if !model.pendingReports.isEmpty {
                    pendingSection
                }
                if !model.recoveredOnLaunch.isEmpty {
                    recoveredSection
                }
                ridesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hazard POC")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onAppear { model.refresh() }
            .sheet(isPresented: $showPlaceHazard, onDismiss: { model.refresh() }) {
                PlaceHazardView()
                    .environmentObject(model)
            }
        }
    }

    private var testHazardSection: some View {
        Section {
            Button {
                showPlaceHazard = true
            } label: {
                Label("Place a test hazard here", systemImage: "mappin.and.ellipse")
            }
            .disabled(!model.location.hasAnyAuthorization)
            if model.hazardLoad.testCount > 0 {
                LabeledContent("Test hazards active", value: "\(model.hazardLoad.testCount)")
                    .font(.footnote)
            }
        } header: {
            Text("Test mode")
        } footer: {
            Text("Stop, place a hazard at your position with a direction, then start a ride and approach it to see when it fires.")
        }
    }

    private var startSection: some View {
        Section {
            Button {
                model.startRide()
            } label: {
                HStack {
                    Spacer()
                    Label("Start Ride", systemImage: "play.fill")
                        .font(.title2.bold())
                        .padding(.vertical, 14)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartRide)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if !model.location.hasAnyAuthorization {
                Text("Grant location access below before starting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !model.location.hasAlwaysAuthorization {
                Label("Location is not set to Always. Recording will stop when the phone locks.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var hazardsSection: some View {
        Section("Hazards") {
            LabeledContent("Active hazards", value: "\(model.hazardLoad.hazards.count)")
            LabeledContent("Seeded", value: "\(model.hazardLoad.seededCount)")
            LabeledContent("From your reports", value: "\(model.hazardLoad.reportedCount)")
            if model.hazardLoad.testCount > 0 {
                LabeledContent("Placed by hand (test)", value: "\(model.hazardLoad.testCount)")
            }
            LabeledContent("Source", value: model.hazardLoad.sourceDescription)
                .font(.footnote)
            if model.hazardLoad.expiredDropped > 0 {
                LabeledContent("Expired, ignored", value: "\(model.hazardLoad.expiredDropped)")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.hazardLoad.problems, id: \.self) { problem in
                Label(problem, systemImage: "xmark.octagon.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            LabeledContent("Permission", value: model.location.statusDescription)
                .font(.footnote)
            switch model.location.authorizationStatus {
            case .notDetermined, .authorizedWhenInUse:
                Button("Allow location access (Always)") {
                    model.location.requestAuthorization()
                }
                if model.location.authorizationStatus == .authorizedWhenInUse {
                    openSettingsButton
                }
            case .denied, .restricted:
                openSettingsButton
            default:
                if model.location.accuracyAuthorization != .fullAccuracy {
                    openSettingsButton
                }
            }
        }
    }

    private var openSettingsButton: some View {
        Button("Open iOS Settings for this app") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private var pendingSection: some View {
        Section {
            NavigationLink {
                PendingReportsView()
            } label: {
                Label("\(model.pendingReports.count) report\(model.pendingReports.count == 1 ? "" : "s") to categorise", systemImage: "hand.tap.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var recoveredSection: some View {
        Section {
            Label("\(model.recoveredOnLaunch.count) ride\(model.recoveredOnLaunch.count == 1 ? " was" : "s were") not stopped cleanly and \(model.recoveredOnLaunch.count == 1 ? "has" : "have") been recovered. Check the diagnostics in the ride log.", systemImage: "arrow.counterclockwise.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private var ridesSection: some View {
        Section("Rides") {
            NavigationLink {
                RideListView()
            } label: {
                LabeledContent("Previous rides", value: "\(model.rides.count)")
            }
            if let last = model.rides.first {
                NavigationLink {
                    PostRideView(entry: last, showsDone: false)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last ride: \(Format.dateTime.string(from: last.startedAt))")
                        Text("\(last.summary.alertsFired) alerts · \(last.summary.reports) reports · \(Format.meters(last.summary.distanceMeters))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
