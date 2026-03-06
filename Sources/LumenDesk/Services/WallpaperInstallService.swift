import Foundation

@MainActor
final class WallpaperInstallService: ObservableObject {
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let marketplaceURL: URL
    private let packsURL: URL

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = support.appendingPathComponent("LumenDesk", isDirectory: true)
        marketplaceURL = rootURL.appendingPathComponent("Marketplace", isDirectory: true)
        packsURL = rootURL.appendingPathComponent("Packs", isDirectory: true)

        ensureDirectory(rootURL)
        ensureDirectory(marketplaceURL)
        ensureDirectory(packsURL)
    }

    func installRemoteVideo(urlString: String, title: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw InstallError.invalidURL
        }

        let extensionGuess = (url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        let safeName = sanitizeFilename(title)
        let destination = marketplaceURL.appendingPathComponent("\(safeName)-\(UUID().uuidString).\(extensionGuess)")

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw InstallError.downloadFailed
        }

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        return destination.path
    }

    func installGitHubPack(zipData: Data, repositoryFullName: String, branch: String) throws -> InstalledWallpaperPack {
        let slug = sanitizeFilename(repositoryFullName.replacingOccurrences(of: "/", with: "-"))
        let destination = packsURL.appendingPathComponent(slug, isDirectory: true)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let tempZip = destination.appendingPathComponent("source.zip")
        try zipData.write(to: tempZip)

        try runProcess(executable: "/usr/bin/unzip", arguments: ["-o", tempZip.path, "-d", destination.path])
        try? fileManager.removeItem(at: tempZip)

        let normalizedRoot = normalizePackRoot(in: destination)
        let pack = try loadInstalledPack(
            at: normalizedRoot,
            fallbackName: repositoryFullName,
            sourceRepository: repositoryFullName,
            packID: "\(repositoryFullName)#\(branch)"
        )

        return pack
    }

    func listInstalledPacks() -> [InstalledWallpaperPack] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: packsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var packs: [InstalledWallpaperPack] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            if let pack = try? loadInstalledPack(
                at: normalizePackRoot(in: url),
                fallbackName: url.lastPathComponent,
                sourceRepository: url.lastPathComponent,
                packID: url.lastPathComponent
            ) {
                packs.append(pack)
            }
        }

        return packs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadInstalledPack(
        at root: URL,
        fallbackName: String,
        sourceRepository: String,
        packID: String
    ) throws -> InstalledWallpaperPack {
        let manifestURL = root.appendingPathComponent("pack.json")
        let wallpapers: [InstalledPackWallpaper]
        let packName: String

        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(WallpaperPackManifest.self, from: data)
            wallpapers = manifest.wallpapers.compactMap { $0.toInstalledWallpaper(baseURL: root) }
            packName = manifest.name ?? fallbackName
        } else {
            wallpapers = discoverVideoWallpapers(in: root)
            packName = fallbackName
        }

        return InstalledWallpaperPack(
            id: packID,
            name: packName,
            sourceRepository: sourceRepository,
            localPath: root.path,
            wallpapers: wallpapers
        )
    }

    private func discoverVideoWallpapers(in root: URL) -> [InstalledPackWallpaper] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [InstalledPackWallpaper] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ["mp4", "mov", "m4v", "webm"].contains(ext) {
                let title = fileURL.deletingPathExtension().lastPathComponent
                results.append(
                    InstalledPackWallpaper(
                        id: UUID().uuidString,
                        title: title,
                        source: .video(path: fileURL.path)
                    )
                )
            }
        }

        return results
    }

    private func normalizePackRoot(in directory: URL) -> URL {
        guard
            let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]),
            children.count == 1,
            (try? children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            return directory
        }

        return children[0]
    }

    private func ensureDirectory(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let reduced = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(reduced).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "wallpaper" : cleaned
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "unknown"
            throw InstallError.processFailed(output)
        }
    }
}

enum InstallError: LocalizedError {
    case invalidURL
    case downloadFailed
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .downloadFailed:
            return "Download failed"
        case .processFailed(let output):
            return "Install process failed: \(output)"
        }
    }
}
