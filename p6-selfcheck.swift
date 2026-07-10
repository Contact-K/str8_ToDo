//
//  p6-selfcheck.swift — Phase 6 の自己チェック（BackupService の export/restore）
//
//  実行方法（macOS、リポジトリルートで）:
//    cd "/Users/konnotakuto/Swift_PRJS/str(8)_ToDo/str(8) ToDo" && \
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/FocusSession.swift" "str(8) ToDo/BackupService.swift" \
//      "str(8) ToDo/Subject.swift" "str(8) ToDo/MoneyStats.swift" "str(8) ToDo/Formatting.swift" \
//      p6-selfcheck.swift -o /tmp/p6check && /tmp/p6check
//
//  アプリターゲットには含めない（pbxproj 未登録）。
//

import Foundation
import SwiftData

// MARK: - 共通ヘルパー

/// in-memory の ModelContext を作る。container を返り値に含めて生存させる。
@MainActor
func makeTestContext() -> (container: ModelContainer, ctx: ModelContext) {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                         Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self, Subject.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    return (container, container.mainContext)
}

// MARK: - Test 1: リレーション付きシードデータ → export → restore

@MainActor
func testRoundtrip() {
    // container を捨てると mainContext が無効化されて SwiftData 内部でクラッシュする。スコープ末尾まで保持。
    let (container, ctx) = makeTestContext()
    defer { withExtendedLifetime(container) {} }

    // Category を作成
    let category = Category(id: UUID(), name: "仕事", colorHex: "#FF0000", symbolName: "briefcase.fill")
    ctx.insert(category)

    // PlaceTag を作成
    let place = PlaceTag(id: UUID(), name: "オフィス", latitude: 35.6789, longitude: 139.7654)
    ctx.insert(place)

    // Subject を作成（P10: TaskItem.subjectID / FocusSession.subjectID の参照先）
    let subject = Subject(id: UUID(), name: "数学", colorHex: "#4F8DFD",
                          dailyGoalMinutes: 90, weeklyGoalMinutes: 420, pomodoroMinutes: 30)
    ctx.insert(subject)

    // BandTemplate と Band を作成
    let template = BandTemplate(id: UUID(), name: "平日")
    let band1 = Band(id: UUID(), name: "朝", startMinutes: 360, endMinutes: 540)
    band1.template = template
    template.bands = [band1]
    ctx.insert(template)
    ctx.insert(band1)

    // BandAssignment (weekday 版)
    let assignmentWeekday = BandAssignment(id: UUID(), weekday: 2)
    assignmentWeekday.template = template
    ctx.insert(assignmentWeekday)

    // BandAssignment (date 版)
    let assignmentDate = BandAssignment(id: UUID(), date: Date())
    assignmentDate.template = template
    ctx.insert(assignmentDate)

    // TaskItem (カテゴリ・場所・科目付き)
    let task1 = TaskItem(id: UUID(), title: "会議", category: category, place: place, phase: .today, status: .active, subjectID: subject.id)
    task1.createdAt = Date(timeIntervalSince1970: 1000000)
    ctx.insert(task1)

    // TaskItem (amount 付き、支出・サブスク用)
    let task2 = TaskItem(id: UUID(), title: "サブスク", phase: .week, amount: Decimal(string: "12.99"))
    task2.createdAt = Date(timeIntervalSince1970: 2000000)
    ctx.insert(task2)

    // DayStat
    let stat = DayStat(day: Date(), completedCount: 5, focusSeconds: 3600)
    ctx.insert(stat)

    // FocusSession (taskID・subjectID 付き)
    let session = FocusSession(id: UUID(), start: Date(), end: Date().addingTimeInterval(1800), taskID: task1.id, subjectID: subject.id)
    ctx.insert(session)

    try! ctx.save()

    // export
    let passphrase = "test-passphrase"
    let exportLowerBound = Date()
    let backupData = try! BackupService.export(context: ctx, passphrase: passphrase)
    assert(backupData.count > 0, "export: データが生成された")
    assert(backupData.prefix(4) == "STR8".data(using: .utf8), "export: magic check")

    // readPayload: 書き込みなしで exportedAt が読める（UI の復元確認用）
    // ISO8601 は秒未満を切り捨てるため ±1 秒の許容を入れる
    let peeked = try! BackupService.readPayload(data: backupData, passphrase: passphrase)
    assert(peeked.exportedAt >= exportLowerBound.addingTimeInterval(-1)
           && peeked.exportedAt <= Date().addingTimeInterval(1),
           "readPayload: exportedAt が export 時刻を返す")

    // 全消去（バッチ削除は inverse 制約で失敗するため個別 delete のヘルパーを使う）
    try! BackupService.deleteAllModels(context: ctx)
    try! ctx.save()

    // restore
    try! BackupService.restore(data: backupData, passphrase: passphrase, context: ctx)

    // 件数確認
    let taskCount = try! ctx.fetch(FetchDescriptor<TaskItem>()).count
    let categoryCount = try! ctx.fetch(FetchDescriptor<Category>()).count
    let placeCount = try! ctx.fetch(FetchDescriptor<PlaceTag>()).count
    let statCount = try! ctx.fetch(FetchDescriptor<DayStat>()).count
    let templateCount = try! ctx.fetch(FetchDescriptor<BandTemplate>()).count
    let bandCount = try! ctx.fetch(FetchDescriptor<Band>()).count
    let assignmentCount = try! ctx.fetch(FetchDescriptor<BandAssignment>()).count
    let sessionCount = try! ctx.fetch(FetchDescriptor<FocusSession>()).count
    let subjectCount = try! ctx.fetch(FetchDescriptor<Subject>()).count

    assert(taskCount == 2, "restore: TaskItem 件数 \(taskCount) == 2")
    assert(categoryCount == 1, "restore: Category 件数 \(categoryCount) == 1")
    assert(placeCount == 1, "restore: PlaceTag 件数 \(placeCount) == 1")
    assert(statCount == 1, "restore: DayStat 件数 \(statCount) == 1")
    assert(templateCount == 1, "restore: BandTemplate 件数 \(templateCount) == 1")
    assert(bandCount == 1, "restore: Band 件数 \(bandCount) == 1")
    assert(assignmentCount == 2, "restore: BandAssignment 件数 \(assignmentCount) == 2")
    assert(sessionCount == 1, "restore: FocusSession 件数 \(sessionCount) == 1")
    assert(subjectCount == 1, "restore: Subject 件数 \(subjectCount) == 1")

    // リレーション確認
    let restoredTask1 = try! ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == "会議" })).first
    assert(restoredTask1?.category?.name == "仕事", "restore: task.category?.name が復元された")
    assert(restoredTask1?.place?.name == "オフィス", "restore: task.place?.name が復元された")

    // amount 確認
    let restoredTask2 = try! ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == "サブスク" })).first
    assert(restoredTask2?.amount == Decimal(string: "12.99"), "restore: task.amount が復元された")

    // phase・status 確認
    assert(restoredTask1?.phase == .today, "restore: task.phase が復元された")
    assert(restoredTask1?.status == .active, "restore: task.status が復元された")

    // band.template 確認
    let restoredBand = try! ctx.fetch(FetchDescriptor<Band>()).first
    assert(restoredBand?.template?.name == "平日", "restore: band.template?.name が復元された")

    // BandAssignment.template 確認
    let restoredAssignments = try! ctx.fetch(FetchDescriptor<BandAssignment>())
    assert(restoredAssignments.allSatisfy { $0.template?.name == "平日" }, "restore: BandAssignment.template が復元された")

    // FocusSession.taskID 確認
    let restoredSession = try! ctx.fetch(FetchDescriptor<FocusSession>()).first
    assert(restoredSession?.taskID == task1.id, "restore: FocusSession.taskID が保持された")

    // Subject の値往復（名前/色/日週目標/ポモ）
    let restoredSubject = try! ctx.fetch(FetchDescriptor<Subject>()).first
    assert(restoredSubject?.id == subject.id, "restore: Subject.id が復元された")
    assert(restoredSubject?.name == "数学", "restore: Subject.name が復元された")
    assert(restoredSubject?.colorHex == "#4F8DFD", "restore: Subject.colorHex が復元された")
    assert(restoredSubject?.dailyGoalMinutes == 90, "restore: Subject.dailyGoalMinutes が復元された")
    assert(restoredSubject?.weeklyGoalMinutes == 420, "restore: Subject.weeklyGoalMinutes が復元された")
    assert(restoredSubject?.pomodoroMinutes == 30, "restore: Subject.pomodoroMinutes が復元された")

    // subjectID が有効な復元 Subject を指す（ダングリングでない）
    let restoredSubjectIDs = Set(try! ctx.fetch(FetchDescriptor<Subject>()).map { $0.id })
    assert(restoredTask1?.subjectID == subject.id, "restore: TaskItem.subjectID が保持された")
    assert(restoredTask1?.subjectID.map { restoredSubjectIDs.contains($0) } == true, "restore: TaskItem.subjectID が有効な Subject を指す")
    assert(restoredSession?.subjectID == subject.id, "restore: FocusSession.subjectID が保持された")
    assert(restoredSession?.subjectID.map { restoredSubjectIDs.contains($0) } == true, "restore: FocusSession.subjectID が有効な Subject を指す")
}

