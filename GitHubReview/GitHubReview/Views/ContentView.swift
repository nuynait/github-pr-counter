import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var prVM: PRViewModel
    @State private var showSettings = false
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if authVM.isAuthenticated {
                mainView
            } else {
                LoginView()
            }
        }
    }

    private var myPRsTabTitle: String {
        let count = prVM.myPRUnreadCount
        return count > 0 ? "My PRs (\(count))" : "My PRs"
    }

    private var reviewTabTitle: String {
        let count = prVM.reviewUnreadCount
        return count > 0 ? "Review Requests (\(count))" : "Review Requests"
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                MyPRsView()
                    .tabItem {
                        Label(myPRsTabTitle, systemImage: "arrow.triangle.pull")
                    }
                    .tag(0)

                ReviewRequestsView()
                    .tabItem {
                        Label(reviewTabTitle, systemImage: "eye")
                    }
                    .tag(1)
            }

            statusBar
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if prVM.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    if selectedTab == 0 {
                        prVM.markAllMyPRsAsRead()
                    } else {
                        prVM.markAllReviewsAsRead()
                    }
                } label: {
                    Image(systemName: "eye")
                }
                .help("Mark all as read")

                Button {
                    prVM.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Menu {
                    if let user = authVM.currentUser {
                        Text("Signed in as \(user.login)")
                        Divider()
                    }
                    Button("Settings...") {
                        showSettings = true
                    }
                    Divider()
                    Button("Sign Out") {
                        prVM.stopPolling()
                        authVM.signOut()
                    }
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
        .onAppear {
            if let token = authVM.token, let user = authVM.currentUser {
                prVM.configure(token: token, username: user.login)
            }
        }
        .onChange(of: authVM.currentUser) { _, newUser in
            if let token = authVM.token, let user = newUser {
                prVM.configure(token: token, username: user.login)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(prVM)
        }
    }

    private var statusBar: some View {
        HStack {
            if let error = prVM.error {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let lastUpdated = prVM.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
