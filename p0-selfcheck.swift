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

        print("P0 self-check: ALL PASS")
    }
}
