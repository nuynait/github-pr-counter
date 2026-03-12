import Foundation

actor GitHubService {
    private let session = URLSession.shared
    private var token: String

    init(token: String) {
        self.token = token
    }

    func updateToken(_ newToken: String) {
        self.token = newToken
    }

    func fetchCurrentUser() async throws -> GitHubUser {
        let request = makeRequest(path: "/user")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubUser.self, from: data)
    }

    func fetchMyPRs(username: String) async throws -> [PullRequest] {
        let query = "type:pr+state:open+author:\(username)"
        return try await searchIssues(query: query)
    }

    func fetchReviewRequests(username: String) async throws -> [PullRequest] {
        async let pending = searchIssues(query: "type:pr+state:open+review-requested:\(username)")
        async let reviewed = searchIssues(query: "type:pr+state:open+reviewed-by:\(username)+-author:\(username)")

        let (pendingPRs, reviewedPRs) = try await (pending, reviewed)

        // Merge and deduplicate by ID, preferring pending (more recent data)
        var seen = Set<Int>()
        var result: [PullRequest] = []
        for pr in pendingPRs + reviewedPRs {
            if seen.insert(pr.id).inserted {
                result.append(pr)
            }
        }
        return result
    }

    /// Check if a PR was merged, closed, or still open.
    func fetchPRState(repo: String, number: Int) async -> String {
        let request = makeRequest(path: "/repos/\(repo)/pulls/\(number)")
        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let json = try decoder.decode(PRStateResponse.self, from: data)
            if json.mergedAt != nil { return "merged" }
            return json.state
        } catch {
            return "unknown"
        }
    }

    /// Fetch reviews for a PR.
    func fetchReviews(repo: String, number: Int) async -> [PRReview] {
        let request = makeRequest(path: "/repos/\(repo)/pulls/\(number)/reviews?per_page=100")
        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PRReview].self, from: data)
        } catch {
            return []
        }
    }

    /// Fetch PR detail to get requested_reviewers.
    func fetchPRDetail(repo: String, number: Int) async -> PRDetailResponse? {
        let request = makeRequest(path: "/repos/\(repo)/pulls/\(number)")
        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PRDetailResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func searchIssues(query: String) async throws -> [PullRequest] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let request = makeRequest(path: "/search/issues?q=\(encodedQuery)&per_page=100&sort=updated&order=desc")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let searchResponse = try decoder.decode(SearchResponse.self, from: data)
        return searchResponse.items
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: Constants.gitHubAPIBaseURL + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw GitHubAPIError.unauthorized
        case 403:
            throw GitHubAPIError.rateLimited
        case 422:
            throw GitHubAPIError.validationFailed
        default:
            throw GitHubAPIError.httpError(httpResponse.statusCode)
        }
    }
}

enum GitHubAPIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited
    case validationFailed
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from GitHub"
        case .unauthorized: return "Authentication failed. Please sign in again."
        case .rateLimited: return "GitHub API rate limit exceeded. Please wait."
        case .validationFailed: return "Invalid request"
        case .httpError(let code): return "HTTP error \(code)"
        }
    }
}
