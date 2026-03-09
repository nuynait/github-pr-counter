import Foundation
import SwiftUI

struct PRGroup: Identifiable, Equatable {
    let id: String // repo full name
    let repoName: String
    let prs: [PullRequest]
}

@MainActor
class PRViewModel: ObservableObject {
    @Published var myPRs: [PullRequest] = []
    @Published var reviewRequests: [PullRequest] = []
    @Published var myPRGroups: [PRGroup] = []
    @Published var reviewGroups: [PRGroup] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?
    @Published var archivedRepos: Set<String> {
        didSet { saveArchivedRepos() }
    }
    @Published var repoOrder: [String] {
        didSet {
            saveRepoOrder()
            applyFilters()
        }
    }

    private var allMyPRs: [PullRequest] = []
    private var allReviewRequests: [PullRequest] = []
    private var service: GitHubService?
    private var username: String?
    private var pollTask: Task<Void, Never>?
    private var previousMyPRs: [Int: PullRequest] = [:]
    private var previousReviews: [Int: PullRequest] = [:]
    private var hasLoadedOnce = false

    /// Per-PR metadata (unread, starred) persisted across launches.
    @Published var prMetadata: [Int: PRMetadata] = [:] {
        didSet { PRMetadataStore.save(prMetadata) }
    }
    /// PR IDs known from last session, used to detect new PRs on first load.
    private var lastSessionKnownIds: Set<Int>

    @Published var showNewIndicator: Bool {
        didSet { UserDefaults.standard.set(showNewIndicator, forKey: Self.showNewIndicatorKey) }
    }

    private static let archivedReposKey = "archivedRepos"
    private static let repoOrderKey = "repoOrder"
    private static let showNewIndicatorKey = "showNewIndicator"

    var myPRCount: Int { myPRs.count }
    var reviewRequestCount: Int { reviewRequests.count }
    var myPRUnreadCount: Int { myPRs.filter { isUnread($0.id) }.count }
    var reviewUnreadCount: Int { reviewRequests.filter { isUnread($0.id) }.count }

    /// All visible (non-archived) repos seen across both tabs, in user-defined order.
    var orderedVisibleRepos: [String] {
        let allRepoNames = Set(allMyPRs.map(\.repoFullName) + allReviewRequests.map(\.repoFullName))
        let visible = allRepoNames.subtracting(archivedRepos)
        // Return repos in the saved order, appending any new ones at the bottom
        var result = repoOrder.filter { visible.contains($0) }
        let unsorted = visible.subtracting(Set(result)).sorted()
        result.append(contentsOf: unsorted)
        return result
    }

    init() {
        let savedArchived = UserDefaults.standard.stringArray(forKey: Self.archivedReposKey) ?? []
        self.archivedRepos = Set(savedArchived)
        self.repoOrder = UserDefaults.standard.stringArray(forKey: Self.repoOrderKey) ?? []
        self.showNewIndicator = UserDefaults.standard.object(forKey: Self.showNewIndicatorKey) as? Bool ?? true
        self.prMetadata = PRMetadataStore.load()
        self.lastSessionKnownIds = PRMetadataStore.loadKnownPRIds()
    }

    func markAsRead(_ prId: Int) {
        prMetadata[prId]?.isUnread = false
    }

    func isUnread(_ prId: Int) -> Bool {
        showNewIndicator && (prMetadata[prId]?.isUnread == true)
    }

    func toggleStar(_ prId: Int) {
        if prMetadata[prId] != nil {
            prMetadata[prId]!.isStarred.toggle()
        } else {
            prMetadata[prId] = PRMetadata(prId: prId, isStarred: true)
        }
        applyFilters()
    }

    func isStarred(_ prId: Int) -> Bool {
        prMetadata[prId]?.isStarred == true
    }

    func markAllMyPRsAsRead() {
        for pr in myPRs {
            prMetadata[pr.id]?.isUnread = false
        }
    }

    func markAllReviewsAsRead() {
        for pr in reviewRequests {
            prMetadata[pr.id]?.isUnread = false
        }
    }

    func configure(token: String, username: String) {
        self.service = GitHubService(token: token)
        self.username = username
        startPolling()
    }

