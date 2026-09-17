import SwiftUI

struct RideListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.rides.isEmpty {
                Text("No rides yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.rides) { ride in
                NavigationLink {
                    PostRideView(entry: ride, showsDone: false)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Format.dateTime.string(from: ride.startedAt))
                                .font(.headline)
                            if ride.recovered {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("\(Format.duration(ride.summary.durationSeconds)) · \(Format.meters(ride.summary.distanceMeters)) · \(ride.summary.alertsFired) alerts · \(ride.summary.reports) reports · gap \(Format.seconds(ride.summary.maxGapSeconds))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets {
                    RideStore.deleteRide(model.rides[i])
                }
                model.refresh()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rides")
        .onAppear { model.refresh() }
    }
}
