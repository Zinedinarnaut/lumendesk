import SwiftUI

struct SettingsRootView: View {
    private enum AppPage: String, CaseIterable, Identifiable {
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

        var symbolName: String {
            switch self {
            case .studio: return "display.2"
            case .marketplace: return "storefront"
            case .githubPacks: return "shippingbox"
            }
        }
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var engine: WallpaperEngine

    @State private var selectedPage: AppPage = .studio
    @State private var selectedDisplayID: UInt32?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                Section("Pages") {
                    ForEach(AppPage.allCases) { page in
                        Label(page.label, systemImage: page.symbolName)
                            .tag(page)
                    }
                }
            }
            .navigationTitle("LumenDesk")
        } detail: {
            switch selectedPage {
            case .studio:
                studioPage
            case .marketplace:
                marketplacePage
            case .githubPacks:
                githubPacksPage
            }
        }
        .onAppear {
            selectFirstDisplayIfNeeded()
        }
        .onChange(of: engine.connectedDisplays) { _, _ in
            selectFirstDisplayIfNeeded()
        }
    }

    private var studioPage: some View {
        HSplitView {
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
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    globalControls

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
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var marketplacePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                displaySelectionPanel(
                    title: "Marketplace Target Display",
                    subtitle: "Choose which display receives wallpapers from the marketplace."
                )

                MarketplaceView(selectedDisplay: selectedDisplay)
            }
            .padding(20)
        }
    }

    private var githubPacksPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                displaySelectionPanel(
                    title: "GitHub Packs Target Display",
                    subtitle: "Choose which display receives wallpapers from installed packs."
                )

                GitHubPacksView(selectedDisplay: selectedDisplay)
            }
            .padding(20)
        }
    }

    private func displaySelectionPanel(title: String, subtitle: String) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(engine.connectedDisplays) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                }
                .pickerStyle(.menu)

                if let selectedDisplay {
                    Text("Selected: \(selectedDisplay.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No connected displays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
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

                Text("Music reactive mode is currently disabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
