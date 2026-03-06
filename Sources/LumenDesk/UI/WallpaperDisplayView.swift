import Foundation
import SwiftUI

struct WallpaperDisplayView: View {
    let displayID: UInt32
    let fallbackName: String

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: WallpaperEngine

    var body: some View {
        let config = settingsStore.existingSetting(for: displayID) ?? .default(for: displayID, name: fallbackName)

        ZStack {
            switch config.source {
            case .gradient(let presetID):
                AnimatedGradientWallpaper(
                    preset: GradientPreset.preset(withID: presetID),
                    paused: engine.isPaused
                )
            case .shader(let presetID):
                MetalShaderWallpaperView(
                    preset: ShaderPreset.preset(withID: presetID),
                    isPaused: engine.isPaused,
                    frameRateLimit: engine.effectiveFrameRateLimit,
                    playbackRate: config.playbackRate,
                    reactiveLevel: engine.reactiveLevel,
                    reactiveBeatPulse: engine.reactiveBeatPulse,
                    musicReactiveEnabled: settingsStore.settings.musicReactiveEnabled
                )
            case .video(let path):
                if FileManager.default.fileExists(atPath: path) {
                    VideoWallpaperView(
                        url: URL(fileURLWithPath: path),
                        isPaused: engine.isPaused,
                        muted: config.muted,
                        volume: config.volume,
                        playbackRate: config.playbackRate,
                        scaleMode: config.scaleMode
                    )
                } else {
                    AnimatedGradientWallpaper(
                        preset: .fallback,
                        paused: engine.isPaused
                    )
                }
            case .web(let urlString):
                if let url = normalizeWebURL(urlString) {
                    WebWallpaperView(
                        url: url,
                        isPaused: engine.isPaused,
                        frameRateLimit: engine.effectiveFrameRateLimit
                    )
                } else {
                    AnimatedGradientWallpaper(
                        preset: .fallback,
                        paused: engine.isPaused
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    private func normalizeWebURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }

        return URL(string: "https://\(trimmed)")
    }
}
