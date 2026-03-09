import Foundation
import UserNotifications

enum PREvent {
    // My PRs
    case myPRCreated(PullRequest)
    case myPRMerged(PullRequest)
    case myPRClosed(PullRequest)

    // Review requests
    case reviewRequestAdded(PullRequest)
    case reviewRequestRemoved(PullRequest)
    case reviewPRMerged(PullRequest)
    case reviewPRClosed(PullRequest)

    var title: String {
        switch self {
        case .myPRCreated: return "PR Created"
        case .myPRMerged: return "PR Merged"
        case .myPRClosed: return "PR Closed"
        case .reviewRequestAdded: return "Review Requested"
        case .reviewRequestRemoved: return "Review Request Removed"
        case .reviewPRMerged: return "Reviewed PR Merged"
        case .reviewPRClosed: return "Reviewed PR Closed"
        }
    }

    var subtitle: String {
        switch self {
        case .myPRCreated(let pr):
            return "You created a new pull request"
        case .myPRMerged(let pr):
            return "Your pull request has been merged"
        case .myPRClosed(let pr):
            return "Your pull request has been closed"
        case .reviewRequestAdded(let pr):
            return "\(pr.user.login) requested your review"
        case .reviewRequestRemoved(let pr):
            return "You have been removed from reviewers"
        case .reviewPRMerged(let pr):
            return "\(pr.user.login)'s pull request has been merged"
        case .reviewPRClosed(let pr):
            return "\(pr.user.login)'s pull request has been closed"
        }
    }

    var pr: PullRequest {
        switch self {
        case .myPRCreated(let pr),
             .myPRMerged(let pr),
             .myPRClosed(let pr),
             .reviewRequestAdded(let pr),
             .reviewRequestRemoved(let pr),
             .reviewPRMerged(let pr),
             .reviewPRClosed(let pr):
            return pr
        }
    }
}

enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(events: [PREvent]) {
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = "\(event.title): \(event.pr.title)"
            content.subtitle = event.subtitle
            content.body = "\(event.pr.repoFullName) #\(event.pr.number)"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
