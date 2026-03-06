import Foundation

@MainActor
final class GitHubPackService: ObservableObject {
    @Published private(set) var searchResults: [GitHubWallpaperRepository] = []
    @Published private(set) var installedPacks: [InstalledWallpaperPack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private let installService: WallpaperInstallService

    init(installService: WallpaperInstallService) {
        self.installService = installService
        installedPacks = installService.listInstalledPacks()
    }

    func reloadInstalledPacks() {
        installedPacks = installService.listInstalledPacks()
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a GitHub search query"
            return
        }

        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            let endpoint = "https://api.github.com/search/repositories?q=\(encoded)&sort=stars&order=desc&per_page=30"
            guard let url = URL(string: endpoint) else {
                throw GitHubPackError.invalidQuery
            }

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("LumenDesk", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw GitHubPackError.searchFailed
            }

            let decoded = try JSONDecoder().decode(GitHubSearchResponse.self, from: data)
            searchResults = decoded.items.map {
                GitHubWallpaperRepository(
                    id: $0.id,
                    name: $0.name,
                    fullName: $0.fullName,
                    summary: $0.description ?? "",
                    stars: $0.stargazersCount,
                    defaultBranch: $0.defaultBranch,
                    htmlURL: $0.htmlURL
                )
            }
            statusMessage = "Found \(searchResults.count) repositories"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func install(_ repository: GitHubWallpaperRepository) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let zipURLString = "https://codeload.github.com/\(repository.fullName)/zip/refs/heads/\(repository.defaultBranch)"
            guard let zipURL = URL(string: zipURLString) else {
                throw GitHubPackError.installFailed
            }

            var request = URLRequest(url: zipURL)
            request.setValue("LumenDesk", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw GitHubPackError.installFailed
            }

            _ = try installService.installGitHubPack(
                zipData: data,
                repositoryFullName: repository.fullName,
                branch: repository.defaultBranch
            )

            reloadInstalledPacks()
            statusMessage = "Installed \(repository.fullName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct GitHubSearchResponse: Decodable {
    let items: [GitHubSearchItem]
}

private struct GitHubSearchItem: Decodable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let stargazersCount: Int
    let defaultBranch: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case description
        case stargazersCount = "stargazers_count"
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
    }
}

enum GitHubPackError: LocalizedError {
    case invalidQuery
    case searchFailed
    case installFailed

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid GitHub query"
        case .searchFailed:
            return "GitHub search failed"
        case .installFailed:
            return "Could not install the GitHub pack"
        }
    }
}
