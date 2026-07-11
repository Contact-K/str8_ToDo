//
//  FocusSession.swift
//  str8ToDo
//
//  集中セッションの記録。砂時計タイマーの完了で1行作られ、
//  紐付けタスクの actualDuration に累積する（W2 の学習データ）。
//

import Foundation
import SwiftData

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date
    /// TaskItem への弱い参照（リレーションにしない=削除に強い）。
    var taskID: UUID?
    /// 科目（P10）。タイマーで科目を選んで終了すると記録される（未選択なら nil）。ponytail: 生 UUID 保持（@Relationship 非採用）。Subject 削除 UI での nullify は現状 UI 側の責務。
    var subjectID: UUID?
    /// 集中ルーム（P14）。セッションが生成されたルームの ID。
    var roomID: UUID? = nil
    /// ルーム参加者数（P14）。ホストを含む。
    var participantCount: Int? = nil
    /// 集中ルームのホスト識別子（P14。peer.hostPeerID の displayName）。TaskItem.approverID パターン踏襲。
    var approverID: String? = nil

    /// 週報の focusTotalSec 集計（WeekReportSource）が end の範囲 fetch で年単位に線形劣化しないための Index。
    #Index<FocusSession>([\.end])

    init(id: UUID = UUID(), start: Date, end: Date, taskID: UUID? = nil, subjectID: UUID? = nil, roomID: UUID? = nil, participantCount: Int? = nil, approverID: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.taskID = taskID
        self.subjectID = subjectID
        self.roomID = roomID
        self.participantCount = participantCount
        self.approverID = approverID
    }

    /// セッションを保存し、紐付けタスクがあれば actualDuration に経過を累積する。
    @MainActor
    @discardableResult
    static func record(start: Date, end: Date, task: TaskItem?, subject: Subject? = nil, context: ModelContext) -> FocusSession {
        let session = FocusSession(start: start, end: end, taskID: task?.id, subjectID: subject?.id)
        context.insert(session)
        if let task {
            let duration = end.timeIntervalSince(start)
            // ponytail: 時計変更による負値・巨大値の混入防止。0〜24時間にクランプ
            let clampedDuration = max(0, min(duration, 24 * 3600))
            task.actualDuration = (task.actualDuration ?? 0) + clampedDuration
        }
        do {
            try context.save()
        } catch {
            print("FocusSession.record: context.save() failed: \(error)")
        }
        return session
    }
}
