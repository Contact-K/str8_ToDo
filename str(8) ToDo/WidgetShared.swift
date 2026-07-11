//
//  WidgetShared.swift
//  str(8) ToDo
//
//  App & Widget 共有型（App Group 経由の JSON 交換用）。
//  純 Foundation のみ（SwiftData/WidgetKit を import しない）。
//

import Foundation
import os

enum AppGroup {
    static let identifier = "group.str8.todo.str8"
}

private let widgetLog = Logger(subsystem: "str8.todo.str8", category: "widget-snapshot")

/// ウィジェット表示用スナップショット。アプリが算出して App Group に書き出す。
struct WidgetSnapshot: Codable {
    var generatedAt: Date
    /// 今日の残り時刻付きタスク（active・start 昇順）。境界エントリ生成と「次のカード」表示の元。
    var upcoming: [Card]
    /// 今日の枠（マイ時間割）。
    var bands: [BandInfo]
    /// 今日の達成数（DayStat.completedCount）。
    var achievementCount: Int
    /// 未確定件数（status == .done）。
    var unconfirmedCount: Int

    struct Card: Codable {
        var title: String
        var start: Date
        var end: Date
        var colorHex: String?   // nil = カテゴリ/既定色
        var isTimePinned: Bool
    }

    struct BandInfo: Codable {
        var name: String
        var startMinutes: Int
        var endMinutes: Int
    }
}

// MARK: - 表示ロジック（純ロジック。ウィジェットと p11-selfcheck が共有）

extension WidgetSnapshot {
    /// 生成が今日でなければ鮮度切れ（達成数・カードが前日以前の可能性）。
    var isStale: Bool { !Calendar.current.isDateInToday(generatedAt) }

    /// entry.date 基準で「今」表示すべきカード（end が date より後の最初の upcoming）。
    /// upcoming は start 昇順前提。時間経過で自動的に次のカードへ進む。
    func currentCard(at date: Date) -> Card? {
        upcoming.first { $0.end > date }
    }

    /// タイムラインエントリを打つ境界時刻（各カードの開始/終了のうち now より後）。
    /// 昇順・重複除去・先頭 cap 件。ponytail: WidgetKit のエントリ上限対策、1日最大48境界≒24タスクまでカバー
    func timelineBoundaries(after now: Date, cap: Int = 48) -> [Date] {
        let future = upcoming.flatMap { [$0.start, $0.end] }.filter { $0 > now }
        return Array(Set(future).sorted().prefix(cap))
    }
}

/// App Group 共有コンテナ経由の読み書き。失敗は握りつぶして nil/no-op（ウィジェットもアプリも落とさない）。
enum WidgetSnapshotStore {
    static func url() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard var url = url() else {
            widgetLog.error("write: App Group container URL not available")
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // バックアップ除外（NSFileProtection と合わせて平文個人情報の露出を最小化）
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        } catch {
            widgetLog.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let url = url() else {
            widgetLog.error("read: App Group container URL not available")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetSnapshot.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil   // 初回起動は正常
        } catch {
            widgetLog.error("read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
