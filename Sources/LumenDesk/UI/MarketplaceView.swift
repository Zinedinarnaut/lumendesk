import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MarketplaceView: View {
    let selectedDisplay: DisplayDescriptor?

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var marketplaceService: MarketplaceService
    @EnvironmentObject private var installService: WallpaperInstallService

    @State private var uploadInput = MarketplaceUploadInput.empty
    @State private var installingIDs: Set<String> = []
    @State private var localStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Marketplace") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("Marketplace endpoint", text: marketplaceEndpointBinding)
                            .textFieldStyle(.roundedBorder)
                        Button("Refresh") {
                            Task {
                                await marketplaceService.fetch(endpoint: settingsStore.settings.marketplaceEndpoint)
                            }
                        }
                        .disabled(marketplaceService.isLoading)
                    }

                    if let status = marketplaceService.statusMessage, !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let localStatusMessage, !localStatusMessage.isEmpty {
                        Text(localStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if marketplaceService.wallpapers.isEmpty {
                        Text("No wallpapers loaded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(marketplaceService.wallpapers, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.headline)
                                        Text("by \(item.author)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(item.kind.label)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                }

                                if let summary = item.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Button("Apply To Selected Display") {
                                        install(item)
                                    }
                                    .disabled(selectedDisplay == nil || installingIDs.contains(item.id))

                                    if installingIDs.contains(item.id) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }

                                    Spacer()

                                    if !item.tags.isEmpty {
                                        Text(item.tags.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 220, maxHeight: 320)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Upload Wallpaper") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Title", text: $uploadInput.title)
                        TextField("Author", text: $uploadInput.author)
                    }

                    TextField("Summary", text: $uploadInput.summary)

                    Picker("Type", selection: $uploadInput.kind) {
                        ForEach(CommunityWallpaperKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch uploadInput.kind {
                    case .video:
                        HStack {
                            Text(uploadInput.fileURL?.path ?? "No video selected")
                                .foregroundStyle(uploadInput.fileURL == nil ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose Video") {
                                chooseVideoForUpload()
                            }
                        }
                    case .web:
                        TextField("Web URL", text: $uploadInput.sourceValue, prompt: Text("https://example.com"))
                    case .gradient:
                        TextField("Gradient preset id", text: $uploadInput.sourceValue, prompt: Text(GradientPreset.fallback.id))
                    case .shader:
                        TextField("Shader preset id", text: $uploadInput.sourceValue, prompt: Text(ShaderPreset.fallback.id))
                    }

                    HStack {
                        Button("Upload") {
                            Task {
                                await marketplaceService.upload(
                                    endpoint: settingsStore.settings.marketplaceEndpoint,
                                    input: sanitizedUploadInput()
                                )
                            }
                        }
                        .disabled(!canUpload)

                        if let status = marketplaceService.statusMessage, !status.isEmpty {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            if marketplaceService.wallpapers.isEmpty {
                Task {
                    await marketplaceService.fetch(endpoint: settingsStore.settings.marketplaceEndpoint)
                }
            }
        }
    }

    private var marketplaceEndpointBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.marketplaceEndpoint },
            set: { newValue in
                var updated = settingsStore.settings
                updated.marketplaceEndpoint = newValue
                settingsStore.settings = updated
            }
        )
    }

    private var canUpload: Bool {
        let hasBasic = !uploadInput.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !uploadInput.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard hasBasic else { return false }

        switch uploadInput.kind {
        case .video:
            return uploadInput.fileURL != nil
        case .web, .gradient, .shader:
            return !uploadInput.sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func install(_ item: MarketplaceWallpaper) {
        guard let display = selectedDisplay else { return }
        installingIDs.insert(item.id)

        Task {
            defer {
                Task { @MainActor in
                    installingIDs.remove(item.id)
                }
            }

            do {
                let source = try await buildSource(from: item)
                await MainActor.run {
                    settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
                        setting.source = source
                    }
                    localStatusMessage = "Applied \(item.title) to \(display.name)"
                }
            } catch {
                await MainActor.run {
                    localStatusMessage = "Install failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func buildSource(from item: MarketplaceWallpaper) async throws -> WallpaperSource {
        switch item.kind {
        case .web:
            let value = item.sourceValue ?? item.downloadURL ?? ""
            guard !value.isEmpty else { throw InstallError.invalidURL }
            return .web(url: value)
        case .gradient:
            let id = item.sourceValue ?? GradientPreset.fallback.id
            return .gradient(presetID: id)
        case .shader:
            let id = item.sourceValue ?? ShaderPreset.fallback.id
            return .shader(presetID: id)
        case .video:
            let remote = item.downloadURL ?? item.sourceValue ?? ""
            let localPath = try await installService.installRemoteVideo(urlString: remote, title: item.title)
            return .video(path: localPath)
        }
    }

    private func chooseVideoForUpload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        uploadInput.fileURL = selectedURL
    }

    private func sanitizedUploadInput() -> MarketplaceUploadInput {
        var copy = uploadInput
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.author = copy.author.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.summary = copy.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sourceValue = copy.sourceValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}
