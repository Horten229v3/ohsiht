import SwiftUI

/// Shown once, on first launch, before anything else.
struct DisclaimerView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Before you ride")
                .font(.largeTitle.bold())
                .padding(.top, 40)

            VStack(alignment: .leading, spacing: 16) {
                Text("This is experimental software built to test an idea. It is not a safety device.")
                Text("Hazard warnings may be wrong, out of date, or missing. Some hazards will never be announced, and some announcements will be for hazards that are not there.")
                Text("You are responsible for riding to the conditions you can see. The app describes what others reported; you decide what to do.")
                Text("Never look at the screen while moving. The only thing to do with the phone on the bike is a single tap, anywhere, to report something you just passed.")
            }
            .font(.body)

            Spacer()

            Button {
                settings.disclaimerAccepted = true
            } label: {
                Text("I understand")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .interactiveDismissDisabled(true)
    }
}
