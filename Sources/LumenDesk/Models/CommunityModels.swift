import Foundation

enum CommunityWallpaperKind: String, CaseIterable, Identifiable, Codable {
    case web
    case video
    case gradient
    case shader

    var id: String { rawValue }

    var label: String {
        switch self {
        case .web: return "Web"
        case .video: return "Video"
        case .gradient: return "Gradient"
        case .shader: return "Metal"
        }
    }
}

struct MarketplaceWallpaper: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var author: String
    var summary: String?
    var kind: CommunityWallpaperKind
    var sourceValue: String?
    var downloadURL: String?
    var thumbnailURL: String?
    var tags: [String]

    init(
        id: String,
        title: String,
        author: String,
        summary: String?,
        kind: CommunityWallpaperKind,
        sourceValue: String?,
        downloadURL: String?,
        thumbnailURL: String?,
        tags: [String]
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.kind = kind
        self.sourceValue = sourceValue
        self.downloadURL = downloadURL
        self.thumbnailURL = thumbnailURL
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case summary
        case description
        case kind
        case type
        case sourceValue
        case value
        case url
        case downloadURL
        case download
        case thumbnailURL
        case thumbnail
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "Unknown"

        let summaryValue = try container.decodeIfPresent(String.self, forKey: .summary)
        let descriptionValue = try container.decodeIfPresent(String.self, forKey: .description)
        summary = summaryValue ?? descriptionValue

        let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? "web"
        kind = CommunityWallpaperKind(rawValue: kindRaw.lowercased()) ?? .web

        sourceValue = try container.decodeIfPresent(String.self, forKey: .sourceValue)
            ?? container.decodeIfPresent(String.self, forKey: .value)
            ?? container.decodeIfPresent(String.self, forKey: .url)

        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
            ?? container.decodeIfPresent(String.self, forKey: .download)

        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
            ?? container.decodeIfPresent(String.self, forKey: .thumbnail)

        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(summary, forKey: .summary)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(sourceValue, forKey: .sourceValue)
        try container.encode(downloadURL, forKey: .downloadURL)
        try container.encode(thumbnailURL, forKey: .thumbnailURL)
        try container.encode(tags, forKey: .tags)
    }
}

struct MarketplaceFeedEnvelope: Codable {
    let wallpapers: [MarketplaceWallpaper]
}

struct MarketplaceUploadInput {
    var title: String
    var author: String
    var summary: String
    var kind: CommunityWallpaperKind
    var sourceValue: String
    var fileURL: URL?

    static let empty = MarketplaceUploadInput(
        title: "",
        author: "",
        summary: "",
        kind: .web,
        sourceValue: "",
        fileURL: nil
    )
}

struct GitHubWallpaperRepository: Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let summary: String
    let stars: Int
    let defaultBranch: String
    let htmlURL: String
}

struct InstalledPackWallpaper: Identifiable {
    let id: String
    let title: String
    let source: WallpaperSource
}

struct InstalledWallpaperPack: Identifiable {
    let id: String
    let name: String
    let sourceRepository: String
    let localPath: String
    let wallpapers: [InstalledPackWallpaper]
}

struct WallpaperPackManifest: Codable {
    let name: String?
    let author: String?
    let summary: String?
    let wallpapers: [WallpaperPackEntry]
}

struct WallpaperPackEntry: Codable {
    let id: String?
    let title: String?
    let type: String
    let url: String?
    let path: String?
    let presetID: String?
    let preset: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case url
        case path
        case presetID
        case preset
    }

    func toInstalledWallpaper(baseURL: URL) -> InstalledPackWallpaper? {
        let generatedID = id ?? UUID().uuidString
        let generatedTitle = title ?? type.capitalized

        switch type.lowercased() {
        case "web":
            let value = url ?? ""
            guard !value.isEmpty else { return nil }
            return InstalledPackWallpaper(id: generatedID, title: generatedTitle, source: .web(url: value))
        case "video":
            if let path, !path.isEmpty {
                let resolvedPath: String
                if path.hasPrefix("/") {
                    resolvedPath = path
                } else {
                    resolvedPath = baseURL.appendingPathComponent(path).path
                }
                return InstalledPackWallpaper(id: generatedID, title: generatedTitle, source: .video(path: resolvedPath))
            }
            return nil
        case "gradient":
            let id = presetID ?? preset ?? GradientPreset.fallback.id
            return InstalledPackWallpaper(id: generatedID, title: generatedTitle, source: .gradient(presetID: id))
        case "shader":
            let id = presetID ?? preset ?? ShaderPreset.fallback.id
            return InstalledPackWallpaper(id: generatedID, title: generatedTitle, source: .shader(presetID: id))
        default:
            return nil
        }
    }
}