// MARK: - Test 2: 誤パスフレーズ → BackupError.wrongPassphrase

@MainActor
func testWrongPassphrase() {
    // container を捨てると mainContext が無効化されて SwiftData 内部でクラッシュする。スコープ末尾まで保持。
    let (container, ctx) = makeTestContext()
    defer { withExtendedLifetime(container) {} }

    let task = TaskItem(title: "テスト")
    ctx.insert(task)
    try! ctx.save()

    let backupData = try! BackupService.export(context: ctx, passphrase: "correct-pass")

    // 誤パスフレーズで復号
    var errorCaught = false
    var wrongPassphraseError = false
    do {
        try BackupService.restore(data: backupData, passphrase: "wrong-pass", context: ctx)
    } catch let error as BackupService.BackupError {
        errorCaught = true
        if case .wrongPassphrase = error {
            wrongPassphraseError = true
        }
    } catch {
        errorCaught = true
    }

    assert(errorCaught, "restore: エラーが throw された")
    assert(wrongPassphraseError, "restore: BackupError.wrongPassphrase が catch された")
}

// MARK: - Test 3: 壊れたデータ → BackupError.corruptData

@MainActor
func testCorruptData() {
    // container を捨てると mainContext が無効化されて SwiftData 内部でクラッシュする。スコープ末尾まで保持。
    let (container, ctx) = makeTestContext()
    defer { withExtendedLifetime(container) {} }

    let task = TaskItem(title: "テスト")
    ctx.insert(task)
    try! ctx.save()

    var backupData = try! BackupService.export(context: ctx, passphrase: "test-pass")

    // magic を壊す
    if backupData.count > 0 {
        backupData[0] = UInt8(ascii: "X")
    }

    var corruptDataError = false
    do {
        try BackupService.restore(data: backupData, passphrase: "test-pass", context: ctx)
    } catch let error as BackupService.BackupError {
        if case .corruptData = error {
            corruptDataError = true
        }
    } catch {
    }

    assert(corruptDataError, "restore: BackupError.corruptData が catch された（壊れた magic）")
}

