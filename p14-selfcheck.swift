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

        // Test 7: RoomMessage の JSON ラウンドトリップ
        do {
            let testRoomID = UUID()
            let msgs: [RoomMessage] = [
                .hello(participantID: "abc", isHost: true),
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
                case (.hello(let a, let b), .hello(let c, let d)): assert(a == c && b == d)
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

        print("P14 self-check: ALL PASS")
    }
}
