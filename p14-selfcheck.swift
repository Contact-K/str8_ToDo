// Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library "str(8) ToDo/FocusRoom.swift" "str(8) ToDo/RoomMessage.swift" p14-selfcheck.swift -o /tmp/p14check && /tmp/p14check

import Foundation

@main
struct P14SelfCheck {
    static func main() {
        // Test 1: isReadyToStart
        do {
            let empty: [Participant] = []
            assert(!FocusRoom.isReadyToStart(participants: empty), "empty -> false")

            let allFaceDown = [
                Participant(id: "a", isFaceDown: true, isHost: true),
                Participant(id: "b", isFaceDown: true, isHost: false),
            ]
            assert(FocusRoom.isReadyToStart(participants: allFaceDown), "all faceDown -> true")

            let mixed = [
                Participant(id: "a", isFaceDown: true, isHost: true),
                Participant(id: "b", isFaceDown: false, isHost: false),
            ]
            assert(!FocusRoom.isReadyToStart(participants: mixed), "one not faceDown -> false")
        }

        // Test 2: nextStateAfterLeft
        do {
            let host = Participant(id: "h", isFaceDown: true, isHost: true)
            let guest = Participant(id: "g", isFaceDown: true, isHost: false)

            // 全員離脱 -> aborted
            assert(FocusRoom.nextStateAfterLeft(current: .running, remaining: []) == .aborted, "empty -> aborted")

            // ホスト離脱 -> aborted
            assert(FocusRoom.nextStateAfterLeft(current: .running, remaining: [guest]) == .aborted, "host left -> aborted")

            // ゲスト離脱、ホスト残 -> current 維持
            assert(FocusRoom.nextStateAfterLeft(current: .running, remaining: [host]) == .running, "guest left, host remains -> running")
        }

        // Test 3: clockOffset（対称ネット・ホスト時刻がゲストより 5 秒進んでいるケース）
        do {
            // ゲスト epoch t=100 で ping 送信、片道 0.1 秒でホスト到着（ホスト epoch=105.1）、
            // 即応答（hostReplyTime=105.1）、片道 0.1 秒でゲスト到着（ゲスト epoch=100.2）。
            let offset = FocusRoom.clockOffset(pingSentAt: 100.0, pongReceivedAt: 100.2, hostReplyTime: 105.1)
            // 期待: rtt=0.2 → oneWay=0.1 → estimate=100.1 → offset=105.1-100.1=5.0
            assert(abs(offset - 5.0) < 0.001, "offset 5.0 expected, got \(offset)")
        }

        // Test 4: localStartTime（ホスト startAt=200、offset=5.0 → ゲスト側 195）
        do {
            let local = FocusRoom.localStartTime(hostStartAt: 200.0, offset: 5.0)
            assert(abs(local - 195.0) < 0.001, "local start 195.0 expected, got \(local)")
        }

        // Test 5: recommendedHostStartAt（既定 3 秒バッファ）
        do {
            let hostStart = FocusRoom.recommendedHostStartAt(hostNow: 1000.0)
            assert(abs(hostStart - 1003.0) < 0.001, "hostStart 1003.0 expected, got \(hostStart)")

            let custom = FocusRoom.recommendedHostStartAt(hostNow: 1000.0, delaySec: 5)
            assert(abs(custom - 1005.0) < 0.001, "custom delay hostStart 1005.0 expected, got \(custom)")
        }

        // Test 6: 受け入れ基準「2台が1秒未満のズレで同時開始」の数値検証
        do {
            // ホスト epoch と ゲスト epoch が実際に 5 秒ズレていて、対称ネットで RTT=0.05 秒
            let pingSentAt = 100.0
            let pongReceivedAt = 100.05
            let hostReplyTime = 105.025  // ホストは受信時 (100 + 5 + 0.025) で即応答
            let offset = FocusRoom.clockOffset(pingSentAt: pingSentAt, pongReceivedAt: pongReceivedAt, hostReplyTime: hostReplyTime)
            // ホストが startAt = 200 を announce（ホスト epoch）→ ゲスト側計算
            let localStart = FocusRoom.localStartTime(hostStartAt: 200.0, offset: offset)
            // 真の同期時刻: ゲスト epoch では 195.0（ホスト 200 に対応）
            let trueSync = 200.0 - 5.0
            let error = abs(localStart - trueSync)
            assert(error < 1.0, "sync error should be < 1 sec, got \(error)")
        }

        // Test 7: RoomMessage の JSON ラウンドトリップ（hello は isHost フラグ廃止済み）
        do {
            let testRoomID = UUID()
            let msgs: [RoomMessage] = [
                .hello(participantID: "abc"),
                .faceDown(participantID: "def", isFaceDown: true),
                .clockPing(pingSentAt: 123.456),
                .clockPong(pingSentAt: 123.456, hostReplyTime: 789.012),
                .start(hostStartAt: 200.0, roomID: testRoomID),
                .end,
                .leave(participantID: "ghi"),
            ]
            let enc = JSONEncoder(); let dec = JSONDecoder()
            for m in msgs {
                let data = try! enc.encode(m)
                let back = try! dec.decode(RoomMessage.self, from: data)
                // Equatable が無いので switch でパターンマッチして比較
                switch (m, back) {
                case (.hello(let a), .hello(let b)): assert(a == b)
                case (.faceDown(let a, let b), .faceDown(let c, let d)): assert(a == c && b == d)
                case (.clockPing(let a), .clockPing(let b)): assert(a == b)
                case (.clockPong(let a, let b), .clockPong(let c, let d)): assert(a == c && b == d)
                case (.start(let a, let ar), .start(let b, let br)): assert(a == b && ar == br)
                case (.end, .end): break
                case (.leave(let a), .leave(let b)): assert(a == b)
                default: assert(false, "roundtrip mismatch")
                }
            }
        }

        // Test 8（統合テスト）: FocusRoom.shouldAddParticipant — PeerRoomSession.handle(.hello) の
        // 重複メッセージ処理そのものが使う判定。同じ id の hello が2回来ても2件目は弾かれる。
        do {
            var existing: [Participant] = [Participant(id: "a", isFaceDown: false, isHost: true)]
            assert(FocusRoom.shouldAddParticipant(existing: existing, id: "b"), "new id -> should add")
            assert(!FocusRoom.shouldAddParticipant(existing: existing, id: "a"), "duplicate hello -> reject")
            // 実際に1回だけ追加されるシミュレーション
            if FocusRoom.shouldAddParticipant(existing: existing, id: "b") {
                existing.append(Participant(id: "b", isFaceDown: false, isHost: false))
            }
            if FocusRoom.shouldAddParticipant(existing: existing, id: "b") {
                existing.append(Participant(id: "b", isFaceDown: false, isHost: false))
            }
            assert(existing.filter { $0.id == "b" }.count == 1, "duplicate hello must not double-insert")
        }

        // Test 9（統合テスト）: FocusRoom.tryTransitionToEnded — PeerRoomSession.markEnded()/end() の
        // 再入ガードそのもの。onEnded に相当するコールバックが2回目は呼ばれないことを検証。
        do {
            var state: RoomState = .running
            var onEndedCallCount = 0
            func markEnded() {
                guard FocusRoom.tryTransitionToEnded(&state) else { return }
                onEndedCallCount += 1
            }
            markEnded()
            markEnded()  // 2回目発火（例: .end の重複受信 or 呼び忘れ経路からの再呼び出し）
            assert(state == .ended, "state should be .ended")
            assert(onEndedCallCount == 1, "onEnded must fire exactly once, got \(onEndedCallCount)")
        }

        // Test 10（統合テスト）: FocusRoom.markFinishedOnce — FocusRoomView.finishAndSave が使う
        // ガードそのもの。onEnded が2回発火しても FocusSession の保存(相当処理)は1回だけ実行される。
        do {
            var hasFinished = false
            var saveCount = 0
            func finishAndSave() {
                guard FocusRoom.markFinishedOnce(&hasFinished) else { return }
                saveCount += 1  // FocusSession.record 相当（実際の保存は SwiftData 依存のため selfcheck 対象外）
            }
            finishAndSave()  // 1回目: onStartScheduled の Timer 満了
            finishAndSave()  // 2回目: onEnded からもほぼ同時に発火（1Hz self-report と .end broadcast の競合）
            assert(saveCount == 1, "FocusSession must be saved exactly once, got \(saveCount)")
        }

        // Test 11（統合テスト）: FocusRoom.isRateLimited — PeerRoomSession.handle の .hello/.leave
        // 受信レート制限そのもの。5秒窓で3回まで許容、4回目は拒否。窓を過ぎれば再度許容される。
        do {
            var timestamps: [TimeInterval] = []
            assert(!FocusRoom.isRateLimited(&timestamps, now: 0.0, limit: 3, window: 5), "1st within window -> allowed")
            assert(!FocusRoom.isRateLimited(&timestamps, now: 0.5, limit: 3, window: 5), "2nd within window -> allowed")
            assert(!FocusRoom.isRateLimited(&timestamps, now: 1.0, limit: 3, window: 5), "3rd within window -> allowed")
            assert(FocusRoom.isRateLimited(&timestamps, now: 1.2, limit: 3, window: 5), "4th within window -> rejected")
            // 5秒経過後は古いタイムスタンプが剪定されて再度許容される
            assert(!FocusRoom.isRateLimited(&timestamps, now: 10.0, limit: 3, window: 5), "after window elapses -> allowed again")
        }

        print("P14 self-check: ALL PASS")
    }
}