    func refresh() {
        Task { await fetchAll() }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            await fetchAll()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.pollInterval))
                if Task.isCancelled { break }
                await fetchAll()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
    }

    func archiveRepo(_ repoName: String) {
        archivedRepos.insert(repoName)
        applyFilters()
    }

    func unarchiveRepo(_ repoName: String) {
        archivedRepos.remove(repoName)
        // Append to order if not already tracked
        if !repoOrder.contains(repoName) {
            repoOrder.append(repoName)
        }
        applyFilters()
    }

    func moveRepos(from source: IndexSet, to destination: Int) {
        var ordered = orderedVisibleRepos
        ordered.move(fromOffsets: source, toOffset: destination)
        repoOrder = ordered
        applyFilters()
    }

    private func fetchAll() async {
        guard let service, let username else { return }

        isLoading = true
        error = nil

        do {
            async let myPRsResult = service.fetchMyPRs(username: username)
            async let reviewResult = service.fetchReviewRequests(username: username)

            let (myPRs, reviews) = try await (myPRsResult, reviewResult)

            let currentAllIds = Set(myPRs.map(\.id)).union(Set(reviews.map(\.id)))

            if hasLoadedOnce {
                // Subsequent fetches: detect events and notify
                let events = await detectEvents(
                    newMyPRs: myPRs,
                    newReviews: reviews,
                    service: service
                )
                let filtered = events.filter { !archivedRepos.contains($0.pr.repoFullName) }
                NotificationService.send(events: filtered)

                // Mark newly added PRs as unread
                let oldAllIds = Set(previousMyPRs.keys).union(Set(previousReviews.keys))
                let addedIds = currentAllIds.subtracting(oldAllIds)
                for id in addedIds {
                    if prMetadata[id] == nil {
                        prMetadata[id] = PRMetadata(prId: id, isUnread: true)
                    } else {
                        prMetadata[id]?.isUnread = true
                    }
                }
            } else {
                // First load: compare against last session's known IDs
                let addedIds = currentAllIds.subtracting(lastSessionKnownIds)
                for id in addedIds {
                    if prMetadata[id] == nil {
                        prMetadata[id] = PRMetadata(prId: id, isUnread: true)
                    } else {
                        prMetadata[id]?.isUnread = true
                    }
                }
            }

            // Clean up metadata for PRs no longer in any list
            for id in prMetadata.keys where !currentAllIds.contains(id) {
                prMetadata.removeValue(forKey: id)
            }

            // Persist known IDs for next session
            PRMetadataStore.saveKnownPRIds(currentAllIds)

            previousMyPRs = Dictionary(uniqueKeysWithValues: myPRs.map { ($0.id, $0) })
            previousReviews = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
            hasLoadedOnce = true

            self.allMyPRs = myPRs
            self.allReviewRequests = reviews

            // Add any new repos to the order list
            let allRepoNames = Set(myPRs.map(\.repoFullName) + reviews.map(\.repoFullName))
            let newRepos = allRepoNames.subtracting(Set(repoOrder)).subtracting(archivedRepos).sorted()
            if !newRepos.isEmpty {
                repoOrder.append(contentsOf: newRepos)
            }

            applyFilters()
            self.lastUpdated = Date()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func detectEvents(
        newMyPRs: [PullRequest],
        newReviews: [PullRequest],
        service: GitHubService
    ) async -> [PREvent] {
        var events: [PREvent] = []

        let newMyPRIds = Set(newMyPRs.map(\.id))
        let newReviewIds = Set(newReviews.map(\.id))
        let oldMyPRIds = Set(previousMyPRs.keys)
        let oldReviewIds = Set(previousReviews.keys)

        // My PRs: added = created
        for pr in newMyPRs where !oldMyPRIds.contains(pr.id) {
            events.append(.myPRCreated(pr))
        }

        // My PRs: removed = merged or closed
        let removedMyPRIds = oldMyPRIds.subtracting(newMyPRIds)
        for id in removedMyPRIds {
            guard let pr = previousMyPRs[id] else { continue }
            let state = await service.fetchPRState(repo: pr.repoFullName, number: pr.number)
            if state == "merged" {
                events.append(.myPRMerged(pr))
            } else {
                events.append(.myPRClosed(pr))
            }
        }

        // Review requests: added = review requested
        for pr in newReviews where !oldReviewIds.contains(pr.id) {
            events.append(.reviewRequestAdded(pr))
        }

        // Review requests: removed = merged, closed, or removed from review
        let removedReviewIds = oldReviewIds.subtracting(newReviewIds)
        for id in removedReviewIds {
            guard let pr = previousReviews[id] else { continue }
            let state = await service.fetchPRState(repo: pr.repoFullName, number: pr.number)
            switch state {
            case "merged":
                events.append(.reviewPRMerged(pr))
            case "closed":
                events.append(.reviewPRClosed(pr))
            default:
                // PR is still open but we're no longer a reviewer
                events.append(.reviewRequestRemoved(pr))
            }
        }

        return events
    }

    private func applyFilters() {
        let filteredMyPRs = allMyPRs.filter { !archivedRepos.contains($0.repoFullName) }
        let filteredReviews = allReviewRequests.filter { !archivedRepos.contains($0.repoFullName) }

        self.myPRs = filteredMyPRs
        self.reviewRequests = filteredReviews
        self.myPRGroups = groupByRepo(filteredMyPRs)
        self.reviewGroups = groupByRepo(filteredReviews)
    }

    private func groupByRepo(_ prs: [PullRequest]) -> [PRGroup] {
        let grouped = Dictionary(grouping: prs) { $0.repoFullName }
        let groups = grouped.map { key, value in
            // Starred PRs first within each group
            let sorted = value.sorted { a, b in
                let aStarred = isStarred(a.id)
                let bStarred = isStarred(b.id)
                if aStarred != bStarred { return aStarred }
                return a.updatedAt > b.updatedAt
            }
            return PRGroup(id: key, repoName: key, prs: sorted)
        }

        // Sort by user-defined order; unknown repos go to the end alphabetically
        return groups.sorted { a, b in
            let indexA = repoOrder.firstIndex(of: a.repoName)
            let indexB = repoOrder.firstIndex(of: b.repoName)
            switch (indexA, indexB) {
            case let (ia?, ib?): return ia < ib
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.repoName < b.repoName
            }
        }
    }

    private func saveArchivedRepos() {
        UserDefaults.standard.set(Array(archivedRepos), forKey: Self.archivedReposKey)
    }

    private func saveRepoOrder() {
        UserDefaults.standard.set(repoOrder, forKey: Self.repoOrderKey)
    }
}
