//
//  p0-selfcheck.swift — Phase 0 の自己チェック（approve チョークポイント＋Band シード）
//
//  実行方法（macOS、リポジトリルートで）:
//    swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
//
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//

import Foundation
import SwiftData

@main
@MainActor
struct P0SelfCheck {
    static func main() throws {
        let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                             Band.self, BandTemplate.self, BandAssignment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let ctx = container.mainContext

        // --- markDone: active → done、completedAt＋unlockDate=翌日0:00 ---
        let t = TaskItem(title: "check")
        ctx.insert(t)
        t.markDone()
        assert(t.status == .done && t.completedAt != nil)
        assert(t.unlockDate != nil && t.unlockDate! > .now, "unlockDate は未来（翌日0:00）")

        // --- ロック中は承認拒否 ---
        assert(t.approve(by: "self-future", context: ctx) == false)
        assert(t.status == .done)

        // --- 解除後に承認 → DayStat が1行・count 1 ---
        t.unlockDate = Date.now.addingTimeInterval(-1)
        assert(t.approve(by: "self-future", context: ctx) == true)
        assert(t.status == .approved && t.approvedAt != nil && t.approverID == "self-future")
        var stats = try ctx.fetch(FetchDescriptor<DayStat>())
        assert(stats.count == 1 && stats[0].completedCount == 1)

        // --- 再承認は no-op（二重カウントなし）---
        assert(t.approve(by: "again", context: ctx) == false)
        stats = try ctx.fetch(FetchDescriptor<DayStat>())
        assert(stats.count == 1 && stats[0].completedCount == 1)
        assert(t.approverID == "self-future")

        // --- 同日の2件目 → 同じ行に +1（upsert）---
        let t2 = TaskItem(title: "check2", status: .done)
        ctx.insert(t2)
        assert(t2.approve(by: "peer", context: ctx) == true)
        stats = try ctx.fetch(FetchDescriptor<DayStat>())
        assert(stats.count == 1 && stats[0].completedCount == 2)

        // --- active からの直接承認は拒否 ---
        let t3 = TaskItem(title: "check3")
        ctx.insert(t3)
        assert(t3.approve(by: "x", context: ctx) == false)

        // --- Band シードは冪等（2回呼んでもテンプレ1つ）---
        BandTemplate.seedDefaultIfNeeded(ctx)
        BandTemplate.seedDefaultIfNeeded(ctx)
        let templates = try ctx.fetch(FetchDescriptor<BandTemplate>())
        assert(templates.count == 1 && templates[0].name == "平日")
        assert(templates[0].orderedBands.count == 5)
        let assignments = try ctx.fetch(FetchDescriptor<BandAssignment>())
        assert(assignments.count == 5)

        // --- resolveTemplate: 月曜日（weekday=2）の割当テンプレが返る ---
        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 7, day: 6))!  // 2026-07-06 月曜
        let resolvedTemplate = BandAssignment.resolveTemplate(for: monday, context: ctx, calendar: cal)
        assert(resolvedTemplate?.name == "平日", "Monday should resolve to weekday template")

        // --- resolveTemplate: 日曜日（weekday=1）は nil ---
        let sunday = cal.date(from: DateComponents(year: 2026, month: 7, day: 5))!  // 2026-07-05 日曜
        let sundayTemplate = BandAssignment.resolveTemplate(for: sunday, context: ctx, calendar: cal)
        assert(sundayTemplate == nil, "Sunday should resolve to nil (no weekend assignment)")

        // --- date 差し替え優先: 特定日に別テンプレを割り当て ---
        let specialTemplate = BandTemplate(name: "特別日")
        ctx.insert(specialTemplate)
        let dateX = cal.startOfDay(for: monday)
        let dateAssignment = BandAssignment(id: UUID(), date: dateX, template: specialTemplate)
        ctx.insert(dateAssignment)
        let specialResolved = BandAssignment.resolveTemplate(for: dateX, context: ctx, calendar: cal)
        assert(specialResolved?.name == "特別日", "Date-specific assignment should take priority over weekday default")

        // --- inverse 検証（テンプレ削除）: テンプレを削除すると割当の template が nil ---
        ctx.delete(specialTemplate)
        try ctx.save()
        let targetID = dateAssignment.id
        let afterDelete = try ctx.fetch(FetchDescriptor<BandAssignment>()).first { $0.id == targetID }
        assert(afterDelete?.template == nil, "Template deletion should nullify assignment.template via inverse")

        // --- inverse 検証（PlaceTag 削除）: PlaceTag を削除するとタスクの place が nil ---
        let placeTag = PlaceTag(name: "Office")
        ctx.insert(placeTag)
        let taskWithPlace = TaskItem(title: "meeting", place: placeTag)
        ctx.insert(taskWithPlace)
        try ctx.save()
        assert(taskWithPlace.place?.name == "Office", "TaskItem should have PlaceTag before deletion")
        ctx.delete(placeTag)
        try ctx.save()
        assert(taskWithPlace.place == nil, "PlaceTag deletion should nullify task.place via inverse")

        print("P0 self-check: ALL PASS")
    }
}
