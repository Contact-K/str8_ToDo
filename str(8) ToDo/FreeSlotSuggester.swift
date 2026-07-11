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

    /// gap が過去に食い込む場合に now でクランプ。完全に過去なら nil、跨ぐなら (now, 残り)、完全に未来なら (start, duration)。
    static func clampGap(start: Date, duration: TimeInterval, now: Date) -> (start: Date, duration: TimeInterval)? {
        if start >= now { return (start, duration) }
        let clipped = duration - now.timeIntervalSince(start)
        return clipped > 0 ? (now, clipped) : nil
    }

    /// 貪欲フィット。candidates を「締切近い順(phaseRank昇順)→重い順(effectiveDuration降順)→sortIndex昇順→id昇順」で整列し、
    /// 各空きに先頭から詰める（First-Fit-Decreasing 風、1タスクは全空き通して高々1回）。
    /// 各空き内では start から順に配置し、配置ごとに cursor を effectiveDuration 分進める。
    /// - Returns: `gaps` と同順の 2 次元配列。`result[i]` は `gaps[i]` に対する提案列（空きに何も入らなかった場合は空配列）。
    ///   ponytail: 以前は `[Date: [SlotSuggestion]]` を返していたが、同一 `gap.start` の複数 gap で後勝ち上書きが起きるため index 対応に変更。
    ///   ponytail: 実 dueDate なし → SortPhase.now/today を締切近さの代理に利用。`.week` 拡張時は phaseRank の割り当てを見直す。
    static func suggest(gaps: [(start: Date, duration: TimeInterval)],
                        candidates: [Candidate]) -> [[SlotSuggestion]] {
        // duration=0（見積無し・実績無し・fallback にも達しない）候補は「重い順」の並びを崩すため除外
        let validCandidates = candidates.filter { $0.effectiveDuration > 0 }

        let sorted = validCandidates.sorted { a, b in
            if a.phaseRank != b.phaseRank { return a.phaseRank < b.phaseRank }
            if a.effectiveDuration != b.effectiveDuration { return a.effectiveDuration > b.effectiveDuration }
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.id.uuidString < b.id.uuidString
        }

        var placed = Set<UUID>()
        var result: [[SlotSuggestion]] = []
        result.reserveCapacity(gaps.count)

        for gap in gaps {
            var cursor = gap.start
            var remaining = gap.duration
            var suggestions: [SlotSuggestion] = []

            for candidate in sorted {
                if !placed.contains(candidate.id) && candidate.effectiveDuration <= remaining {
                    suggestions.append(SlotSuggestion(taskID: candidate.id, start: cursor, duration: candidate.effectiveDuration))
                    cursor = Date(timeInterval: candidate.effectiveDuration, since: cursor)
                    remaining -= candidate.effectiveDuration
                    placed.insert(candidate.id)
                }
            }

            result.append(suggestions)
        }

        return result
    }
}