// MARK: - Test 4: 未対応バージョン → BackupError.unsupportedVersion

@MainActor
func testUnsupportedVersion() {
    // container を捨てると mainContext が無効化されて SwiftData 内部でクラッシュする。スコープ末尾まで保持。
    let (container, ctx) = makeTestContext()
    defer { withExtendedLifetime(container) {} }

    let task = TaskItem(title: "テスト")
    ctx.insert(task)
    try! ctx.save()

    let passphrase = "test-pass"

    // export して、formatVersion を +1 に上げたペイロードを作る
    let originalBackupData = try! BackupService.export(context: ctx, passphrase: passphrase)

    // 暗号化された部分を解析
    let payload = try! BackupService.decryptPayload(
        originalBackupData.subdata(in: 5..<originalBackupData.count),
        passphrase: passphrase
    )

    // formatVersion を +1 に上げたペイロード
    var newPayload = payload
    newPayload.formatVersion = BackupService.formatVersion + 1

    // 新しいペイロードを暗号化
    let newEncryptedPayload = try! BackupService.encryptPayload(newPayload, passphrase: passphrase)

    // magic + version + 新しい暗号化ペイロード
    var newBackupData = Data("STR8".utf8)
    newBackupData.append(UInt8(BackupService.formatVersion))
    newBackupData.append(newEncryptedPayload)

    // 復号を試みる
    var unsupportedVersionError = false
    do {
        try BackupService.restore(data: newBackupData, passphrase: passphrase, context: ctx)
    } catch let error as BackupService.BackupError {
        if case .unsupportedVersion = error {
            unsupportedVersionError = true
        }
    } catch {
    }

    assert(unsupportedVersionError, "restore: BackupError.unsupportedVersion が catch された")
}

@main
@MainActor
struct P6SelfCheck {
    static func main() throws {
        testRoundtrip()
        testWrongPassphrase()
        testCorruptData()
        testUnsupportedVersion()

        print("p6-selfcheck: all passed")
    }
}
