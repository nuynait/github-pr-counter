import Foundation

struct SearchResponse: Codable {
    let totalCount: Int
    let items: [PullRequest]
}

struct PullRequest: Codable, Identifiable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let state: String
    let draft: Bool?
    let createdAt: Date
    let updatedAt: Date
    let user: PRUser
    let pullRequest: PRLinks?
    let repositoryUrl: String?

    var repoFullName: String {
        // repositoryUrl is like "https://api.github.com/repos/org/repo"
        guard let url = repositoryUrl else { return "unknown" }
        let components = url.components(separatedBy: "/repos/")
        return components.count > 1 ? components[1] : "unknown"
    }

    var browserURL: URL? {
        URL(string: htmlUrl)
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var isDraft: Bool {
        draft ?? false
    }
}

struct PRUser: Codable, Identifiable, Equatable {
    let id: Int
    let login: String
    let avatarUrl: String
}

struct PRLinks: Codable, Equatable {
    let htmlUrl: String?
}

struct PRStateResponse: Codable {
    let state: String
    let mergedAt: String?
}
