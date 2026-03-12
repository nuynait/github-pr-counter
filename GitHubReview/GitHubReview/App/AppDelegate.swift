import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    let authVM = AuthViewModel()
    let prVM = PRViewModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        observeBadgeCounts()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
    }

    // Show notifications even when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateButton(button, reviewCount: 0, myPRCount: 0)
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc private func statusItemClicked() {
        if let window = NSApp.windows.first(where: { $0.title.contains("GitHub Review") || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            for window in NSApp.windows {
                if window.level == .normal {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeBadgeCounts() {
        prVM.$reviewRequests
            .combineLatest(prVM.$myPRs, prVM.$excludeDraftsFromMenuBar)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                guard let self, let button = self.statusItem.button else { return }
                self.updateButton(button, reviewCount: self.prVM.menuBarReviewCount, myPRCount: self.prVM.menuBarMyPRCount)
            }
            .store(in: &cancellables)
    }

    private func updateButton(_ button: NSStatusBarButton, reviewCount: Int, myPRCount: Int) {
        let attributed = NSMutableAttributedString()

        let iconAttachment = NSTextAttachment()
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let icon = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "GitHub Review")?
            .withSymbolConfiguration(config) {
            iconAttachment.image = icon
        }
        attributed.append(NSAttributedString(attachment: iconAttachment))

        if reviewCount > 0 {
            attributed.append(NSAttributedString(string: " "))
            let reviewBadge = NSAttributedString(
                string: "\(reviewCount)",
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
                ]
            )
            attributed.append(reviewBadge)
        }

        if myPRCount > 0 {
            attributed.append(NSAttributedString(string: " "))
            let myPRBadge = NSAttributedString(
                string: "\(myPRCount)",
                attributes: [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
                ]
            )
            attributed.append(myPRBadge)
        }

        button.attributedTitle = attributed
    }
}
