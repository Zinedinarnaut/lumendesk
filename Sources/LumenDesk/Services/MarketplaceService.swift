import Foundation
import UniformTypeIdentifiers

@MainActor
final class MarketplaceService: ObservableObject {
    @Published private(set) var wallpapers: [MarketplaceWallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var totalAvailable = 0

    func fetch(
        endpoint rawEndpoint: String,
        authToken: String? = nil,
        appleUserID: String? = nil,
        query: String? = nil,
        kind: CommunityWallpaperKind? = nil,
        sort: MarketplaceSortOption = .featured,
        perPage: Int = 120
    ) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let endpoint = try normalizedEndpoint(from: rawEndpoint)
            let urls = candidateFeedURLs(
                from: endpoint,
                query: query,
                kind: kind,
                sort: sort,
                perPage: perPage
            )

            var lastError: Error?
            for url in urls {
                do {
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                    applyAuthHeaders(
                        request: &request,
                        authToken: authToken,
                        appleUserID: appleUserID
                    )
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                        continue
                    }

                    if let catalog = try? JSONDecoder().decode(MarketplaceCatalogEnvelope.self, from: data) {
                        wallpapers = catalog.items
                        totalAvailable = catalog.total ?? catalog.items.count
                        statusMessage = "Loaded \(catalog.items.count) of \(totalAvailable) wallpapers"
                        return
                    }

                    if let array = try? JSONDecoder().decode([MarketplaceWallpaper].self, from: data) {
                        wallpapers = array
                        totalAvailable = array.count
                        statusMessage = "Loaded \(array.count) wallpapers"
                        return
                    }

                    if let feed = try? JSONDecoder().decode(MarketplaceFeedEnvelope.self, from: data) {
                        wallpapers = feed.wallpapers
                        totalAvailable = feed.wallpapers.count
                        statusMessage = "Loaded \(feed.wallpapers.count) wallpapers"
                        return
                    }

                    if let compatibility = try? JSONDecoder().decode(MarketplaceCompatibilityEnvelope.self, from: data) {
                        wallpapers = compatibility.wallpapers
                        totalAvailable = compatibility.total ?? compatibility.wallpapers.count
                        statusMessage = "Loaded \(compatibility.wallpapers.count) of \(totalAvailable) wallpapers"
                        return
                    }

                    throw MarketplaceError.invalidResponseFormat
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? MarketplaceError.feedUnavailable
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func upload(
        endpoint rawEndpoint: String,
        input: MarketplaceUploadInput,
        authToken: String? = nil,
        appleUserID: String? = nil
    ) async {
        statusMessage = nil

        do {
            let endpoint = try normalizedEndpoint(from: rawEndpoint)
            let boundary = "Boundary-\(UUID().uuidString)"
            let body = try multipartBody(boundary: boundary, input: input)
            let uploadURLs = candidateUploadURLs(from: endpoint)
            var lastError: Error?

            for uploadURL in uploadURLs {
                do {
                    var request = URLRequest(url: uploadURL)
                    request.httpMethod = "POST"
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    applyAuthHeaders(
                        request: &request,
                        authToken: authToken,
                        appleUserID: appleUserID
                    )

                    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                        let responseText = String(data: data, encoding: .utf8) ?? ""
                        throw MarketplaceError.uploadFailed("HTTP upload failed. \(responseText)")
                    }

                    if let item = decodeUploadedWallpaper(from: data) {
                        upsertWallpaper(item)
                    }

                    statusMessage = "Upload completed"
                    return
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? MarketplaceError.uploadFailed("No upload endpoint accepted the request.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func trackInstall(
        endpoint rawEndpoint: String,
        wallpaperID: String,
        authToken: String? = nil,
        appleUserID: String? = nil
    ) async {
        do {
            let endpoint = try normalizedEndpoint(from: rawEndpoint)
            let urls = candidateInstallURLs(from: endpoint, wallpaperID: wallpaperID)

            for url in urls {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    applyAuthHeaders(request: &request, authToken: authToken, appleUserID: appleUserID)

                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                        continue
                    }

                    if let updated = decodeUploadedWallpaper(from: data) {
                        upsertWallpaper(updated)
                    } else {
                        incrementInstallCount(for: wallpaperID)
                    }
                    return
                } catch {
                    continue
                }
            }
        } catch {
            return
        }
    }

    private func normalizedEndpoint(from raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw MarketplaceError.invalidEndpoint
        }

        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }

        guard let url = URL(string: "https://\(trimmed)") else {
            throw MarketplaceError.invalidEndpoint
        }

        return url
    }

    private func candidateFeedURLs(
        from endpoint: URL,
        query: String?,
        kind: CommunityWallpaperKind?,
        sort: MarketplaceSortOption,
        perPage: Int
    ) -> [URL] {
        if endpoint.pathExtension.lowercased() == "json" {
            return [endpoint]
        }

        let parameters = FeedParameters(
            query: query?.trimmingCharacters(in: .whitespacesAndNewlines),
            kindRawValue: kind?.rawValue,
            sortRawValue: sort.rawValue,
            perPage: max(1, min(perPage, 250))
        )

        var urls: [URL] = []
        urls.append(configureFeedURL(endpoint.appendingPathComponent("api/marketplace"), parameters: parameters))
        urls.append(configureFeedURL(endpoint.appendingPathComponent("api/wallpapers"), parameters: parameters))
        urls.append(endpoint.appendingPathComponent("wallpapers.json"))
        urls.append(configureFeedURL(endpoint, parameters: parameters))

        // De-duplicate preserving order.
        var seen = Set<String>()
        return urls.filter {
            let key = $0.absoluteString
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func candidateUploadURLs(from endpoint: URL) -> [URL] {
        let normalizedPath = endpoint.path.lowercased()
        if normalizedPath.hasSuffix("/upload") || normalizedPath.hasSuffix("/api/upload") {
            return [endpoint]
        }

        var urls: [URL] = []
        urls.append(endpoint.appendingPathComponent("api/upload"))
        urls.append(endpoint.appendingPathComponent("upload"))
        urls.append(endpoint)

        var seen = Set<String>()
        return urls.filter {
            let key = $0.absoluteString
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func candidateInstallURLs(from endpoint: URL, wallpaperID: String) -> [URL] {
        let cleanID = wallpaperID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return [] }

        var urls: [URL] = []
        urls.append(endpoint.appendingPathComponent("api/wallpapers").appendingPathComponent(cleanID).appendingPathComponent("install"))
        urls.append(endpoint.appendingPathComponent("wallpapers").appendingPathComponent(cleanID).appendingPathComponent("install"))

        let normalizedPath = endpoint.path.lowercased()
        if normalizedPath.contains("/api/wallpapers/") && normalizedPath.hasSuffix("/install") {
            urls.insert(endpoint, at: 0)
        }

        var seen = Set<String>()
        return urls.filter {
            let key = $0.absoluteString
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func configureFeedURL(_ rawURL: URL, parameters: FeedParameters) -> URL {
        guard var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else {
            return rawURL
        }

        var queryItems = components.queryItems ?? []

        if let query = parameters.query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        if let kind = parameters.kindRawValue, !kind.isEmpty {
            queryItems.append(URLQueryItem(name: "kind", value: kind))
        }

        queryItems.append(URLQueryItem(name: "sort", value: parameters.sortRawValue))
        queryItems.append(URLQueryItem(name: "perPage", value: String(parameters.perPage)))

        components.queryItems = queryItems
        return components.url ?? rawURL
    }

    private func applyAuthHeaders(request: inout URLRequest, authToken: String?, appleUserID: String?) {
        request.setValue("LumenDesk", forHTTPHeaderField: "User-Agent")

        if let authToken {
            let trimmed = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
            }
        }

        if let appleUserID {
            let trimmed = appleUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                request.setValue(trimmed, forHTTPHeaderField: "X-Apple-User-ID")
            }
        }
    }

    private func multipartBody(boundary: String, input: MarketplaceUploadInput) throws -> Data {
        var body = Data()

        func appendText(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString(value)
            body.appendString("\r\n")
        }

        appendText("title", input.title)
        appendText("author", input.author)
        appendText("summary", input.summary)
        appendText("kind", input.kind.rawValue)
        appendText("sourceValue", input.sourceValue)

        if !input.tags.isEmpty {
            appendText("tags", input.tags)
        }

        if !input.thumbnailURL.isEmpty {
            appendText("thumbnailURL", input.thumbnailURL)
        }

        if !input.previewURL.isEmpty {
            appendText("previewURL", input.previewURL)
        }

        if !input.accentColor.isEmpty {
            appendText("accentColor", input.accentColor)
        }

        if let fileURL = input.fileURL {
            let fileData = try Data(contentsOf: fileURL)
            let filename = fileURL.lastPathComponent
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
            body.appendString("Content-Type: \(mimeType)\r\n\r\n")
            body.append(fileData)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    private func decodeUploadedWallpaper(from data: Data) -> MarketplaceWallpaper? {
        if let itemEnvelope = try? JSONDecoder().decode(MarketplaceItemEnvelope.self, from: data) {
            return itemEnvelope.wallpaper
        }

        if let singleItem = try? JSONDecoder().decode(MarketplaceWallpaper.self, from: data) {
            return singleItem
        }

        return nil
    }

    private func upsertWallpaper(_ item: MarketplaceWallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.id == item.id }) {
            wallpapers[index] = item
        } else {
            wallpapers.insert(item, at: 0)
            totalAvailable += 1
        }
    }

    private func incrementInstallCount(for wallpaperID: String) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaperID }) else {
            return
        }

        wallpapers[index].installs += 1
    }
}

private struct FeedParameters {
    let query: String?
    let kindRawValue: String?
    let sortRawValue: String
    let perPage: Int
}

private struct MarketplaceCompatibilityEnvelope: Codable {
    let wallpapers: [MarketplaceWallpaper]
    let page: Int?
    let perPage: Int?
    let total: Int?
    let hasMore: Bool?
}

private struct MarketplaceItemEnvelope: Codable {
    let wallpaper: MarketplaceWallpaper
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

enum MarketplaceError: LocalizedError {
    case invalidEndpoint
    case feedUnavailable
    case invalidResponseFormat
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid marketplace endpoint"
        case .feedUnavailable:
            return "No marketplace feed could be loaded"
        case .invalidResponseFormat:
            return "Marketplace response format is invalid"
        case .uploadFailed(let message):
            return message
        }
    }
}
