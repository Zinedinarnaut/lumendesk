import SwiftUI

struct AnimatedGradientWallpaper: View {
    let preset: GradientPreset
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            GeometryReader { proxy in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let colors = preset.hexColors.map(Color.init(hex:))

                ZStack {
                    LinearGradient(
                        colors: colors,
                        startPoint: UnitPoint(
                            x: 0.5 + 0.3 * cos(t * 0.05),
                            y: 0.5 + 0.3 * sin(t * 0.07)
                        ),
                        endPoint: UnitPoint(
                            x: 0.5 + 0.3 * sin(t * 0.04),
                            y: 0.5 + 0.3 * cos(t * 0.06)
                        )
                    )

                    ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                        let phase = t * (0.08 + Double(index) * 0.03)
                        Circle()
                            .fill(color.opacity(0.45))
                            .frame(width: proxy.size.width * 0.8, height: proxy.size.height * 0.8)
                            .position(
                                x: proxy.size.width * (0.5 + 0.35 * sin(phase + Double(index))),
                                y: proxy.size.height * (0.5 + 0.35 * cos(phase * 1.2 + Double(index)))
                            )
                            .blur(radius: 120)
                    }
                }
                .compositingGroup()
                .saturation(1.15)
            }
        }
    }
}
