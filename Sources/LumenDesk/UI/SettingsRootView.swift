import SwiftUI

struct SettingsRootView: View {
    private enum DetailPanel: String, CaseIterable, Identifiable {
        case studio
        case marketplace
        case githubPacks

        var id: String { rawValue }

        var label: String {
            switch self {
            case .studio: return "Studio"
            case .marketplace: return "Marketplace"
            case .githubPacks: return "GitHub Packs"
            }
        }
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: WallpaperEngine

    @State private var selectedDisplayID: UInt32?
    @State private var detailPanel: DetailPanel = .studio

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDisplayID) {
                Section("Connected Displays") {
                    ForEach(engine.connectedDisplays) { display in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(display.name)
                                Text(display.sizeDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .tag(display.id)
                    }
                }
            }
            .navigationTitle("LumenDesk")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    globalControls

                    Picker("Panel", selection: $detailPanel) {
                        ForEach(DetailPanel.allCases) { panel in
                            Text(panel.label).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch detailPanel {
                    case .studio:
                        if let display = selectedDisplay {
                            DisplayEditorView(display: display) {
                                engine.applySelectedDisplayToAll(display.id)
                            }
                        } else {
                            ContentUnavailableView(
                                "No Display Selected",
                                systemImage: "display",
                                description: Text("Connect a display to start assigning wallpaper sources.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 300)
                        }
                    case .marketplace:
                        MarketplaceView(selectedDisplay: selectedDisplay)
                    case .githubPacks:
                        GitHubPacksView(selectedDisplay: selectedDisplay)
                    }
                }
                .padding(20)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            selectFirstDisplayIfNeeded()
        }
        .onChange(of: engine.connectedDisplays) { _, _ in
            selectFirstDisplayIfNeeded()
        }
    }

    private var selectedDisplay: DisplayDescriptor? {
        guard let selectedDisplayID else {
            return engine.connectedDisplays.first
        }

        return engine.connectedDisplays.first(where: { $0.id == selectedDisplayID })
    }

    private var globalControls: some View {
        GroupBox("Global Controls") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Engine status")
                    Spacer()
                    Text(engine.pauseReason.description)
                        .foregroundStyle(engine.isPaused ? .orange : .green)
                }

                HStack {
                    Button(engine.isPaused ? "Resume" : "Pause") {
                        engine.toggleManualPause()
                    }

                    Spacer()

                    Text("Displays: \(engine.connectedDisplays.count)")
                        .foregroundStyle(.secondary)
                }

                Toggle("Pause when running on battery", isOn: globalBinding(\.pauseOnBattery))
                Toggle("Pause when a fullscreen app is active", isOn: globalBinding(\.pauseOnFullscreenApp))
                Toggle("Launch at login", isOn: globalBinding(\.launchAtLogin))

                Divider()

                Toggle("Music reactive mode", isOn: globalBinding(\.musicReactiveEnabled))

                HStack {
                    Text("Reactive sensitivity")
                    Slider(value: globalBinding(\.reactiveSensitivity), in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2fx", settingsStore.settings.reactiveSensitivity))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Mic level")
                    ProgressView(value: engine.reactiveLevel)
                    Text("Beat: \(Int(engine.reactiveBeatPulse * 100))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Divider()

                Toggle("Auto GPU throttling on high CPU load", isOn: globalBinding(\.gpuAutoThrottleEnabled))

                HStack {
                    Text("CPU load")
                    Spacer()
                    Text("\(Int(engine.cpuUsagePercent.rounded()))%")
                        .monospacedDigit()
                }

                HStack {
                    Text("Target framerate")
                    Spacer()
                    Stepper(value: frameRateBinding, in: 5...120, step: 1) {
                        Text("\(settingsStore.settings.frameRateLimit) FPS")
                            .monospacedDigit()
                    }
                    .frame(width: 180)
                }

                HStack {
                    Text("Effective framerate")
                    Spacer()
                    Text("\(engine.effectiveFrameRateLimit) FPS")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var frameRateBinding: Binding<Int> {
        globalBinding(\.frameRateLimit)
    }

    private func globalBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: {
                settingsStore.settings[keyPath: keyPath]
            },
            set: { newValue in
                var updated = settingsStore.settings
                updated[keyPath: keyPath] = newValue
                settingsStore.settings = updated
            }
        )
    }

    private func selectFirstDisplayIfNeeded() {
        guard !engine.connectedDisplays.isEmpty else {
            selectedDisplayID = nil
            return
        }

        if let selectedDisplayID,
           engine.connectedDisplays.contains(where: { $0.id == selectedDisplayID }) {
            return
        }

        selectedDisplayID = engine.connectedDisplays.first?.id
    }
}
