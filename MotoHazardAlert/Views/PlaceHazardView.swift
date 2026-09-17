import SwiftUI
import UIKit

/// Test mode: stand at a spot, choose a direction and a category, and a hazard is
/// created at the current GPS position. Then start a ride and approach it.
struct PlaceHazardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Direction: String, CaseIterable, Identifiable {
        case compass = "Compass"
        case any = "All directions"
        var id: String { rawValue }
    }

    @State private var direction: Direction = .compass
    @State private var flipped = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var confirmDeleteAll = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            List {
                positionSection
                directionSection
                placeSection
                if !model.testHazards.isEmpty {
                    existingSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Place test hazard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all \(model.testHazards.count) test hazards?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { model.deleteAllTestHazards() }
            }
        }
        .onAppear { model.location.startPlacementUpdates() }
        .onDisappear { model.location.stopPlacementUpdates() }
    }

    // MARK: Position

    private var fix: TrackPoint? {
        guard let f = model.location.latest, Date().timeIntervalSince(f.timestamp) < 15 else { return nil }
        return f
    }

    private var fixIsGood: Bool {
        guard let f = fix else { return false }
        return f.horizontalAccuracy <= AppModel.maxPlacementAccuracy
    }

    private var positionSection: some View {
        Section("Your position") {
            if let f = fix {
                LabeledContent("GPS accuracy") {
                    Text("±\(Int(f.horizontalAccuracy)) m")
                        .foregroundStyle(fixIsGood ? Color.green : Color.orange)
                        .monospacedDigit()
                }
                LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", f.lat, f.lon))
                    .font(.footnote)
            } else {
                HStack {
                    ProgressView()
                    Text("Waiting for a GPS fix…")
                        .foregroundStyle(.secondary)
                }
            }
            if !fixIsGood {
                Text("Stand still with a clear view of the sky. Placement needs ±\(Int(AppModel.maxPlacementAccuracy)) m or better.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Direction

    /// The heading that will be stored, or nil for all directions.
    private var chosenHeading: Double? {
        guard direction == .compass, let c = model.location.compassHeading else { return nil }
        return flipped ? Geo.normaliseDegrees(c + 180) : c
    }

    private var directionSection: some View {
        Section {
            Picker("Direction", selection: $direction) {
                ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if direction == .compass {
                if let h = chosenHeading {
                    HStack {
                        Image(systemName: "location.north.line.fill")
                            .font(.title)
                            .rotationEffect(.degrees(h))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("\(Int(h.rounded()))° \(compassPoint(h))")
                                .font(.title2.bold())
                                .monospacedDigit()
                            Text(flipped ? "Opposite to where the phone points" : "Where the top of the phone points")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Toggle("Flip 180° (hazard for the other direction)", isOn: $flipped)
                } else {
                    Label("Compass unavailable — move the phone in a figure-8 to calibrate, or use All directions.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Direction of travel")
        } footer: {
            Text(direction == .compass
                 ? "Hold the phone flat or upright with its top pointing the way a rider would travel when the hazard applies. Tolerance is the Settings default (±\(Int(model.settingsStore.settings.defaultHeadingTolerance))°)."
                 : "The hazard alerts for any direction of travel. Good for a pure timing test.")
        }
    }

    // MARK: Place

    private var canPlace: Bool {
        fixIsGood && (direction == .any || chosenHeading != nil)
    }

    private var placeSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(HazardCategory.allCases) { category in
                    Button {
                        place(category)
                    } label: {
                        Text(category.label)
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlace)
                }
            }
            .padding(.vertical, 4)

            if let message {
                Label(message, systemImage: messageIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(messageIsError ? Color.red : Color.green)
            }
        } header: {
            Text("Tap a category to place it here")
        } footer: {
            Text("The hazard uses the category's normal expiry (accident 3 h, cattle/other 7 d, gravel 14 d, surface 90 d). Then close this, start a ride, ride away at least 1 km or turn around, and approach it. Every alert and near-miss ends up in the ride log as usual.")
        }
    }

    private func place(_ category: HazardCategory) {
        do {
            let h = try model.placeTestHazard(category: category, heading: chosenHeading)
            let dir = h.heading.map { "heading \(Int($0.rounded()))°" } ?? "all directions"
            message = "Placed \(category.label), \(dir), GPS ±\(Int(fix?.horizontalAccuracy ?? 0)) m."
            messageIsError = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            message = error.localizedDescription
            messageIsError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: Existing

    private var existingSection: some View {
        Section {
            ForEach(model.testHazards) { h in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(h.category.label) · \(h.heading.map { "\(Int($0.rounded()))° \(compassPoint($0))" } ?? "all directions")")
                            .font(.headline)
                        Text(Format.dateTime.string(from: h.createdAt))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let f = fix {
                        Text(Format.meters(Geo.distanceMeters(lat1: f.lat, lon1: f.lon, lat2: h.lat, lon2: h.lon)))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { model.deleteTestHazard(model.testHazards[i]) }
            }
            Button("Delete all test hazards", role: .destructive) { confirmDeleteAll = true }
        } header: {
            Text("Test hazards (\(model.testHazards.count))")
        } footer: {
            Text("Swipe left to delete one. Distances are from where you stand now.")
        }
    }

    private func compassPoint(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int((Geo.normaliseDegrees(degrees) + 22.5) / 45) % 8
        return names[i]
    }
}
