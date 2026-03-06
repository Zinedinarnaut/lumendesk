import Foundation

enum SourceKind: String, CaseIterable, Identifiable, Codable {
    case gradient
    case shader
    case video
    case web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gradient: return "Gradient"
        case .shader: return "Metal"
        case .video: return "Video"
        case .web: return "Web"
        }
    }
}

enum ScaleMode: String, CaseIterable, Identifiable, Codable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        }
    }
}

struct GradientPreset: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let hexColors: [String]

    static let all: [GradientPreset] = [
        GradientPreset(id: "aurora", title: "Aurora", hexColors: ["#0B1A3A", "#1D4ED8", "#14B8A6", "#C4F1F9"]),
        GradientPreset(id: "ember", title: "Ember", hexColors: ["#150B0A", "#7C2D12", "#EA580C", "#FDE68A"]),
        GradientPreset(id: "mono", title: "Monochrome", hexColors: ["#111827", "#374151", "#6B7280", "#D1D5DB"]),
        GradientPreset(id: "ocean", title: "Ocean", hexColors: ["#020617", "#0F172A", "#0E7490", "#67E8F9"]),
        GradientPreset(id: "forest", title: "Forest", hexColors: ["#052E16", "#14532D", "#22C55E", "#D9F99D"]),
        GradientPreset(id: "sunset", title: "Sunset", hexColors: ["#2E1065", "#BE185D", "#F97316", "#FDE68A"]),
    ]

    static let fallback = GradientPreset.all[0]

    static func preset(withID id: String) -> GradientPreset {
        all.first(where: { $0.id == id }) ?? fallback
    }
}

struct ShaderPreset: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let styleIndex: UInt32
    let baseSpeed: Double

    static let all: [ShaderPreset] = [
        ShaderPreset(id: "nebula", title: "Nebula Drift", styleIndex: 0, baseSpeed: 1.0),
        ShaderPreset(id: "plasma", title: "Plasma Bloom", styleIndex: 1, baseSpeed: 1.15),
        ShaderPreset(id: "ripple", title: "Liquid Ripple", styleIndex: 2, baseSpeed: 0.85),
        ShaderPreset(id: "grid", title: "Pulse Grid", styleIndex: 3, baseSpeed: 1.05),
        ShaderPreset(id: "vortex", title: "Prism Vortex", styleIndex: 4, baseSpeed: 1.2)
    ]

    static let fallback = ShaderPreset.all[0]

    static func preset(withID id: String) -> ShaderPreset {
        all.first(where: { $0.id == id }) ?? fallback
    }
}

enum WallpaperSource: Equatable, Codable {
    case gradient(presetID: String)
    case shader(presetID: String)
    case video(path: String)
    case web(url: String)

    var kind: SourceKind {
        switch self {
        case .gradient: return .gradient
        case .shader: return .shader
        case .video: return .video
        case .web: return .web
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case presetID
        case path
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SourceKind.self, forKey: .kind)
        switch kind {
        case .gradient:
            let presetID = try container.decode(String.self, forKey: .presetID)
            self = .gradient(presetID: presetID)
        case .shader:
            let presetID = try container.decode(String.self, forKey: .presetID)
            self = .shader(presetID: presetID)
        case .video:
            let path = try container.decode(String.self, forKey: .path)
            self = .video(path: path)
        case .web:
            let url = try container.decode(String.self, forKey: .url)
            self = .web(url: url)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .gradient(let presetID):
            try container.encode(presetID, forKey: .presetID)
        case .shader(let presetID):
            try container.encode(presetID, forKey: .presetID)
        case .video(let path):
            try container.encode(path, forKey: .path)
        case .web(let url):
            try container.encode(url, forKey: .url)
        }
    }
}

struct DisplaySettings: Identifiable, Equatable, Codable {
    let id: UInt32
    var name: String
    var source: WallpaperSource
    var scaleMode: ScaleMode
    var muted: Bool
    var volume: Double
    var playbackRate: Double

    static func `default`(for id: UInt32, name: String) -> DisplaySettings {
        DisplaySettings(
            id: id,
            name: name,
            source: .gradient(presetID: GradientPreset.fallback.id),
            scaleMode: .fill,
            muted: true,
            volume: 0.0,
            playbackRate: 1.0
        )
    }
}

