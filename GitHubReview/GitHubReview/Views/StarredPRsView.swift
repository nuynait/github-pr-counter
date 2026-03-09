import SwiftUI

struct StarredPRsView: View {
    @EnvironmentObject var prVM: PRViewModel
    @State private var selectedInnerTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Inner tab picker
            Picker("", selection: $selectedInnerTab) {
                Text("All").tag(0)
                Text("My PRs").tag(1)
                Text("Reviews").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Content
            switch selectedInnerTab {
            case 0:
                starredList(groups: prVM.starredAllGroups, emptyTitle: "No Starred PRs", emptyDescription: "Star a PR to keep track of it here.")
            case 1:
                starredList(groups: prVM.starredMyPRGroups, emptyTitle: "No Starred PRs", emptyDescription: "None of your starred PRs are in My PRs.")
            case 2:
                starredList(groups: prVM.starredReviewGroups, emptyTitle: "No Starred PRs", emptyDescription: "None of your starred PRs are in Review Requests.")
            default:
                EmptyView()
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func starredList(groups: [PRGroup], emptyTitle: String, emptyDescription: String) -> some View {
        if groups.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "star",
                description: Text(emptyDescription)
            )
        } else {
            List {
                ForEach(groups) { group in
                    RepoSectionView(
                        group: group,
                        badgeColor: .yellow,
                        isExpanded: binding(for: group.id),
                        onArchive: { prVM.archiveRepo(group.repoName) }
                    )
                }
            }
            .listStyle(.plain)
        }
    }

    private func binding(for repoName: String) -> Binding<Bool> {
        Binding(
            get: { prVM.isRepoExpanded(repoName, tab: .starred) },
            set: { prVM.setRepoExpanded(repoName, tab: .starred, expanded: $0) }
        )
    }
}
