import SwiftUI

struct GitHubPacksView: View {
    let selectedDisplay: DisplayDescriptor?

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var gitHubPackService: GitHubPackService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("GitHub Wallpaper Packs") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("GitHub search query", text: githubQueryBinding)
                            .textFieldStyle(.roundedBorder)
                        Button("Search") {
                            Task {
                                await gitHubPackService.search(query: settingsStore.settings.githubPackQuery)
                            }
                        }
                        .disabled(gitHubPackService.isLoading)
                    }

                    if let status = gitHubPackService.statusMessage, !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    List(gitHubPackService.searchResults, id: \.id) { repository in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(repository.fullName)
                                    .font(.headline)
                                Spacer()
                                Text("★ \(repository.stars)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !repository.summary.isEmpty {
                                Text(repository.summary)
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }

                            HStack {
                                if let url = URL(string: repository.htmlURL) {
                                    Link("Open", destination: url)
                                }
                                Button("Install") {
                                    Task {
                                        await gitHubPackService.install(repository)
                                    }
                                }
                                .disabled(gitHubPackService.isLoading)
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 180, maxHeight: 280)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Installed Packs") {
                VStack(alignment: .leading, spacing: 10) {
                    if gitHubPackService.installedPacks.isEmpty {
                        Text("No installed packs yet")
                            .foregroundStyle(.secondary)
                    } else {
                        List(gitHubPackService.installedPacks, id: \.id) { pack in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pack.name)
                                    .font(.headline)
                                Text(pack.sourceRepository)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if pack.wallpapers.isEmpty {
                                    Text("Pack contains no recognized wallpapers")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(pack.wallpapers, id: \.id) { wallpaper in
                                        HStack {
                                            Text(wallpaper.title)
                                            Spacer()
                                            Button("Apply") {
                                                apply(wallpaper, to: selectedDisplay)
                                            }
                                            .disabled(selectedDisplay == nil)
                                        }
                                        .font(.callout)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 180, maxHeight: 320)
                    }

                    Button("Refresh Installed Packs") {
                        gitHubPackService.reloadInstalledPacks()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            gitHubPackService.reloadInstalledPacks()
            if gitHubPackService.searchResults.isEmpty {
                Task {
                    await gitHubPackService.search(query: settingsStore.settings.githubPackQuery)
                }
            }
        }
    }

    private var githubQueryBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.githubPackQuery },
            set: { newValue in
                var updated = settingsStore.settings
                updated.githubPackQuery = newValue
                settingsStore.settings = updated
            }
        )
    }

    private func apply(_ wallpaper: InstalledPackWallpaper, to display: DisplayDescriptor?) {
        guard let display else { return }
        settingsStore.updateDisplay(displayID: display.id, fallbackName: display.name) { setting in
            setting.source = wallpaper.source
        }
    }
}
