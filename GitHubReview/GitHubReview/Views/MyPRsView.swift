import SwiftUI

struct MyPRsView: View {
    @EnvironmentObject var prVM: PRViewModel

    var body: some View {
        Group {
            if prVM.myPRGroups.isEmpty && !prVM.isLoading {
                ContentUnavailableView(
                    "No Open PRs",
                    systemImage: "checkmark.circle",
                    description: Text("You don't have any open pull requests.")
                )
            } else {
                List {
                    ForEach(prVM.myPRGroups) { group in
                        RepoSectionView(
                            group: group,
                            badgeColor: .blue,
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
            get: { prVM.isRepoExpanded(repoName, tab: .myPRs) },
            set: { prVM.setRepoExpanded(repoName, tab: .myPRs, expanded: $0) }
        )
    }
}
