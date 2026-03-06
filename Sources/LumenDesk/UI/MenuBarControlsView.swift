import AppKit
import SwiftUI

struct MenuBarControlsView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: WallpaperEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LumenDesk")
                .font(.headline)

            Text(engine.pauseReason.description)
                .foregroundStyle(engine.isPaused ? .orange : .green)

            Divider()

            Button("Open Studio") {
                openStudio()
            }

            Button(engine.isPaused ? "Resume Wallpapers" : "Pause Wallpapers") {
                engine.toggleManualPause()
            }

            Toggle("Pause On Battery", isOn: pauseBatteryBinding)
            Toggle("Pause On Fullscreen", isOn: pauseFullscreenBinding)
            Toggle("Music Reactive", isOn: musicReactiveBinding)

            Divider()

            Text("Target FPS: \(settingsStore.settings.frameRateLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Effective FPS: \(engine.effectiveFrameRateLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: frameRateBinding, in: 5...120, step: 1)
                .frame(width: 220)
        }
        .padding(12)
        .frame(width: 250)
    }

    private var pauseBatteryBinding: Binding<Bool> {
        globalBinding(\.pauseOnBattery)
    }

    private var pauseFullscreenBinding: Binding<Bool> {
        globalBinding(\.pauseOnFullscreenApp)
    }

    private var frameRateBinding: Binding<Double> {
        Binding(
            get: { Double(settingsStore.settings.frameRateLimit) },
            set: { newValue in
                var updated = settingsStore.settings
                updated.frameRateLimit = Int(newValue.rounded())
                settingsStore.settings = updated
            }
        )
    }

    private var musicReactiveBinding: Binding<Bool> {
        globalBinding(\.musicReactiveEnabled)
    }

    private func globalBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = settingsStore.settings
                updated[keyPath: keyPath] = newValue
                settingsStore.settings = updated
            }
        )
    }

    private func openStudio() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "studio")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApplication.shared.windows.first(where: { $0.title == "LumenDesk Studio" }) else {
                return
            }

            let isVisibleOnAnyScreen = NSScreen.screens
                .map(\.visibleFrame)
                .contains(where: { $0.intersects(window.frame) })

            if !isVisibleOnAnyScreen, let screen = NSScreen.main ?? NSScreen.screens.first {
                let size = window.frame.size
                let visibleFrame = screen.visibleFrame
                let origin = CGPoint(
                    x: visibleFrame.midX - (size.width / 2),
                    y: visibleFrame.midY - (size.height / 2)
                )
                window.setFrameOrigin(origin)
            }

            window.makeKeyAndOrderFront(nil)
        }
    }
}
