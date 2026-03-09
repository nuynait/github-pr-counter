import Foundation

struct PRMetadata: Codable, Equatable {
    let prId: Int
    var isUnread: Bool
    var isStarred: Bool

    init(prId: Int, isUnread: Bool = false, isStarred: Bool = false) {
        self.prId = prId
        self.isUnread = isUnread
        self.isStarred = isStarred
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
}
