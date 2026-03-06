import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class WallpaperEngine: ObservableObject {
    enum PauseReason: Equatable {
        case none
        case manual
        case battery
        case fullscreen

        var description: String {
            switch self {
            case .none: return "Running"
            case .manual: return "Paused manually"
            case .battery: return "Paused on battery"
            case .fullscreen: return "Paused for fullscreen app"
            }
        }
    }

    @Published private(set) var connectedDisplays: [DisplayDescriptor] = []
    @Published private(set) var pauseReason: PauseReason = .none
    @Published private(set) var effectiveFrameRateLimit: Int
    @Published private(set) var cpuUsagePercent: Double = 0
    @Published private(set) var throttleFactor: Double = 1.0
    @Published private(set) var reactiveLevel: Double = 0
    @Published private(set) var reactiveBeatPulse: Double = 0

    let settingsStore: SettingsStore
    let audioReactiveService: AudioReactiveService
    let cpuLoadMonitor: CPULoadMonitor

    private var windows: [UInt32: WallpaperWindowController] = [:]
    private var screenObservers: [NSObjectProtocol] = []
    private var batteryTimer: Timer?
    private var fullscreenTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let batteryMonitor = BatteryMonitor()
    private let fullscreenDetector = FullscreenDetector()
    private let excludedWindowOwners: Set<String> = [
        "Finder",
        "Dock",
        "Window Server",
        "Notification Center",
        "Control Center",
        "LumenDesk"
    ]

    private var hasStarted = false
    private var manualPauseEnabled = false
    private var batteryPauseActive = false
    private var fullscreenPauseActive = false

    init(
        settingsStore: SettingsStore,
        audioReactiveService: AudioReactiveService,
        cpuLoadMonitor: CPULoadMonitor
    ) {
        self.settingsStore = settingsStore
        self.audioReactiveService = audioReactiveService
        self.cpuLoadMonitor = cpuLoadMonitor
        effectiveFrameRateLimit = settingsStore.settings.frameRateLimit

        bindSettings()
        bindServices()
        recalculateEffectiveFrameRate()
    }

    var isPaused: Bool {
        pauseReason != .none
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if settingsStore.settings.musicReactiveEnabled || settingsStore.settings.reactiveSensitivity != 1.0 {
            var updated = settingsStore.settings
            updated.musicReactiveEnabled = false
            updated.reactiveSensitivity = 1.0
            settingsStore.settings = updated
        }

        installScreenObservers()
        refreshDisplays()
        configurePauseMonitors()
        evaluatePauseReason()
        recalculateEffectiveFrameRate()

        cpuLoadMonitor.start()
        audioReactiveService.updateConfiguration(
            enabled: false,
            sensitivity: 1.0
        )

        LoginItemService.sync(enabled: settingsStore.settings.launchAtLogin)
    }

    func handleSettingsUpdated() {
        guard hasStarted else { return }
        refreshDisplays()
        configurePauseMonitors()
        evaluatePauseReason()
        recalculateEffectiveFrameRate()
    }

    func toggleManualPause() {
        manualPauseEnabled.toggle()
        evaluatePauseReason()
    }

    func applySelectedDisplayToAll(_ sourceDisplayID: UInt32) {
        let targets = connectedDisplays.map(\.id)
        settingsStore.applyDisplayConfiguration(from: sourceDisplayID, to: targets)
    }

    private func bindSettings() {
        settingsStore.$settings
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleSettingsUpdated()
                }
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.launchAtLogin)
            .removeDuplicates()
            .dropFirst()
            .sink { enabled in
                Task { @MainActor in
                    LoginItemService.sync(enabled: enabled)
                }
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.frameRateLimit)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.recalculateEffectiveFrameRate()
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.gpuAutoThrottleEnabled)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.recalculateEffectiveFrameRate()
            }
            .store(in: &cancellables)
    }

    private func bindServices() {
        cpuLoadMonitor.$systemUsage
            .sink { [weak self] usage in
                self?.cpuUsagePercent = usage * 100.0
            }
            .store(in: &cancellables)

        cpuLoadMonitor.$throttleFactor
            .sink { [weak self] factor in
                self?.throttleFactor = factor
                self?.recalculateEffectiveFrameRate()
            }
            .store(in: &cancellables)

        audioReactiveService.$level
            .sink { [weak self] level in
                self?.reactiveLevel = level
            }
            .store(in: &cancellables)

        audioReactiveService.$beatPulse
            .sink { [weak self] pulse in
                self?.reactiveBeatPulse = pulse
            }
            .store(in: &cancellables)
    }

    private func recalculateEffectiveFrameRate() {
        let settings = settingsStore.settings
        let baseFPS = max(5, min(settings.frameRateLimit, 120))
        let factor = settings.gpuAutoThrottleEnabled ? throttleFactor : 1.0
        let adjusted = max(8, Int((Double(baseFPS) * factor).rounded(.toNearestOrAwayFromZero)))

        if effectiveFrameRateLimit != adjusted {
            effectiveFrameRateLimit = adjusted
        }
    }

    private func installScreenObservers() {
        let center = NotificationCenter.default

        let screenObserver = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
            }
        }

        let activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFullscreenState()
            }
        }

        screenObservers = [screenObserver, activeSpaceObserver]
    }

    private func refreshDisplays() {
        let screens = NSScreen.screens.sorted { lhs, rhs in
            if lhs.frame.minX == rhs.frame.minX {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }

        settingsStore.syncDisplays(with: screens)

        connectedDisplays = screens.map(\.descriptor)
        let activeIDs = Set(connectedDisplays.map(\.id))

        for screen in screens {
            let id = screen.displayID
            let rootView = WallpaperDisplayView(displayID: id, fallbackName: screen.localizedName)
                .environmentObject(settingsStore)
                .environmentObject(self)

            if let controller = windows[id] {
                controller.updateFrame(for: screen)
                controller.updateRootView(rootView)
            } else {
                windows[id] = WallpaperWindowController(
                    screen: screen,
                    displayID: id,
                    rootView: rootView
                )
            }
        }

        let obsoleteIDs = windows.keys.filter { !activeIDs.contains($0) }
        for id in obsoleteIDs {
            windows[id]?.close()
            windows.removeValue(forKey: id)
        }
    }

    private func configurePauseMonitors() {
        let settings = settingsStore.settings

        if settings.pauseOnBattery {
            startBatteryMonitorIfNeeded()
            updateBatteryState()
        } else {
            batteryTimer?.invalidate()
            batteryTimer = nil
            batteryPauseActive = false
        }

        if settings.pauseOnFullscreenApp {
            startFullscreenMonitorIfNeeded()
            updateFullscreenState()
        } else {
            fullscreenTimer?.invalidate()
            fullscreenTimer = nil
            fullscreenPauseActive = false
        }
    }

    private func startBatteryMonitorIfNeeded() {
        guard batteryTimer == nil else { return }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryState()
            }
        }
        RunLoop.main.add(batteryTimer!, forMode: .common)
    }

    private func startFullscreenMonitorIfNeeded() {
        guard fullscreenTimer == nil else { return }
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFullscreenState()
            }
        }
        RunLoop.main.add(fullscreenTimer!, forMode: .common)
    }

    private func updateBatteryState() {
        batteryPauseActive = batteryMonitor.isOnBatteryPower()
        evaluatePauseReason()
    }

    private func updateFullscreenState() {
        fullscreenPauseActive = fullscreenDetector.hasLikelyFullscreenForegroundWindow(
            excludingOwners: excludedWindowOwners
        )
        evaluatePauseReason()
    }

    private func evaluatePauseReason() {
        if manualPauseEnabled {
            pauseReason = .manual
            return
        }

        let settings = settingsStore.settings
        if settings.pauseOnBattery && batteryPauseActive {
            pauseReason = .battery
            return
        }

        if settings.pauseOnFullscreenApp && fullscreenPauseActive {
            pauseReason = .fullscreen
            return
        }

        pauseReason = .none
    }
}
