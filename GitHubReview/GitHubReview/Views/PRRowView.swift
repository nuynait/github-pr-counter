import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    @EnvironmentObject var prVM: PRViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Unread indicator
            if prVM.isUnread(pr.id) {
                Button {
                    withAnimation { prVM.markAsRead(pr.id) }
                } label: {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(.plain)
                .help("Mark as read")
            } else {
                Spacer()
                    .frame(width: 8)
            }

            // Main PR content
            Button {
                prVM.markAsRead(pr.id)
                if let url = pr.browserURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pr.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        if pr.isDraft {
                            Text("Draft")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.gray.opacity(0.2))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }

                        if let state = prVM.resolvedState(pr.id) {
                            Text(state == "merged" ? "Merged" : "Closed")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(state == "merged" ? Color.purple.opacity(0.2) : Color.red.opacity(0.2))
                                .clipShape(Capsule())
                                .foregroundStyle(state == "merged" ? .purple : .red)
                        }
                    }

                    HStack(spacing: 4) {
                        Text("#\(pr.number)")
                            .font(.caption.monospaced())
                        Text("by \(pr.user.login)")
                            .font(.caption)
                        Text("·")
                            .font(.caption)
                        Text(pr.timeAgo)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Star button
            Button {
                withAnimation { prVM.toggleStar(pr.id) }
            } label: {
                Image(systemName: prVM.isStarred(pr.id) ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(prVM.isStarred(pr.id) ? Color.yellow : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help(prVM.isStarred(pr.id) ? "Unstar" : "Star")
        }
        .padding(.vertical, 2)
        .padding(.trailing, 8)
    }
}
