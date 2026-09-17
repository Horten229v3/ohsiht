import SwiftUI

@main
struct MotoHazardAlertApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settingsStore)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            switch model.screen {
            case .home:
                HomeView()
            case .riding:
                RidingView()
            case .postRide(let entry):
                NavigationStack {
                    PostRideView(entry: entry, showsDone: true)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !settings.disclaimerAccepted },
            set: { _ in }
        )) {
            DisclaimerView()
        }
    }
}
