import AppKit
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let settingsURL: URL
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("LumenDesk", isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        settingsURL = directory.appendingPathComponent("settings.json")
        settings = Self.load(from: settingsURL)

        $settings
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] updated in
                self?.save(updated)
            }
            .store(in: &cancellables)
    }

    func syncDisplays(with screens: [NSScreen]) {
        var updated = settings
        for screen in screens {
            let id = screen.displayID
            let existing = updated.setting(for: id)
            if var existing {
                existing.name = screen.localizedName
                updated.upsertDisplay(existing)
            } else {
                updated.upsertDisplay(.default(for: id, name: screen.localizedName))
            }
        }
        if updated != settings {
            settings = updated
        }
    }

    func setting(for displayID: UInt32, fallbackName: String) -> DisplaySettings {
        if let existing = settings.setting(for: displayID) {
            return existing
        }

        let fallback = DisplaySettings.default(for: displayID, name: fallbackName)
        var updated = settings
        updated.upsertDisplay(fallback)
        settings = updated
        return fallback
    }

    func existingSetting(for displayID: UInt32) -> DisplaySettings? {
        settings.setting(for: displayID)
    }

    func updateDisplay(displayID: UInt32, fallbackName: String, mutate: (inout DisplaySettings) -> Void) {
        var updated = settings
        var display = updated.setting(for: displayID) ?? .default(for: displayID, name: fallbackName)
        mutate(&display)
        updated.upsertDisplay(display)
        if updated != settings {
            settings = updated
        }
    }

    func applyDisplayConfiguration(from sourceDisplayID: UInt32, to targetDisplayIDs: [UInt32]) {
        guard let source = settings.setting(for: sourceDisplayID) else { return }
        var updated = settings
        for id in targetDisplayIDs where id != sourceDisplayID {
            let existing = updated.setting(for: id) ?? .default(for: id, name: "Display \(id)")
            var clone = source
            clone.name = existing.name
            clone = DisplaySettings(
                id: id,
                name: clone.name,
                source: clone.source,
                scaleMode: clone.scaleMode,
                muted: clone.muted,
                volume: clone.volume,
                playbackRate: clone.playbackRate
            )
            updated.upsertDisplay(clone)
        }
        if updated != settings {
            settings = updated
        }
    }

    private static func load(from url: URL) -> AppSettings {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    private func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder.pretty.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            fputs("[LumenDesk] Failed to save settings: \(error)\n", stderr)
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
