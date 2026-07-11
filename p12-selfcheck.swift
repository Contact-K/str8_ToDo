// Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library "str(8) ToDo/FreeSlotSuggester.swift" p12-selfcheck.swift -o /tmp/p12check && /tmp/p12check

import Foundation

@main
struct P12SelfCheck {
    static func main() {
        let baseDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // Test 1: effectiveDuration logic
        do {
            let d1 = FreeSlotSuggester.effectiveDuration(actualDuration: 600, duration: 900)
            assert(d1 == 600.0, "actualDuration > 0 should be preferred")

            let d2 = FreeSlotSuggester.effectiveDuration(actualDuration: nil, duration: 900)
            assert(d2 == 900.0, "duration > 0 when no actual")

            let d3 = FreeSlotSuggester.effectiveDuration(actualDuration: nil, duration: 0)
            assert(d3 == 1800.0, "fallback when both invalid")

            let d4 = FreeSlotSuggester.effectiveDuration(actualDuration: 0, duration: 900)
            assert(d4 == 900.0, "actualDuration=0 is invalid, use duration")
        }

        // Test 2:収まらない空きにはタスクが提案されない
        do {
            let gap30 = (start: baseDate, duration: 30.0 * 60)  // 30分
            let candidate45 = FreeSlotSuggester.Candidate(id: UUID(), phaseRank: 0, effectiveDuration: 45.0 * 60, sortIndex: 0)
            let candidate20 = FreeSlotSuggester.Candidate(id: UUID(), phaseRank: 0, effectiveDuration: 20.0 * 60, sortIndex: 1)

            let result = FreeSlotSuggester.suggest(gaps: [gap30], candidates: [candidate45, candidate20])

            // 45分は収まらない、20分のみ
            assert(result[baseDate]?.count == 1, "Only 20-min task should fit")
            assert(result[baseDate]?.first?.duration == 20.0 * 60, "20-min task should be suggested")
        }

        // Test 3: 貪欲順（deadline → weight）
        do {
            let gap300 = (start: baseDate, duration: 300.0 * 60)  // 300分

            let id1 = UUID()
            let id2 = UUID()
            let id3 = UUID()

            // phaseRank=0, 100分
            let c1 = FreeSlotSuggester.Candidate(id: id1, phaseRank: 0, effectiveDuration: 100.0 * 60, sortIndex: 0)
            // phaseRank=0, 80分 (軽음)
            let c2 = FreeSlotSuggester.Candidate(id: id2, phaseRank: 0, effectiveDuration: 80.0 * 60, sortIndex: 1)
            // phaseRank=1 (締切遠い)
            let c3 = FreeSlotSuggester.Candidate(id: id3, phaseRank: 1, effectiveDuration: 60.0 * 60, sortIndex: 2)

            let result = FreeSlotSuggester.suggest(gaps: [gap300], candidates: [c3, c1, c2])

            assert(result[baseDate]?.count == 3, "All 3 should fit in 300-min gap")

            let suggestions = result[baseDate]!
            assert(suggestions[0].taskID == id1, "100-min (phaseRank=0, heaviest) should be first")
            assert(suggestions[1].taskID == id2, "80-min (phaseRank=0, second) should be second")
            assert(suggestions[2].taskID == id3, "60-min (phaseRank=1, lower priority) should be third")
        }

        // Test 4: 1タスク高々1回
        do {
            let gap1 = (start: baseDate, duration: 60.0 * 60)
            let gap2 = (start: Date(timeInterval: 120.0 * 60, since: baseDate), duration: 60.0 * 60)

            let taskID = UUID()
            let candidate = FreeSlotSuggester.Candidate(id: taskID, phaseRank: 0, effectiveDuration: 30.0 * 60, sortIndex: 0)

            let result = FreeSlotSuggester.suggest(gaps: [gap1, gap2], candidates: [candidate])

            // Count how many gaps have this task
            var count = 0
            for (_, suggestions) in result {
                count += suggestions.filter { $0.taskID == taskID }.count
            }
            assert(count == 1, "Task should appear exactly once across all gaps")
        }

        // Test 5: 複数パック＋cursor前進（sortIndex タイブレーク検証）
        do {
            let gap60 = (start: baseDate, duration: 60.0 * 60)  // 60分

            let id1 = UUID()
            let id2 = UUID()
            let id3 = UUID()

            let c1 = FreeSlotSuggester.Candidate(id: id1, phaseRank: 0, effectiveDuration: 20.0 * 60, sortIndex: 0)
            let c2 = FreeSlotSuggester.Candidate(id: id2, phaseRank: 0, effectiveDuration: 20.0 * 60, sortIndex: 1)
            let c3 = FreeSlotSuggester.Candidate(id: id3, phaseRank: 0, effectiveDuration: 20.0 * 60, sortIndex: 2)

            let result = FreeSlotSuggester.suggest(gaps: [gap60], candidates: [c1, c2, c3])

            assert(result[baseDate]?.count == 3, "All 3 20-min tasks should fit in 60-min gap")

            let suggestions = result[baseDate]!
            // sortIndex による並び順（昇順）
            assert(suggestions[0].taskID == id1, "First (sortIndex=0) should be id1")
            assert(suggestions[1].taskID == id2, "Second (sortIndex=1) should be id2")
            assert(suggestions[2].taskID == id3, "Third (sortIndex=2) should be id3")
            // start 時刻の前進
            assert(suggestions[0].start == baseDate, "First should start at gap.start")
            assert(suggestions[1].start == Date(timeInterval: 20.0 * 60, since: baseDate), "Second should start +20min")
            assert(suggestions[2].start == Date(timeInterval: 40.0 * 60, since: baseDate), "Third should start +40min")
        }

        // Test 6: 入らない空きはキー無し
        do {
            let gap10 = (start: baseDate, duration: 10.0 * 60)  // 10分
            let gap100 = (start: Date(timeInterval: 120.0 * 60, since: baseDate), duration: 100.0 * 60)  // 100分

            let candidate = FreeSlotSuggester.Candidate(id: UUID(), phaseRank: 0, effectiveDuration: 50.0 * 60, sortIndex: 0)

            let result = FreeSlotSuggester.suggest(gaps: [gap10, gap100], candidates: [candidate])

            assert(result[baseDate] == nil, "10-min gap should not have key (task doesn't fit)")
            assert(result[gap100.start] != nil, "100-min gap should have key")
            assert(result[gap100.start]?.count == 1, "100-min gap should have 1 task")
        }

        // Test 7: 空きぴったり（等号境界、effectiveDuration <= 残り）
        do {
            let gap30 = (start: baseDate, duration: 30.0 * 60)  // 30分ちょうど
            let candidate30 = FreeSlotSuggester.Candidate(id: UUID(), phaseRank: 0, effectiveDuration: 30.0 * 60, sortIndex: 0)

            let result = FreeSlotSuggester.suggest(gaps: [gap30], candidates: [candidate30])

            assert(result[baseDate] != nil, "30-min gap should have key")
            assert(result[baseDate]?.count == 1, "30-min task should fit in 30-min gap")
            assert(result[baseDate]?.first?.duration == 30.0 * 60, "Suggested duration should be 30 min")
            assert(result[baseDate]?.first?.start == baseDate, "Start should match gap start")
        }

        print("P12 self-check: ALL PASS")
    }
}
