import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DisplayEditorView: View {
    let display: DisplayDescriptor
    let applyToAll: () -> Void

    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        let current = settingsStore.existingSetting(for: display.id) ?? .default(for: display.id, name: display.name)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name)
                        .font(.title2.weight(.semibold))
                    Text(display.sizeDescription)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply To All Displays", action: applyToAll)
            }

            GroupBox("Source") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Type", selection: sourceKindBinding) {
                        ForEach(SourceKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch current.source {
                    case .gradient(let presetID):
                        Picker("Preset", selection: gradientPresetBinding(defaultID: presetID)) {
                            ForEach(GradientPreset.all) { preset in
                                Text(preset.title).tag(preset.id)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach(GradientPreset.preset(withID: presetID).hexColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                            }
                        }
                    case .shader(let presetID):
                        Picker("Metal Preset", selection: shaderPresetBinding(defaultID: presetID)) {
                            ForEach(ShaderPreset.all) { preset in
                                Text(preset.title).tag(preset.id)
                            }
                        }

                        HStack {
                            Text("Animation Speed")
                            Slider(value: playbackRateBinding, in: 0.25...3.0, step: 0.05)
                            Text(String(format: "%.2fx", current.playbackRate))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    case .video(let path):
                        Text(path.isEmpty ? "No file selected" : path)
                            .font(.callout)
                            .foregroundStyle(path.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)

                        HStack {
                            Button("Choose Video") {
                                pickVideoFile()
                            }
                            Button("Clear") {
                                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                                    setting.source = .gradient(presetID: GradientPreset.fallback.id)
                                }
                            }
                        }
                    case .web(let url):
                        TextField(
                            "URL (https://...)",
                            text: webURLBinding(defaultValue: url),
                            prompt: Text("https://example.com")
                        )
                        .textFieldStyle(.roundedBorder)

                        Text("Tip: best results come from pages designed for animation loops.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Playback") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Scale", selection: scaleModeBinding) {
                        ForEach(ScaleMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if current.source.kind == .video {
                        Toggle("Mute audio", isOn: mutedBinding)

                        HStack {
                            Text("Volume")
                            Slider(value: volumeBinding, in: 0...1)
                            Text("\(Int((current.volume * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Speed")
                            Slider(value: playbackRateBinding, in: 0.25...2.0, step: 0.05)
                            Text(String(format: "%.2fx", current.playbackRate))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
    }

    private var sourceKindBinding: Binding<SourceKind> {
        Binding(
            get: {
                let setting = settingsStore.existingSetting(for: display.id) ?? .default(for: display.id, name: display.name)
                return setting.source.kind
            },
            set: { newKind in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    switch (newKind, setting.source) {
                    case (.gradient, .gradient):
                        return
                    case (.gradient, _):
                        setting.source = .gradient(presetID: GradientPreset.fallback.id)
                    case (.shader, .shader):
                        return
                    case (.shader, _):
                        setting.source = .shader(presetID: ShaderPreset.fallback.id)
                    case (.video, .video):
                        return
                    case (.video, _):
                        setting.source = .video(path: "")
                    case (.web, .web):
                        return
                    case (.web, _):
                        setting.source = .web(url: "https://")
                    }
                }
            }
        )
    }

    private func shaderPresetBinding(defaultID: String) -> Binding<String> {
        Binding(
            get: {
                guard case .shader(let presetID) = settingsStore.existingSetting(for: display.id)?.source else {
                    return defaultID
                }
                return presetID
            },
            set: { presetID in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.source = .shader(presetID: presetID)
                }
            }
        )
    }

    private func gradientPresetBinding(defaultID: String) -> Binding<String> {
        Binding(
            get: {
                guard case .gradient(let presetID) = settingsStore.existingSetting(for: display.id)?.source else {
                    return defaultID
                }
                return presetID
            },
            set: { presetID in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.source = .gradient(presetID: presetID)
                }
            }
        )
    }

    private func webURLBinding(defaultValue: String) -> Binding<String> {
        Binding(
            get: {
                guard case .web(let url) = settingsStore.existingSetting(for: display.id)?.source else {
                    return defaultValue
                }
                return url
            },
            set: { url in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.source = .web(url: url)
                }
            }
        )
    }

    private var scaleModeBinding: Binding<ScaleMode> {
        Binding(
            get: {
                settingsStore.existingSetting(for: display.id)?.scaleMode ?? .fill
            },
            set: { newValue in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.scaleMode = newValue
                }
            }
        )
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: {
                settingsStore.existingSetting(for: display.id)?.muted ?? true
            },
            set: { newValue in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.muted = newValue
                }
            }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: {
                settingsStore.existingSetting(for: display.id)?.volume ?? 0
            },
            set: { newValue in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.volume = newValue
                }
            }
        )
    }

    private var playbackRateBinding: Binding<Double> {
        Binding(
            get: {
                settingsStore.existingSetting(for: display.id)?.playbackRate ?? 1
            },
            set: { newValue in
                settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                    setting.playbackRate = newValue
                }
            }
        )
    }

    private func pickVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
            setting.source = .video(path: selectedURL.path)
        }
    }
}
