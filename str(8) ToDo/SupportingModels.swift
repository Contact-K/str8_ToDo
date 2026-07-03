//
//  SupportingModels.swift
//  str8ToDo
//
//  カテゴリ・固定スケジュール・場所タグ・日次集計キャッシュ。
//

import Foundation
import SwiftData

/// タスクの分類。年ビューの積み上げ棒や色分けに使う。
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    /// "#RRGGBB" 形式のカラー。
    var colorHex: String
    var symbolName: String

    @Relationship(deleteRule: .nullify)
    var tasks: [TaskItem]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#4F8DFD",
        symbolName: String = "tag.fill",
        tasks: [TaskItem] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.tasks = tasks
    }
}

/// 毎日・毎週の固定枠（授業・バイトなど）。日ビューの背景レーンに敷く。
@Model
final class FixedSchedule {
    @Attribute(.unique) var id: UUID
    var title: String
    /// 0=日 ... 6=土。曜日の集合。
    var weekdays: [Int]
    /// 0:00 からの経過秒（開始）。
    var startSeconds: Int
    /// 同（終了）。
    var endSeconds: Int
    var colorHex: String

    init(
        id: UUID = UUID(),
        title: String,
        weekdays: [Int],
        startSeconds: Int,
        endSeconds: Int,
        colorHex: String = "#9AA0A6"
    ) {
        self.id = id
        self.title = title
        self.weekdays = weekdays
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.colorHex = colorHex
    }
}

/// 場所タグ。出発時刻の逆算（後続フェーズ）で座標を使う。
@Model
final class PlaceTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var latitude: Double?
    var longitude: Double?

    init(id: UUID = UUID(), name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 日次の事前集計キャッシュ。年ビューの草グラフを高速描画するため。
@Model
final class DayStat {
    /// その日の 00:00（startOfDay）をキーにする。
    @Attribute(.unique) var day: Date
    /// 承認済みタスク数。
    var completedCount: Int
    /// 集中時間の合計（秒）。
    var focusSeconds: Int

    init(day: Date, completedCount: Int = 0, focusSeconds: Int = 0) {
        self.day = day
        self.completedCount = completedCount
        self.focusSeconds = focusSeconds
    }
}
