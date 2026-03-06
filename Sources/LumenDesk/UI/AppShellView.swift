import SwiftUI

struct AppShellView: View {
    @State private var startupPhase: StartupPhase = .splash
    @State private var didScheduleTransition = false

    var body: some View {
        ZStack {
            SettingsRootView()
                .opacity(startupPhase == .ready ? 1 : 0)
                .blur(radius: startupPhase == .ready ? 0 : 10)
                .allowsHitTesting(startupPhase == .ready)

            if startupPhase != .ready {
                LumenSplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .onAppear {
            scheduleTransitionIfNeeded()
        }
    }

    private func scheduleTransitionIfNeeded() {
        guard !didScheduleTransition else { return }
        didScheduleTransition = true

        Task {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            await MainActor.run {
                startupPhase = .finishing
                withAnimation(.easeInOut(duration: 0.45)) {
                    startupPhase = .ready
                }
            }
        }
    }
}

private enum StartupPhase {
    case splash
    case finishing
    case ready
}

private struct LumenSplashView: View {
    @State private var glowPulse = false
    @State private var iconSpin = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#060913"), Color(hex: "#0B1736"), Color(hex: "#1A1F3D")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Color(hex: "#3B82F6").opacity(glowPulse ? 0.45 : 0.15), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: glowPulse ? 420 : 260
                )
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 104, height: 104)
                        .blur(radius: glowPulse ? 18 : 10)

                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#7DD3FC"), Color(hex: "#60A5FA"), Color(hex: "#FDE68A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(iconSpin ? 6 : -6))
                }

                Text("LumenDesk")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Crafting live wallpapers for your desktop")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.78))

                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(.top, 6)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                iconSpin = true
            }
        }
    }
}
