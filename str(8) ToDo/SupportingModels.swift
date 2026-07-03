//
//  SupportingModels.swift
//  str8ToDo
//
//  カテゴリ・場所タグ・日次集計キャッシュ。
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
