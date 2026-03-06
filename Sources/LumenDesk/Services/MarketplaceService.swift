import Foundation
import UniformTypeIdentifiers

@MainActor
final class MarketplaceService: ObservableObject {
    @Published private(set) var wallpapers: [MarketplaceWallpaper] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    func fetch(endpoint rawEndpoint: String) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let endpoint = try normalizedEndpoint(from: rawEndpoint)
            let urls = candidateFeedURLs(from: endpoint)

            var lastError: Error?
            for url in urls {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
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

    func upload(endpoint rawEndpoint: String, input: MarketplaceUploadInput) async {
        statusMessage = nil

        do {
            let endpoint = try normalizedEndpoint(from: rawEndpoint)
            let uploadURL = candidateUploadURL(from: endpoint)
            let boundary = "Boundary-\(UUID().uuidString)"

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let body = try multipartBody(boundary: boundary, input: input)
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)

            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                let responseText = String(data: data, encoding: .utf8) ?? ""
                throw MarketplaceError.uploadFailed("HTTP upload failed. \(responseText)")
            }

            statusMessage = "Upload request sent successfully"
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

    private func candidateUploadURL(from endpoint: URL) -> URL {
        if endpoint.lastPathComponent.lowercased() == "upload" {
            return endpoint
        }
        return endpoint.appendingPathComponent("upload")
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
