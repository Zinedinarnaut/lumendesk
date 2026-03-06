import SwiftUI

@main
struct LumenDeskApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var appleSignInService: AppleSignInService
    @StateObject private var installService: WallpaperInstallService
    @StateObject private var marketplaceService: MarketplaceService
    @StateObject private var gitHubPackService: GitHubPackService
    @StateObject private var audioReactiveService: AudioReactiveService
    @StateObject private var cpuLoadMonitor: CPULoadMonitor
    @StateObject private var engine: WallpaperEngine

    init() {
        let store = SettingsStore()
        let appleSignIn = AppleSignInService()
        let installer = WallpaperInstallService()
        let marketplace = MarketplaceService()
        let audioReactive = AudioReactiveService()
        let cpuMonitor = CPULoadMonitor()
        let githubPacks = GitHubPackService(installService: installer)
        let wallpaperEngine = WallpaperEngine(
            settingsStore: store,
            audioReactiveService: audioReactive,
            cpuLoadMonitor: cpuMonitor
        )

        _settingsStore = StateObject(wrappedValue: store)
        _appleSignInService = StateObject(wrappedValue: appleSignIn)
        _installService = StateObject(wrappedValue: installer)
        _marketplaceService = StateObject(wrappedValue: marketplace)
        _audioReactiveService = StateObject(wrappedValue: audioReactive)
        _cpuLoadMonitor = StateObject(wrappedValue: cpuMonitor)
        _gitHubPackService = StateObject(wrappedValue: githubPacks)
        _engine = StateObject(wrappedValue: wallpaperEngine)

        wallpaperEngine.start()
    }

    var body: some Scene {
        WindowGroup("LumenDesk Studio", id: "studio") {
            AppShellView()
                .environmentObject(settingsStore)
                .environmentObject(appleSignInService)
                .environmentObject(installService)
                .environmentObject(marketplaceService)
                .environmentObject(gitHubPackService)
                .environmentObject(audioReactiveService)
                .environmentObject(cpuLoadMonitor)
                .environmentObject(engine)
        }
        .defaultSize(width: 1180, height: 780)

        MenuBarExtra("LumenDesk", systemImage: "sparkles.rectangle.stack") {
            MenuBarControlsView()
                .environmentObject(settingsStore)
                .environmentObject(engine)
        }
    }
}
