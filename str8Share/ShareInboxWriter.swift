//
//  ShareInboxWriter.swift
//  str8Share
//
//  Share Extension とメインアプリの inbox 共有ロジック。
//  Extension 側は write() で App Group `share-inbox/` に <uuid>.json と画像ファイルを書き出す。
//  メインアプリ側（ShareInboxDrainer）は inboxDirectoryURL と ShareInboxItem スキーマを共有して読む。
//

import Foundation
import UniformTypeIdentifiers

enum ShareInboxWriter {
    /// App Group 識別子。Widget / メインアプリ / Share Extension 全部で同じ値。
    static let appGroupID = "group.str8.todo.str8"
    /// inbox サブディレクトリ名。JSON と画像ファイルはここに置く。
    static let inboxDirectoryName = "share-inbox"
    /// 添付画像の永続保存先。inbox から drain 後もタスクに紐づけて保持する。
    static let attachmentsDirectoryName = "attachments"

    /// App Group コンテナ内 inbox の URL。Extension も本体も同じパスを見る。
    static func inboxDirectoryURL() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let dir = base.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 画像添付の永続保存先。相対パスを TaskItem.attachmentPaths に保存する。
    static func attachmentsDirectoryURL() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let dir = base.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// NSItemProvider 群からテキストと画像を抽出、App Group に永続化して JSON メタを inbox に書く。
    static func write(text: String?, items: [NSExtensionItem]) async {
        guard let inbox = inboxDirectoryURL(),
              let attachDir = attachmentsDirectoryURL() else { return }

        var textParts: [String] = []
        if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            textParts.append(t)
        }
        var attachmentRelativePaths: [String] = []
        let id = UUID().uuidString

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let path = await copyImage(from: provider, into: attachDir, idPrefix: id) {
                        attachmentRelativePaths.append(path)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let s = await loadURL(from: provider) { textParts.append(s) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let s = await loadText(from: provider) { textParts.append(s) }
                }
            }
        }

        // タイトルは先頭の 1 行、残りは notes に。空でも保存（画像だけ共有もあり得る）。
        let joined = textParts.joined(separator: "\n")
        let firstLine = joined.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let rest = joined.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? ""
        let title = firstLine.isEmpty
            ? (attachmentRelativePaths.isEmpty ? "共有アイテム" : "共有された画像")
            : firstLine

        let item = ShareInboxItem(
            id: id,
            title: title,
            notes: rest,
            attachmentPaths: attachmentRelativePaths,
            createdAt: Date()
        )

        let jsonURL = inbox.appendingPathComponent("\(id).json")
        if let data = try? JSONEncoder.iso8601.encode(item) {
            try? data.write(to: jsonURL, options: [.atomic])
        }
    }

    private static func copyImage(from provider: NSItemProvider, into dir: URL, idPrefix: String) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
                let name = "\(idPrefix)-\(UUID().uuidString.prefix(6)).\(ext)"
                let dest = dir.appendingPathComponent(name)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: name)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                cont.resume(returning: (url as URL?)?.absoluteString)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                cont.resume(returning: (obj as? NSString) as String?)
            }
        }
    }
}

/// inbox JSON のスキーマ。Extension が書き、メインアプリが読む。
struct ShareInboxItem: Codable {
    var id: String
    var title: String
    var notes: String
    /// attachments/ からの相対パス（ファイル名のみ）。
    var attachmentPaths: [String]
    var createdAt: Date
}

extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
