import Foundation
import SwiftUI

enum RepoTab {
    case myPRs, reviews, starred
}

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
    @Published var starredPRs: [PullRequest] = []
    @Published var starredAllGroups: [PRGroup] = []
    @Published var starredMyPRGroups: [PRGroup] = []
    @Published var starredReviewGroups: [PRGroup] = []
    @Published var reviewStatuses: [Int: PRReviewStatus] = [:]
    @Published var prReviewers: [Int: [String]] = [:]
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
    /// Persisted starred PR data, kept even when PRs leave the active lists.
    private var storedStarredPRs: [Int: PullRequest] = [:] {
        didSet { PRMetadataStore.saveStarredPRs(storedStarredPRs) }
    }
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

    @Published var repoMetadata: [String: RepoMetadata] = [:] {
        didSet { RepoMetadataStore.save(repoMetadata) }
    }

    @Published var showNewIndicator: Bool {
        didSet { UserDefaults.standard.set(showNewIndicator, forKey: Self.showNewIndicatorKey) }
    }

    @Published var excludeDraftsFromMenuBar: Bool {
        didSet { UserDefaults.standard.set(excludeDraftsFromMenuBar, forKey: Self.excludeDraftsKey) }
    }

    @Published var showZeroCount: Bool {
        didSet { UserDefaults.standard.set(showZeroCount, forKey: Self.showZeroCountKey) }
    }

    private static let archivedReposKey = "archivedRepos"
    private static let repoOrderKey = "repoOrder"
    private static let showNewIndicatorKey = "showNewIndicator"
    private static let excludeDraftsKey = "excludeDraftsFromMenuBar"
    private static let showZeroCountKey = "showZeroCount"

    var myPRCount: Int { myPRs.count }
    var reviewRequestCount: Int { reviewRequests.count }
    var myPRUnreadCount: Int { myPRs.filter { isUnread($0.id) }.count }
    var reviewUnreadCount: Int { reviewRequests.filter { isUnread($0.id) }.count }
    var starredCount: Int { starredPRs.count }
    var menuBarMyPRCount: Int {
        excludeDraftsFromMenuBar ? myPRs.filter { !$0.isDraft }.count : myPRs.count
    }
    var menuBarReviewCount: Int {
        excludeDraftsFromMenuBar ? reviewRequests.filter { !$0.isDraft }.count : reviewRequests.count
    }

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
        self.excludeDraftsFromMenuBar = UserDefaults.standard.bool(forKey: Self.excludeDraftsKey)
        self.showZeroCount = UserDefaults.standard.bool(forKey: Self.showZeroCountKey)
        self.prMetadata = PRMetadataStore.load()
        self.repoMetadata = RepoMetadataStore.load()
        self.storedStarredPRs = PRMetadataStore.loadStarredPRs()
        self.lastSessionKnownIds = PRMetadataStore.loadKnownPRIds()
    }

    func markAsRead(_ prId: Int) {
        if prMetadata[prId] != nil {
            prMetadata[prId]?.isUnread = false
        } else {
            prMetadata[prId] = PRMetadata(prId: prId, isUnread: false)
        }
    }

    func isUnread(_ prId: Int) -> Bool {
        showNewIndicator && (prMetadata[prId]?.isUnread == true)
    }

    func toggleStar(_ prId: Int) {
        let wasStarred = prMetadata[prId]?.isStarred == true
        if prMetadata[prId] != nil {
            prMetadata[prId]!.isStarred.toggle()
        } else {
            prMetadata[prId] = PRMetadata(prId: prId, isStarred: true)
        }

        if wasStarred {
            // Unstarring: remove from stored starred PRs
            storedStarredPRs.removeValue(forKey: prId)
        } else {
            // Starring: store the PR data
            if let pr = allMyPRs.first(where: { $0.id == prId }) ?? allReviewRequests.first(where: { $0.id == prId }) {
                storedStarredPRs[prId] = pr
            }
        }
        applyFilters()
    }

    func isStarred(_ prId: Int) -> Bool {
        prMetadata[prId]?.isStarred == true
    }

    func resolvedState(_ prId: Int) -> String? {
        prMetadata[prId]?.resolvedState
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

    func isRepoExpanded(_ repoName: String, tab: RepoTab) -> Bool {
        guard let meta = repoMetadata[repoName] else { return true }
        switch tab {
        case .myPRs: return meta.isExpandedMyPRs
        case .reviews: return meta.isExpandedReviews
        case .starred: return meta.isExpandedStarred
        }
    }

    func setRepoExpanded(_ repoName: String, tab: RepoTab, expanded: Bool) {
        if repoMetadata[repoName] == nil {
            repoMetadata[repoName] = RepoMetadata(repoName: repoName)
        }
        switch tab {
        case .myPRs:
            repoMetadata[repoName]?.isExpandedMyPRs = expanded
        case .reviews:
            repoMetadata[repoName]?.isExpandedReviews = expanded
        case .starred:
            repoMetadata[repoName]?.isExpandedStarred = expanded
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

                // Update resolvedState from events
                for event in events {
                    let prId = event.pr.id
                    switch event {
                    case .myPRMerged, .reviewPRMerged:
                        prMetadata[prId]?.resolvedState = "merged"
                    case .myPRClosed, .reviewPRClosed:
                        prMetadata[prId]?.resolvedState = "closed"
                    default:
                        break
                    }
                }

                // Mark newly added PRs as unread, clear resolvedState for returning PRs
                let oldAllIds = Set(previousMyPRs.keys).union(Set(previousReviews.keys))
                let addedIds = currentAllIds.subtracting(oldAllIds)
                for id in addedIds {
                    if prMetadata[id] == nil {
                        prMetadata[id] = PRMetadata(prId: id, isUnread: true)
                    } else {
                        prMetadata[id]?.isUnread = true
                        prMetadata[id]?.resolvedState = nil
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

            // Clean up metadata for PRs no longer in any list (keep starred)
            for id in prMetadata.keys where !currentAllIds.contains(id) {
                if prMetadata[id]?.isStarred != true {
                    prMetadata.removeValue(forKey: id)
                }
            }

            // Update stored starred PRs with latest data when still in lists,
            // and resolve state for starred PRs that left the lists
            for id in storedStarredPRs.keys {
                if let pr = myPRs.first(where: { $0.id == id }) ?? reviews.first(where: { $0.id == id }) {
                    storedStarredPRs[id] = pr
                    prMetadata[id]?.resolvedState = nil
                } else if prMetadata[id]?.resolvedState == nil {
                    // Starred PR left the list but we don't know why yet — check state
                    let pr = storedStarredPRs[id]!
                    let state = await service.fetchPRState(repo: pr.repoFullName, number: pr.number)
                    if state == "merged" {
                        prMetadata[id]?.resolvedState = "merged"
                    } else if state == "closed" {
                        prMetadata[id]?.resolvedState = "closed"
                    }
                }
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

            // Fetch review statuses for all visible PRs
            await fetchReviewStatuses(prs: myPRs + reviews, service: service)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchReviewStatuses(prs: [PullRequest], service: GitHubService) async {
        await withTaskGroup(of: (Int, PRReviewStatus?, [String]).self) { group in
            for pr in prs {
                group.addTask {
                    let (status, reviewers) = await self.computeReviewStatus(pr: pr, service: service)
                    return (pr.id, status, reviewers)
                }
            }

            var statuses: [Int: PRReviewStatus] = [:]
            var reviewers: [Int: [String]] = [:]
            for await (id, status, names) in group {
                if let status {
                    statuses[id] = status
                }
                if !names.isEmpty {
                    reviewers[id] = names
                }
            }
            if self.reviewStatuses != statuses {
                self.reviewStatuses = statuses
            }
            if self.prReviewers != reviewers {
                self.prReviewers = reviewers
            }
        }
    }

    private func computeReviewStatus(pr: PullRequest, service: GitHubService) async -> (PRReviewStatus?, [String]) {
        async let reviewsResult = service.fetchReviews(repo: pr.repoFullName, number: pr.number)
        async let detailResult = service.fetchPRDetail(repo: pr.repoFullName, number: pr.number)

        let reviews = await reviewsResult
        let detail = await detailResult

        // Reviewers who have been (re-)requested and haven't submitted a new review
        let pendingReviewerLogins = Set(detail?.requestedReviewers.map(\.login) ?? [])

        // All reviewer logins: pending + those who already reviewed
        let reviewedLogins = Set(reviews.map(\.user.login))
        let allReviewerLogins = Array(pendingReviewerLogins.union(reviewedLogins).subtracting([pr.user.login])).sorted()

        // Group reviews by reviewer, keep only APPROVED or CHANGES_REQUESTED
        var latestByReviewer: [String: PRReview] = [:]
        for review in reviews {
            let state = review.state
            guard state == "APPROVED" || state == "CHANGES_REQUESTED" else { continue }

            if let existing = latestByReviewer[review.user.login] {
                if let newDate = review.submittedAt, let existingDate = existing.submittedAt, newDate > existingDate {
                    latestByReviewer[review.user.login] = review
                }
            } else {
                latestByReviewer[review.user.login] = review
            }
        }

        // Exclude reviewers who have been re-requested
        let effectiveReviews = latestByReviewer.filter { !pendingReviewerLogins.contains($0.key) }

        let hasChangesRequested = effectiveReviews.values.contains { $0.state == "CHANGES_REQUESTED" }
        let hasApproved = effectiveReviews.values.contains { $0.state == "APPROVED" }

        if hasChangesRequested {
            return (.changesRequested, allReviewerLogins)
        } else if hasApproved {
            return (.approved, allReviewerLogins)
        }
        return (nil, allReviewerLogins)
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

        // Build starred PR lists
        let allStarred = Array(storedStarredPRs.values).sorted { $0.updatedAt > $1.updatedAt }
        let myPRIds = Set(allMyPRs.map(\.id))
        let reviewIds = Set(allReviewRequests.map(\.id))

        self.starredPRs = allStarred
        self.starredAllGroups = groupByRepo(allStarred, starSort: false)
        self.starredMyPRGroups = groupByRepo(allStarred.filter { myPRIds.contains($0.id) }, starSort: false)
        self.starredReviewGroups = groupByRepo(allStarred.filter { reviewIds.contains($0.id) }, starSort: false)
    }

    private func groupByRepo(_ prs: [PullRequest], starSort: Bool = true) -> [PRGroup] {
        let grouped = Dictionary(grouping: prs) { $0.repoFullName }
        let groups = grouped.map { key, value in
            let sorted: [PullRequest]
            if starSort {
                // Starred PRs first within each group
                sorted = value.sorted { a, b in
                    let aStarred = isStarred(a.id)
                    let bStarred = isStarred(b.id)
                    if aStarred != bStarred { return aStarred }
                    return a.updatedAt > b.updatedAt
                }
            } else {
                sorted = value.sorted { $0.updatedAt > $1.updatedAt }
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
