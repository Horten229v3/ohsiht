import SwiftUI

/// The whole screen is one tap target. Nothing on it needs reading while moving.
/// High contrast, heavy type, no thin fonts, no gestures other than tap — plus a
/// hold-to-end bar at the bottom that is only meant to be used at a standstill.
struct RidingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        RidingContent(session: model.session)
    }
}

private struct RidingContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: RideSession
    @State private var isHolding = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text(speedText)
                    .font(.system(size: 150, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Text("km/h")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                Spacer()

                Text("\(session.hazardCount) hazards")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
                    .padding(.bottom, 40)

                Spacer()

                holdToEndBar
            }
            .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.reportTap()
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var speedText: String {
        guard let kmh = session.displaySpeedKmh else { return "—" }
        return String(format: "%.0f", kmh)
    }

    private var holdToEndBar: some View {
        Text(isHolding ? "KEEP HOLDING…" : "HOLD TO END RIDE")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(isHolding ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(isHolding ? Color.white : Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 24)
            .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 60) {
                isHolding = false
                model.stopRide()
            } onPressingChanged: { pressing in
                isHolding = pressing
            }
    }
}
