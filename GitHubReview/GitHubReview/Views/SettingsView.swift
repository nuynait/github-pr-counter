import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var prVM: PRViewModel
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notificationsSection
                menuBarSection
                repoOrderSection
                archivedSection
            }
            .padding(20)
        }
        .frame(minWidth: 420, minHeight: 400)
        .onAppear {
            pollTask = Task {
                while !Task.isCancelled {
                    await checkNotificationStatus()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.headline)

            Text("Get notified when new pull requests are created or when someone requests your review, so you never miss an important code review.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.secondary)

                Text("Push Notifications")
                    .font(.subheadline)

                Spacer()

                if notificationStatus == .authorized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)

                    if notificationStatus == .notDetermined {
                        Button("Enable") {
                            NotificationService.requestPermission()
                            Task {
                                try? await Task.sleep(for: .seconds(1))
                                await checkNotificationStatus()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Open Settings") {
                            openNotificationSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(10)
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Toggle(isOn: $prVM.showNewIndicator) {
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    Text("Show \"new\" indicator on PRs")
                        .font(.subheadline)
                }
            }
            .toggleStyle(.switch)
            .padding(10)
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Menu Bar Customization

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu Bar Customization")
                .font(.headline)

            Toggle(isOn: $prVM.excludeDraftsFromMenuBar) {
                HStack {
                    Image(systemName: "pencil.line")
                        .foregroundStyle(.secondary)

                    Text("Exclude draft PRs from menu bar count")
                        .font(.subheadline)
                }
            }
            .toggleStyle(.switch)
            .padding(10)
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Repository Order

    private var repoOrderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository Order")
                .font(.headline)

            Text("Drag to reorder how repositories appear in the tabs. The order applies to both My PRs and Review Requests.")
                .font(.caption)
                .foregroundStyle(.secondary)

            let repos = prVM.orderedVisibleRepos
            if repos.isEmpty {
                Text("No repositories yet. PRs will appear here once loaded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(10)
            } else {
                VStack(spacing: 0) {
                    ForEach(repos, id: \.self) { repo in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)

                            Text(repo)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Button("Archive") {
                                withAnimation { prVM.archiveRepo(repo) }
                            }
                            .foregroundStyle(.red)
                            .buttonStyle(.plain)
                            .font(.subheadline)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .draggable(repo)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedRepo = items.first,
                                  draggedRepo != repo else { return false }
                            var ordered = prVM.orderedVisibleRepos
                            guard let fromIndex = ordered.firstIndex(of: draggedRepo),
                                  let toIndex = ordered.firstIndex(of: repo) else { return false }
                            ordered.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                            prVM.repoOrder = ordered
                            return true
                        }

                        if repo != repos.last {
                            Divider()
                                .padding(.leading, 10)
                        }
                    }
                }
                .background(.fill.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Archived

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archived Repos (\(prVM.archivedRepos.count))")
                .font(.headline)

            if prVM.archivedRepos.isEmpty {
                Text("No archived repos. Use the Archive button above or right-click a repo header in the tabs.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(10)
            } else {
                VStack(spacing: 0) {
                    ForEach(prVM.archivedRepos.sorted(), id: \.self) { repo in
                        HStack(spacing: 10) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.secondary)

                            Text(repo)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Button("Unarchive") {
                                withAnimation {
                                    prVM.unarchiveRepo(repo)
                                }
                            }
                            .foregroundStyle(.blue)
                            .buttonStyle(.plain)
                            .font(.subheadline)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        if repo != prVM.archivedRepos.sorted().last {
                            Divider()
                        }
                    }
                }
                .background(.fill.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
