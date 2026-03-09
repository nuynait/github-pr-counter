import Foundation

struct PRMetadata: Codable, Equatable {
    let prId: Int
    var isUnread: Bool
    var isStarred: Bool
    /// Tracks resolved state: "merged", "closed", or nil (still open/active).
    var resolvedState: String?

    init(prId: Int, isUnread: Bool = false, isStarred: Bool = false, resolvedState: String? = nil) {
        self.prId = prId
        self.isUnread = isUnread
        self.isStarred = isStarred
        self.resolvedState = resolvedState
    }
}

/// Persists PR metadata (unread, starred) keyed by PR ID.
enum PRMetadataStore {
    private static let key = "prMetadata"

    static func load() -> [Int: PRMetadata] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([PRMetadata].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.prId, $0) })
    }

    static func save(_ metadata: [Int: PRMetadata]) {
        let list = Array(metadata.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Returns the set of PR IDs that were known last session.
    static func loadKnownPRIds() -> Set<Int> {
        guard let data = UserDefaults.standard.data(forKey: "knownPRIds"),
              let ids = try? JSONDecoder().decode(Set<Int>.self, from: data)
        else { return [] }
        return ids
    }

    static func saveKnownPRIds(_ ids: Set<Int>) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: "knownPRIds")
        }
    }

    private static let starredPRsKey = "starredPRs"

    static func loadStarredPRs() -> [Int: PullRequest] {
        guard let data = UserDefaults.standard.data(forKey: starredPRsKey),
              let decoder = {
                  let d = JSONDecoder()
                  d.keyDecodingStrategy = .convertFromSnakeCase
                  d.dateDecodingStrategy = .iso8601
                  return d
              }() as JSONDecoder?,
              let list = try? decoder.decode([PullRequest].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    static func saveStarredPRs(_ prs: [Int: PullRequest]) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let list = Array(prs.values)
        if let data = try? encoder.encode(list) {
            UserDefaults.standard.set(data, forKey: starredPRsKey)
        }
    }
}

/// Per-repo metadata persisted across launches.
struct RepoMetadata: Codable, Equatable {
    let repoName: String
    /// Whether the repo section is expanded in the My PRs tab.
    var isExpandedMyPRs: Bool
    /// Whether the repo section is expanded in the Review Requests tab.
    var isExpandedReviews: Bool
    /// Whether the repo section is expanded in the Starred tab.
    var isExpandedStarred: Bool

    init(repoName: String, isExpandedMyPRs: Bool = true, isExpandedReviews: Bool = true, isExpandedStarred: Bool = true) {
        self.repoName = repoName
        self.isExpandedMyPRs = isExpandedMyPRs
        self.isExpandedReviews = isExpandedReviews
        self.isExpandedStarred = isExpandedStarred
    }
}

enum RepoMetadataStore {
    private static let key = "repoMetadata"

    static func load() -> [String: RepoMetadata] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([RepoMetadata].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.repoName, $0) })
    }

    static func save(_ metadata: [String: RepoMetadata]) {
        let list = Array(metadata.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
