//
//  BandModels.swift
//  str8ToDo
//
//  マイ時間割の枠（Band）・枠セット（BandTemplate）・テンプレ割当（BandAssignment）。
//  ルーティーンは「RRULE 付き枠スナップイベント」で表現し、枠が時間割の器になる
//  （企画書 2026-07-02 改訂。旧・固定スケジュールModelは廃止）。
//

import Foundation
import SwiftData

/// マイ時間割の1枠（コマ）。1限 / 昼 / 午後 / 夜 など。
@Model
final class Band {
    @Attribute(.unique) var id: UUID
    var name: String
    /// 0:00 からの経過分（開始）。ponytail: DateComponents ではなく分単位 Int（単純・比較可能）
    var startMinutes: Int
    /// 同（終了）。24:00 = 1440。
    var endMinutes: Int
    /// テンプレ内の表示順。
    var order: Int

    /// 所属テンプレ（BandTemplate.bands の逆参照）。
    var template: BandTemplate?

    init(id: UUID = UUID(), name: String, startMinutes: Int, endMinutes: Int, order: Int) {
        self.id = id
        self.name = name
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.order = order
    }
}

/// 枠セット（学校の日 / 仕事の日 / フリー など）。
@Model
final class BandTemplate {
    @Attribute(.unique) var id: UUID
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \Band.template)
    var bands: [Band]

    @Relationship(deleteRule: .nullify, inverse: \BandAssignment.template)
    var assignments: [BandAssignment]

    init(id: UUID = UUID(), name: String, bands: [Band] = []) {
        self.id = id
        self.name = name
        self.bands = bands
        self.assignments = []
    }

    /// 表示順に整列した枠。
    var orderedBands: [Band] { bands.sorted { $0.order < $1.order } }
}

/// テンプレ割当。date 指定（特定日の差し替え）が weekday デフォルトより優先される。
@Model
final class BandAssignment {
    @Attribute(.unique) var id: UUID
    /// 曜日デフォルト（1=日 ... 7=土、Calendar.weekday 準拠）。date 指定時は nil。
    var weekday: Int?
    /// 特定日の差し替え（startOfDay をキーにする）。
    var date: Date?

    var template: BandTemplate?

    /// 曜日デフォルト指定（date は nil）。
    init(id: UUID = UUID(), weekday: Int, template: BandTemplate? = nil) {
        self.id = id
        self.weekday = weekday
        self.date = nil
        self.template = template
    }

    /// 特定日差し替え指定（weekday は nil、date は正規化）。
    init(id: UUID = UUID(), date: Date, template: BandTemplate? = nil, calendar: Calendar = .current) {
        self.id = id
        self.weekday = nil
        self.date = calendar.startOfDay(for: date)
        self.template = template
    }
}

// MARK: - 初回シード

extension BandTemplate {
    /// 初回起動時にデフォルトの「平日」テンプレと月〜金の曜日割当をシードする。
    /// 既にテンプレが1つでもあれば何もしない。
    @MainActor
    static func seedDefaultIfNeeded(_ context: ModelContext) {
        var descriptor = FetchDescriptor<BandTemplate>()
        descriptor.fetchLimit = 1
        guard ((try? context.fetch(descriptor)) ?? []).isEmpty else { return }

        let weekdayTemplate = BandTemplate(name: "平日", bands: [
            Band(name: "朝",   startMinutes: 6 * 60,  endMinutes: 9 * 60,  order: 0),
            Band(name: "午前", startMinutes: 9 * 60,  endMinutes: 12 * 60, order: 1),
            Band(name: "昼",   startMinutes: 12 * 60, endMinutes: 13 * 60, order: 2),
            Band(name: "午後", startMinutes: 13 * 60, endMinutes: 18 * 60, order: 3),
            Band(name: "夜",   startMinutes: 18 * 60, endMinutes: 24 * 60, order: 4)
        ])
        context.insert(weekdayTemplate)
        for weekday in 2...6 {   // 月〜金
            context.insert(BandAssignment(weekday: weekday, template: weekdayTemplate))
        }
        try? context.save()
    }
}

// MARK: - テンプレ解決

extension BandAssignment {
    /// 指定日の枠テンプレを解決する。date 指定（特定日差し替え）が weekday デフォルトより優先。
    /// 重複行がある場合は id の昇順で先頭を採用（決定的タイブレーク）。
    @MainActor
    static func resolveTemplate(for day: Date, context: ModelContext, calendar: Calendar = .current) -> BandTemplate? {
        // ponytail: 全件フェッチ。割当は高々数十行、遅くなったら #Predicate 化
        let assignments = (try? context.fetch(FetchDescriptor<BandAssignment>())) ?? []
        let dayStart = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: day)

        // date 指定（特定日差し替え）が優先
        let dateMatches = assignments
            .filter { $0.date == dayStart }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        if let match = dateMatches.first {
            return match.template
        }

        // weekday デフォルト
        let weekdayMatches = assignments
            .filter { $0.weekday == weekday }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return weekdayMatches.first?.template
    }
}
