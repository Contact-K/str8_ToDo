import Foundation

/// 提案1件: どのタスクを・いつ・どれだけの長さで置くか。
struct SlotSuggestion: Identifiable, Equatable {
    let taskID: UUID
    let start: Date
    let duration: TimeInterval
    var id: UUID { taskID }
}

enum FreeSlotSuggester {
    /// フィット候補（純データ。TaskItem を持ち込まない）。
    struct Candidate {
        let id: UUID
        let phaseRank: Int          // 締切近さの代理: .now=0, .today=1（小さいほど優先）
        let effectiveDuration: TimeInterval
        let sortIndex: Int          // 決定的タイブレーク
    }

    /// 実効所要: 実績(actualDuration>0)を優先、無ければ見積(duration>0)、どちらも無効なら fallback。
    static func effectiveDuration(actualDuration: TimeInterval?, duration: TimeInterval, fallback: TimeInterval = 1800) -> TimeInterval {
        if let a = actualDuration, a > 0 { return a }
        if duration > 0 { return duration }
        return fallback
    }

    /// 貪欲フィット。candidates を「締切近い順(phaseRank昇順)→重い順(effectiveDuration降順)→sortIndex昇順→id昇順」で整列し、
    /// 各空きに先頭から詰める（First-Fit-Decreasing 風、1タスクは全空き通して高々1回）。
    /// 各空き内では start から順に配置し、配置ごとに cursor を effectiveDuration 分進める。
    /// - Returns: 空きの start をキーにした提案列（提案が1件以上ある空きのみキーを持つ）。収まらないタスクは現れない。
    static func suggest(gaps: [(start: Date, duration: TimeInterval)],
                        candidates: [Candidate]) -> [Date: [SlotSuggestion]] {
        // 1. candidates を (phaseRank, -effectiveDuration, sortIndex, id.uuidString) で整列
        let sorted = candidates.sorted { a, b in
            if a.phaseRank != b.phaseRank {
                return a.phaseRank < b.phaseRank
            }
            if a.effectiveDuration != b.effectiveDuration {
                return a.effectiveDuration > b.effectiveDuration
            }
            if a.sortIndex != b.sortIndex {
                return a.sortIndex < b.sortIndex
            }
            return a.id.uuidString < b.id.uuidString
        }

        // 2. placed: Set<UUID> を用意
        var placed = Set<UUID>()
        var result: [Date: [SlotSuggestion]] = [:]

        // 3. 各 gap（与えられた順＝時刻順前提）について:
        for gap in gaps {
            var cursor = gap.start
            var remaining = gap.duration
            var suggestions: [SlotSuggestion] = []

            // 整列済み candidates を走査
            for candidate in sorted {
                // 未 placed かつ effectiveDuration <= remaining なら
                if !placed.contains(candidate.id) && candidate.effectiveDuration <= remaining {
                    suggestions.append(SlotSuggestion(taskID: candidate.id, start: cursor, duration: candidate.effectiveDuration))
                    cursor = Date(timeInterval: candidate.effectiveDuration, since: cursor)
                    remaining -= candidate.effectiveDuration
                    placed.insert(candidate.id)
                }
            }

            // 4. 1件も入らなかった gap はキーを作らない
            if !suggestions.isEmpty {
                result[gap.start] = suggestions
            }
        }

        return result
    }
}
