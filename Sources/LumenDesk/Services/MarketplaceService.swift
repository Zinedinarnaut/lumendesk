import Foundation
import UniformTypeIdentifiers

@MainActor
final class MarketplaceService: ObservableObject {
    @Published private(set) var wallpapers: [MarketplaceWallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    func fetch(
        endpoint rawEndpoint: String,
        authToken: String? = nil,
        appleUserID: String? = nil
    ) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let endpoint = try normalizedEndpoint(from: rawEndpoint)
            let urls = candidateFeedURLs(from: endpoint)

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

                    if let array = try? JSONDecoder().decode([MarketplaceWallpaper].self, from: data) {
                        wallpapers = array
                        statusMessage = "Loaded \(array.count) wallpapers"
                        return
                    }

                    if let feed = try? JSONDecoder().decode(MarketplaceFeedEnvelope.self, from: data) {
                        wallpapers = feed.wallpapers
                        statusMessage = "Loaded \(feed.wallpapers.count) wallpapers"
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

                    statusMessage = "Upload request sent successfully"
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

    private func candidateFeedURLs(from endpoint: URL) -> [URL] {
        if endpoint.pathExtension.lowercased() == "json" {
            return [endpoint]
        }

        var urls: [URL] = []
        urls.append(endpoint.appendingPathComponent("wallpapers.json"))
        urls.append(endpoint.appendingPathComponent("api/wallpapers"))
        urls.append(endpoint)

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
