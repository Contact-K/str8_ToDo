//
//  ShareInboxDrainer.swift
//  str8ToDo
//
//  Share Extension が App Group inbox に置いた JSON を、メインアプリ起動時（ScenePhase.active）
//  に吸い上げて TaskItem を作成する。画像は attachments/ に残し、attachmentPaths に相対パスで紐付け。
//

import Foundation
import SwiftData

@MainActor
enum ShareInboxDrainer {
    /// inbox 内の全 JSON を TaskItem 化。処理後 JSON は削除、画像ファイルは残す。
    static func drain(into context: ModelContext) {
        guard let inbox = ShareInboxWriter.inboxDirectoryURL() else { return }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil))
            ?? []
        var didInsert = false
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let item = try? JSONDecoder.iso8601.decode(ShareInboxItem.self, from: data) else {
                try? fm.removeItem(at: url)
                continue
            }
            let task = TaskItem(
                title: item.title,
                startDate: item.startDate,
                duration: item.startDate != nil ? Double((item.durationMin ?? 60) * 60) : 0,
                phase: .today,
                notes: item.notes,
                attachmentPaths: item.attachmentPaths
            )
            context.insert(task)
            didInsert = true
            try? fm.removeItem(at: url)
        }
        if didInsert {
            do {
                try context.save()
            } catch {
                print("[ShareInboxDrainer] save failed: \(error)")
                assertionFailure("Share drain save failed: \(error)")
            }
        }
    }
}
