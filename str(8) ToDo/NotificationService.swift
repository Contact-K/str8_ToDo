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
}