struct AppSettings: Equatable, Codable {
    var frameRateLimit: Int
    var pauseOnBattery: Bool
    var pauseOnFullscreenApp: Bool
    var launchAtLogin: Bool
    var musicReactiveEnabled: Bool
    var reactiveSensitivity: Double
    var gpuAutoThrottleEnabled: Bool
    var marketplaceEndpoint: String
    var githubPackQuery: String
    var displaySettings: [String: DisplaySettings]

    static let `default` = AppSettings(
        frameRateLimit: 30,
        pauseOnBattery: true,
        pauseOnFullscreenApp: true,
        launchAtLogin: false,
        musicReactiveEnabled: false,
        reactiveSensitivity: 1.0,
        gpuAutoThrottleEnabled: true,
        marketplaceEndpoint: "http://localhost:3000",
        githubPackQuery: "topic:lumendesk-wallpaper-pack",
        displaySettings: [:]
    )

    enum CodingKeys: String, CodingKey {
        case frameRateLimit
        case pauseOnBattery
        case pauseOnFullscreenApp
        case launchAtLogin
        case musicReactiveEnabled
        case reactiveSensitivity
        case gpuAutoThrottleEnabled
        case marketplaceEndpoint
        case githubPackQuery
        case displaySettings
    }

    init(
        frameRateLimit: Int,
        pauseOnBattery: Bool,
        pauseOnFullscreenApp: Bool,
        launchAtLogin: Bool,
        musicReactiveEnabled: Bool,
        reactiveSensitivity: Double,
        gpuAutoThrottleEnabled: Bool,
        marketplaceEndpoint: String,
        githubPackQuery: String,
        displaySettings: [String: DisplaySettings]
    ) {
        self.frameRateLimit = frameRateLimit
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnFullscreenApp = pauseOnFullscreenApp
        self.launchAtLogin = launchAtLogin
        self.musicReactiveEnabled = musicReactiveEnabled
        self.reactiveSensitivity = reactiveSensitivity
        self.gpuAutoThrottleEnabled = gpuAutoThrottleEnabled
        self.marketplaceEndpoint = marketplaceEndpoint
        self.githubPackQuery = githubPackQuery
        self.displaySettings = displaySettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default

        frameRateLimit = try container.decodeIfPresent(Int.self, forKey: .frameRateLimit) ?? defaults.frameRateLimit
        pauseOnBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? defaults.pauseOnBattery
        pauseOnFullscreenApp = try container.decodeIfPresent(Bool.self, forKey: .pauseOnFullscreenApp) ?? defaults.pauseOnFullscreenApp
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        musicReactiveEnabled = try container.decodeIfPresent(Bool.self, forKey: .musicReactiveEnabled) ?? defaults.musicReactiveEnabled
        reactiveSensitivity = try container.decodeIfPresent(Double.self, forKey: .reactiveSensitivity) ?? defaults.reactiveSensitivity
        gpuAutoThrottleEnabled = try container.decodeIfPresent(Bool.self, forKey: .gpuAutoThrottleEnabled) ?? defaults.gpuAutoThrottleEnabled
        marketplaceEndpoint = try container.decodeIfPresent(String.self, forKey: .marketplaceEndpoint) ?? defaults.marketplaceEndpoint
        githubPackQuery = try container.decodeIfPresent(String.self, forKey: .githubPackQuery) ?? defaults.githubPackQuery
        displaySettings = try container.decodeIfPresent([String: DisplaySettings].self, forKey: .displaySettings) ?? defaults.displaySettings
    }

    static func key(for displayID: UInt32) -> String {
        String(displayID)
    }

    func setting(for displayID: UInt32) -> DisplaySettings? {
        displaySettings[Self.key(for: displayID)]
    }

    mutating func upsertDisplay(_ display: DisplaySettings) {
        displaySettings[Self.key(for: display.id)] = display
    }

    mutating func removeDisplay(displayID: UInt32) {
        displaySettings.removeValue(forKey: Self.key(for: displayID))
    }

    var knownDisplayIDs: [UInt32] {
        displaySettings.keys.compactMap(UInt32.init)
    }
}
