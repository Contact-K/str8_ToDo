import Foundation
import UserNotifications
import os.log

@MainActor
enum NotificationService {
    /// 通知許可を要求。許可されたら true。
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    /// タスクの通知を貼り直す（既存をキャンセルしてから、startDate と notificationOffsets を元に再登録）。
    static func reschedule(for task: TaskItem) {
        cancel(for: task)

        guard let startDate = task.startDate else { return }

        for offset in task.notificationOffsets {
            let notificationTime = startDate.addingTimeInterval(TimeInterval(-offset * 60))

            if notificationTime < Date() {
                continue
            }

            let identifier = "task-\(task.id.uuidString)-\(offset)"
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = "まもなく開始"
            content.sound = .default

            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    os_log("Failed to schedule notification for task %@: %@", log: .default, type: .error, task.id.uuidString, error.localizedDescription)
                }
            }
        }
    }

    /// タスクの通知を全てキャンセル。
    static func cancel(for task: TaskItem) {
        let identifiers = task.notificationOffsets.map { offset in
            "task-\(task.id.uuidString)-\(offset)"
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - 週次締め通知

    /// 週次締めリマインダーの通知 identifier。
    static let weeklyReviewIdentifier = "weekly-review"

    /// 週次締めリマインダーを登録（既存があれば置き換え）。
    /// - Parameters:
    ///   - weekday: 0=日, 1=月, ..., 6=土。iOS Calendar の 1-indexed（1=日, 7=土）に変換して trigger に渡す。
    ///   - hour: 0-23
    static func scheduleWeeklyReview(weekday: Int, hour: Int) {
        // 既存を除去
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyReviewIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "週次締めの時間です"
        content.body = "今週を振り返って、来週の予定を確認しましょう"
        content.sound = .default

        var components = DateComponents()
        // iOS Calendar.Component.weekday: 1=日, 2=月, ..., 7=土。引数 weekday(0=日..6=土) に +1 して合わせる。
        components.weekday = weekday + 1
        components.hour = hour
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyReviewIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                assertionFailure("weekly review scheduling failed: \(error)")
            }
        }
    }

    /// 週次締めリマインダーを取り消し（通知OFFなどで使用）。
    static func cancelWeeklyReview() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyReviewIdentifier])
    }
}
