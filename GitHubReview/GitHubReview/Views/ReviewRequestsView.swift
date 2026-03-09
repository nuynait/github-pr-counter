import SwiftUI

struct ReviewRequestsView: View {
    @EnvironmentObject var prVM: PRViewModel

    var body: some View {
        Group {
            if prVM.reviewGroups.isEmpty && !prVM.isLoading {
                ContentUnavailableView(
                    "No Review Requests",
                    systemImage: "eye",
                    description: Text("No one has requested your review.")
                )
            } else {
                List {
                    ForEach(prVM.reviewGroups) { group in
                        RepoSectionView(
                            group: group,
                            badgeColor: .orange,
                            isExpanded: binding(for: group.id),
                            onArchive: { prVM.archiveRepo(group.repoName) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func binding(for repoName: String) -> Binding<Bool> {
        Binding(
            get: { prVM.isRepoExpanded(repoName, tab: .reviews) },
            set: { prVM.setRepoExpanded(repoName, tab: .reviews, expanded: $0) }
        )
    }
}
