//
//  AttachmentStore.swift
//  str8ToDo
//
//  TaskItem.attachmentPaths を App Group `attachments/` から読み込む薄いヘルパー。
//  Share Extension（ShareInboxWriter）が書き込み、メインアプリが読み込む。
//

import Foundation
import UIKit

enum AttachmentStore {
    static let appGroupID = "group.str8.todo.str8"
    static let directoryName = "attachments"

    static func directoryURL() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(named name: String) -> URL? {
        directoryURL()?.appendingPathComponent(name)
    }

    static func image(named name: String) -> UIImage? {
        guard let url = url(named: name),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// TaskItem 削除時に呼ぶ。指定パス群のファイルを実消去する。
    static func remove(paths: [String]) {
        guard let dir = directoryURL() else { return }
        for name in paths {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// UIImage を JPEG で保存し、生成した相対ファイル名を返す（手動添付動線用）。
    static func writeJPEG(_ image: UIImage, quality: CGFloat = 0.9) -> String? {
        guard let dir = directoryURL(),
              let data = image.jpegData(compressionQuality: quality) else { return nil }
        let name = "\(UUID().uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970)).jpg"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic])
            return name
        } catch {
            return nil
        }
    }
}
