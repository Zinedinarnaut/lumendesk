import AppKit
import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

struct MarketplaceView: View {
    let selectedDisplay: DisplayDescriptor?

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appleSignInService: AppleSignInService
    @EnvironmentObject private var marketplaceService: MarketplaceService
    @EnvironmentObject private var installService: WallpaperInstallService

    @State private var uploadInput = MarketplaceUploadInput.empty
    @State private var installingIDs: Set<String> = []
    @State private var localStatusMessage: String?
    @State private var searchQuery = ""
    @State private var selectedKindFilter: CommunityWallpaperKind?
    @State private var selectedSort: MarketplaceSortOption = .featured
    @State private var previewItem: MarketplaceWallpaper?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroSection
            accountSection
            browseSection
            uploadSection
        }
        .sheet(item: $previewItem) { item in
            MarketplacePreviewSheet(
                item: item,
                canApply: selectedDisplay != nil,
                isInstalling: installingIDs.contains(item.id),
                onApply: {
                    install(item)
                }
            )
            .frame(minWidth: 760, minHeight: 620)
        }
        .onAppear {
            if marketplaceService.wallpapers.isEmpty {
                refreshMarketplace()
            }
        }
    }

    private var heroSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Marketplace")
                    .font(.largeTitle.weight(.bold))

                Text("Browse animated wallpapers from the community, preview them, and apply to any connected display.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    statPill(label: "Loaded", value: "\(marketplaceService.wallpapers.count)")
                    statPill(label: "Catalog", value: "\(marketplaceService.totalAvailable)")
                    statPill(label: "Display", value: selectedDisplay?.name ?? "None")
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var accountSection: some View {
        GroupBox("Marketplace Account") {
            VStack(alignment: .leading, spacing: 10) {
                if let session = appleSignInService.session {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in with Apple")
                                .font(.headline)
                            Text(displayName(for: session))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Sign Out") {
                            appleSignInService.signOut()
                        }
                    }
                } else {
                    SignInWithAppleButton(
                        .continue,
                        onRequest: appleSignInService.configureAppleIDRequest,
                        onCompletion: appleSignInService.handleAuthorization
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(width: 260, height: 34)

                    Text("Use Apple login for authenticated uploads and creator identity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let status = appleSignInService.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var browseSection: some View {
        GroupBox("Browse Marketplace") {
            VStack(alignment: .leading, spacing: 12) {
                endpointControls
                filtersRow

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

                if marketplaceService.isLoading && displayedWallpapers.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading marketplace wallpapers…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if displayedWallpapers.isEmpty, !marketplaceService.isLoading {
                    ContentUnavailableView(
                        "No Wallpapers Found",
                        systemImage: "sparkles.tv",
                        description: Text("Try adjusting search filters or endpoint settings.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                            ForEach(displayedWallpapers) { item in
                                MarketplaceCardView(
                                    item: item,
                                    isInstalling: installingIDs.contains(item.id),
                                    canApply: selectedDisplay != nil,
                                    onPreview: {
                                        previewItem = item
                                    },
                                    onApply: {
                                        install(item)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(minHeight: 320, idealHeight: 420, maxHeight: 520)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var endpointControls: some View {
        HStack(spacing: 10) {
            TextField("Marketplace endpoint", text: marketplaceEndpointBinding)
                .textFieldStyle(.roundedBorder)

            Button("Refresh") {
                refreshMarketplace()
            }
            .disabled(marketplaceService.isLoading)

            if marketplaceService.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }

    private var filtersRow: some View {
        HStack(spacing: 10) {
            TextField("Search title, author, tags", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    refreshMarketplace()
                }

            Picker("Type", selection: $selectedKindFilter) {
                Text("All Types").tag(Optional<CommunityWallpaperKind>.none)
                ForEach(CommunityWallpaperKind.allCases) { kind in
                    Text(kind.label).tag(Optional(kind))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .onChange(of: selectedKindFilter) { _, _ in
                refreshMarketplace()
            }

            Picker("Sort", selection: $selectedSort) {
                ForEach(MarketplaceSortOption.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 270)
            .onChange(of: selectedSort) { _, _ in
                refreshMarketplace()
            }
        }
    }

    private var uploadSection: some View {
        GroupBox("Publish Wallpaper") {
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

                    TextField("Preview URL (optional)", text: $uploadInput.previewURL, prompt: Text("https://cdn.example.com/preview.jpg"))
                case .web:
                    TextField("Web URL", text: $uploadInput.sourceValue, prompt: Text("https://example.com/canvas"))
                    TextField("Preview URL (optional)", text: $uploadInput.previewURL, prompt: Text("https://cdn.example.com/preview.jpg"))
                case .gradient:
                    TextField("Gradient preset id", text: $uploadInput.sourceValue, prompt: Text(GradientPreset.fallback.id))
                case .shader:
                    TextField("Shader preset id", text: $uploadInput.sourceValue, prompt: Text(ShaderPreset.fallback.id))
                }

                HStack {
                    TextField("Tags (comma separated)", text: $uploadInput.tags)
                    TextField("Accent color", text: $uploadInput.accentColor, prompt: Text("#4A90E2"))
                        .frame(width: 160)
                }

                TextField("Thumbnail URL (optional)", text: $uploadInput.thumbnailURL)

                HStack {
                    Button("Upload") {
                        Task {
                            await marketplaceService.upload(
                                endpoint: settingsStore.settings.marketplaceEndpoint,
                                input: sanitizedUploadInput(),
                                authToken: appleSignInService.authToken,
                                appleUserID: appleSignInService.userID
                            )
                            refreshMarketplace()
                        }
                    }
                    .disabled(!canUpload)

                    if let status = marketplaceService.statusMessage, !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !appleSignInService.isSignedIn {
                    Text("Sign in with Apple to upload wallpapers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
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

    private var displayedWallpapers: [MarketplaceWallpaper] {
        var items = marketplaceService.wallpapers

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            let lower = trimmedQuery.lowercased()
            items = items.filter { item in
                item.title.lowercased().contains(lower)
                    || item.author.lowercased().contains(lower)
                    || (item.summary?.lowercased().contains(lower) ?? false)
                    || item.tags.contains(where: { $0.lowercased().contains(lower) })
            }
        }

        if let selectedKindFilter {
            items = items.filter { $0.kind == selectedKindFilter }
        }

        switch selectedSort {
        case .featured:
            items.sort {
                if $0.featured != $1.featured {
                    return $0.featured && !$1.featured
                }
                if $0.installs != $1.installs {
                    return $0.installs > $1.installs
                }
                return createdDate(for: $0) > createdDate(for: $1)
            }
        case .popular:
            items.sort {
                if $0.installs != $1.installs {
                    return $0.installs > $1.installs
                }
                if $0.downloads != $1.downloads {
                    return $0.downloads > $1.downloads
                }
                return createdDate(for: $0) > createdDate(for: $1)
            }
        case .latest:
            items.sort {
                createdDate(for: $0) > createdDate(for: $1)
            }
        }

        return items
    }

    private func createdDate(for item: MarketplaceWallpaper) -> Date {
        guard let raw = item.createdAt else {
            return .distantPast
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }

        return .distantPast
    }

    private var canUpload: Bool {
        guard appleSignInService.isSignedIn else { return false }

        let hasBasic = !uploadInput.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !uploadInput.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard hasBasic else { return false }

        switch uploadInput.kind {
        case .video:
            return uploadInput.fileURL != nil || !uploadInput.sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .web, .gradient, .shader:
            return !uploadInput.sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func displayName(for session: AppleSignInService.Session) -> String {
        if let fullName = session.fullName, !fullName.isEmpty {
            return fullName
        }

        if let email = session.email, !email.isEmpty {
            return email
        }

        let shortID = session.userID.count > 12 ? "\(session.userID.prefix(12))…" : session.userID
        return "Apple user \(shortID)"
    }

    private func refreshMarketplace() {
        Task {
            await marketplaceService.fetch(
                endpoint: settingsStore.settings.marketplaceEndpoint,
                authToken: appleSignInService.authToken,
                appleUserID: appleSignInService.userID,
                query: searchQuery,
                kind: selectedKindFilter,
                sort: selectedSort,
                perPage: 120
            )
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

                await marketplaceService.trackInstall(
                    endpoint: settingsStore.settings.marketplaceEndpoint,
                    wallpaperID: item.id,
                    authToken: appleSignInService.authToken,
                    appleUserID: appleSignInService.userID
                )
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
        copy.tags = copy.tags.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.thumbnailURL = copy.thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.previewURL = copy.previewURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.accentColor = copy.accentColor.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct MarketplaceCardView: View {
    let item: MarketplaceWallpaper
    let isInstalling: Bool
    let canApply: Bool
    let onPreview: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewSurface

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("by \(item.author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    kindBadge
                }

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(minHeight: 36, alignment: .topLeading)
                }

                HStack(spacing: 8) {
                    Label("\(item.installs)", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.featured {
                        Label("Featured", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                if !item.tags.isEmpty {
                    Text(item.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Button("Preview", action: onPreview)
                        .buttonStyle(.bordered)

                    Button("Apply", action: onApply)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canApply || isInstalling)

                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var kindBadge: some View {
        Text(item.kind.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private var previewSurface: some View {
        ZStack(alignment: .topLeading) {
            if let raw = item.bestPreviewURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        previewPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        previewPlaceholder
                    @unknown default:
                        previewPlaceholder
                    }
                }
            } else {
                previewPlaceholder
            }

            if item.featured {
                Label("Featured", systemImage: "star.fill")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .frame(height: 142)
        .clipped()
    }

    private var previewPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.85), accentColor.opacity(0.35), Color.black.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                Image(systemName: kindIcon)
                    .font(.system(size: 24, weight: .semibold))
                Text(item.kind.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var accentColor: Color {
        if let accent = item.accentColor, !accent.isEmpty {
            return Color(hex: accent)
        }

        switch item.kind {
        case .video:
            return Color(hex: "#2563EB")
        case .web:
            return Color(hex: "#0EA5E9")
        case .gradient:
            return Color(hex: "#10B981")
        case .shader:
            return Color(hex: "#9333EA")
        }
    }

    private var kindIcon: String {
        switch item.kind {
        case .video:
            return "play.rectangle.fill"
        case .web:
            return "globe"
        case .gradient:
            return "circle.lefthalf.filled"
        case .shader:
            return "sparkles"
        }
    }
}

private struct MarketplacePreviewSheet: View {
    let item: MarketplaceWallpaper
    let canApply: Bool
    let isInstalling: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title)
                .font(.title2.weight(.bold))

            Text("by \(item.author)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            previewView
                .frame(maxWidth: .infinity)
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(item.kind.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())

                Label("\(item.installs)", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.featured {
                    Label("Featured", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Spacer()

                Button("Apply To Selected Display", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply || isInstalling)

                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var previewView: some View {
        switch item.kind {
        case .video:
            if let videoURL = url(from: item.downloadURL ?? item.sourceValue ?? item.bestPreviewURL) {
                VideoWallpaperView(
                    url: videoURL,
                    isPaused: false,
                    muted: true,
                    volume: 0,
                    playbackRate: 1,
                    scaleMode: .fill
                )
            } else {
                fallbackPreview
            }
        case .web:
            if let webURL = url(from: item.sourceValue ?? item.bestPreviewURL) {
                WebWallpaperView(url: webURL, isPaused: false, frameRateLimit: 30)
            } else {
                fallbackPreview
            }
        case .gradient:
            AnimatedGradientWallpaper(
                preset: GradientPreset.preset(withID: item.sourceValue ?? GradientPreset.fallback.id),
                paused: false
            )
        case .shader:
            MetalShaderWallpaperView(
                preset: ShaderPreset.preset(withID: item.sourceValue ?? ShaderPreset.fallback.id),
                isPaused: false,
                frameRateLimit: 30,
                playbackRate: 1,
                reactiveLevel: 0,
                reactiveBeatPulse: 0,
                musicReactiveEnabled: false
            )
        }
    }

    private var fallbackPreview: some View {
        ZStack {
            LinearGradient(
                colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.1), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text("No live preview available")
                .foregroundStyle(.secondary)
        }
    }

    private func url(from value: String?) -> URL? {
        guard let value else { return nil }
        return URL(string: value)
    }
}
