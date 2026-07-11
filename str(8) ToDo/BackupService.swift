//
//  BackupService.swift
//  str8ToDo
//
//  暗号化バックアップの export/restore。
//  @Model は直接 Codable にできないため、DTO 層を介して JSON 変換する。
//

import Foundation
import SwiftData
import CryptoKit
import CommonCrypto

enum BackupService {
    static let formatVersion: Int = 1

    // MARK: - DTO 構造体（JSON 変換用）

    struct TaskDTO: Codable {
        var id: UUID
        var title: String
        var categoryID: UUID?
        var startDate: Date?
        var duration: TimeInterval
        var isAllDay: Bool
        var placeID: UUID?
        var phase: String  // SortPhase.rawValue
        var status: String  // TaskStatus.rawValue
        var completedAt: Date?
        var approvedAt: Date?
        var unlockDate: Date?
        var approverID: String?
        var rrule: String?
        var eventKitID: String?
        var isFromEventKit: Bool
        var createdAt: Date
        var notes: String
        var isImportant: Bool
        var colorHex: String?
        var notificationOffsets: [Int]
        var timeZoneIdentifier: String?
        var amount: Decimal?
        var paymentMethod: String?
        var actualDuration: TimeInterval?
        var isTimePinned: Bool
        var sortIndex: Int
        var lastSortedDay: Date?
        var snoozeUntil: Date?
        var subjectID: UUID?
    }

    struct CategoryDTO: Codable {
        var id: UUID
        var name: String
        var colorHex: String
        var symbolName: String
    }

    struct SubjectDTO: Codable {
        var id: UUID
        var name: String
        var colorHex: String
        var dailyGoalMinutes: Int
        var weeklyGoalMinutes: Int
        var pomodoroMinutes: Int
    }

    struct PlaceTagDTO: Codable {
        var id: UUID
        var name: String
        var latitude: Double?
        var longitude: Double?
    }

    struct DayStatDTO: Codable {
        var day: Date
        var completedCount: Int
        var focusSeconds: Int
    }

    struct BandDTO: Codable {
        var id: UUID
        var name: String
        var startMinutes: Int
        var endMinutes: Int
        var templateID: UUID?
    }

    struct BandTemplateDTO: Codable {
        var id: UUID
        var name: String
    }

    struct BandAssignmentDTO: Codable {
        var id: UUID
        var weekday: Int?
        var date: Date?
        var templateID: UUID?
    }

    struct FocusSessionDTO: Codable {
        var id: UUID
        var start: Date
        var end: Date
        var taskID: UUID?
        var subjectID: UUID?
        var roomID: UUID? = nil
        var participantCount: Int? = nil
    }

    struct WeekReviewDTO: Codable {
        var id: UUID
        var weekStart: Date
        var closedAt: Date
        var focusTotalSec: TimeInterval
        var moneyTotal: Decimal
        var doneCount: Int
    }

    /// 後方互換の規約：
    /// - 後続のモデル/フィールドは必ず Optional（または default 付き init(from:)）で加算すること。
    ///   非 Optional で足すと旧バージョンの .str8 が keyNotFound → corruptData になり読めなくなる。
    /// - 既存フィールドの削除・リネームは formatVersion を上げて移行処理を書くこと。
    /// - 未知キーは JSONDecoder が無視するため、加算だけなら旧アプリでも読める。
    struct BackupPayload: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var tasks: [TaskDTO]
        var categories: [CategoryDTO]
        var places: [PlaceTagDTO]
        var dayStats: [DayStatDTO]
        var bandTemplates: [BandTemplateDTO]
        var bands: [BandDTO]
        var bandAssignments: [BandAssignmentDTO]
        var focusSessions: [FocusSessionDTO]
        /// P10 加算。規約どおり optional：旧 .str8（subjects キー無し）でも keyNotFound にならず nil で読める。
        var subjects: [SubjectDTO]?
        /// P13 加算。規約どおり optional：旧 .str8（weekReviews キー無し）でも keyNotFound にならず nil で読める。
        var weekReviews: [WeekReviewDTO]?
    }

    // MARK: - エラー型

    enum BackupError: LocalizedError {
        case wrongPassphrase
        case corruptData
        case unsupportedVersion(Int)
        case emptyPassphrase
        case keyDerivationFailed

        var errorDescription: String? {
            switch self {
            case .wrongPassphrase:
                return "パスフレーズが違うか、ファイルが破損しています"
            case .corruptData:
                return "バックアップファイルが破損しています"
            case .unsupportedVersion(let version):
                return "サポートされていないバージョン \(version) です。アプリを更新してください"
            case .emptyPassphrase:
                return "パスフレーズを入力してください"
            case .keyDerivationFailed:
                return "暗号鍵の生成に失敗しました"
            }
        }
    }

    // MARK: - 鍵導出（PBKDF2）

    /// CommonCrypto の PBKDF2 で鍵を導出。CryptoKit に PBKDF2 がないため必須。
    /// 空パスフレーズは呼び出し側（encrypt/decryptPayload）で guard 済み。
    static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(passphrase.utf8)
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: 32)  // 32 bytes = 256 bits
        let status = passwordBytes.withUnsafeBufferPointer { pw in
            derived.withUnsafeMutableBufferPointer { out in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    UnsafeRawPointer(pw.baseAddress!).assumingMemoryBound(to: Int8.self),
                    passwordBytes.count,
                    saltBytes,
                    saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    210_000,  // iterations
                    out.baseAddress,
                    32
                )
            }
        }
        guard status == kCCSuccess else {
            throw BackupError.keyDerivationFailed
        }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: - 暗号化・復号化ヘルパー（internal でテストから呼べる）

    /// ペイロード JSON を暗号化。戻り値は salt + AES.GCM.SealedBox.combined。
    static func encryptPayload(_ payload: BackupPayload, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }

        // JSON エンコード
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)

        // salt 生成（16 bytes）
        var saltBytes = [UInt8](repeating: 0, count: 16)
        let statusCode = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard statusCode == errSecSuccess else {
            throw BackupError.corruptData
        }
        let salt = Data(saltBytes)

        // 鍵導出
        let key = try deriveKey(passphrase: passphrase, salt: salt)

        // AES-GCM 暗号化
        let sealedBox = try AES.GCM.seal(jsonData, using: key)

        // salt + SealedBox.combined を返す
        var result = salt
        if let combined = sealedBox.combined {
            result.append(combined)
        }
        return result
    }

    /// salt + AES.GCM.SealedBox.combined を復号。
    static func decryptPayload(_ data: Data, passphrase: String) throws -> BackupPayload {
        guard !passphrase.isEmpty else { throw BackupError.emptyPassphrase }

        // salt 抽出（先頭 16 bytes）
        guard data.count >= 16 else {
            throw BackupError.corruptData
        }
        let salt = data.subdata(in: 0..<16)
        let sealedData = data.subdata(in: 16..<data.count)

        // 鍵導出
        let key = try deriveKey(passphrase: passphrase, salt: salt)

        // AES-GCM 復号
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        } catch {
            throw BackupError.wrongPassphrase
        }

        let jsonData: Data
        do {
            jsonData = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupError.wrongPassphrase
        }

        // JSON デコード
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: jsonData)
        } catch {
            throw BackupError.corruptData
        }

        return payload
    }

    // MARK: - 全消去

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }

    /// 全10モデルを参照する側から順に個別 delete（internal: selfcheck からも使う）。
    @MainActor
    static func deleteAllModels(context: ModelContext) throws {
        try deleteAll(TaskItem.self, context: context)
        try deleteAll(FocusSession.self, context: context)
        try deleteAll(DayStat.self, context: context)
        // MonthMoneyStat は再計算可能キャッシュ: 復元時は削除のみ（月ビュー表示時に recompute）
        try deleteAll(MonthMoneyStat.self, context: context)
        try deleteAll(BandAssignment.self, context: context)
        try deleteAll(Band.self, context: context)
        try deleteAll(BandTemplate.self, context: context)
        try deleteAll(Category.self, context: context)
        try deleteAll(PlaceTag.self, context: context)
        // Subject は一次データ（科目名/色/目標/ポモ）。subjectID のダングリング防止に必ず含める。
        try deleteAll(Subject.self, context: context)
        try deleteAll(WeekReview.self, context: context)
    }

    // MARK: - export / restore

    /// 全エンティティを暗号化ファイルに出力。ファイル形式: magic + version + 暗号化ペイロード。
    @MainActor
    static func export(context: ModelContext, passphrase: String) throws -> Data {
        // 全モデルを fetch
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let places = try context.fetch(FetchDescriptor<PlaceTag>())
        let dayStats = try context.fetch(FetchDescriptor<DayStat>())
        let bandTemplates = try context.fetch(FetchDescriptor<BandTemplate>())
        let bands = try context.fetch(FetchDescriptor<Band>())
        let bandAssignments = try context.fetch(FetchDescriptor<BandAssignment>())
        let focusSessions = try context.fetch(FetchDescriptor<FocusSession>())
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let weekReviews = try context.fetch(FetchDescriptor<WeekReview>())

        // DTO に変換
        let taskDTOs = tasks.map { task in
            TaskDTO(
                id: task.id,
                title: task.title,
                categoryID: task.category?.id,
                startDate: task.startDate,
                duration: task.duration,
                isAllDay: task.isAllDay,
                placeID: task.place?.id,
                phase: task.phase.rawValue,
                status: task.status.rawValue,
                completedAt: task.completedAt,
                approvedAt: task.approvedAt,
                unlockDate: task.unlockDate,
                approverID: task.approverID,
                rrule: task.rrule,
                eventKitID: task.eventKitID,
                isFromEventKit: task.isFromEventKit,
                createdAt: task.createdAt,
                notes: task.notes,
                isImportant: task.isImportant,
                colorHex: task.colorHex,
                notificationOffsets: task.notificationOffsets,
                timeZoneIdentifier: task.timeZoneIdentifier,
                amount: task.amount,
                paymentMethod: task.paymentMethod,
                actualDuration: task.actualDuration,
                isTimePinned: task.isTimePinned,
                sortIndex: task.sortIndex,
                lastSortedDay: task.lastSortedDay,
                snoozeUntil: task.snoozeUntil,
                subjectID: task.subjectID
            )
        }

        let categoryDTOs = categories.map { cat in
            CategoryDTO(id: cat.id, name: cat.name, colorHex: cat.colorHex, symbolName: cat.symbolName)
        }

        let placeDTOs = places.map { place in
            PlaceTagDTO(id: place.id, name: place.name, latitude: place.latitude, longitude: place.longitude)
        }

        let dayStatDTOs = dayStats.map { stat in
            DayStatDTO(day: stat.day, completedCount: stat.completedCount, focusSeconds: stat.focusSeconds)
        }

        let bandTemplateDTOs = bandTemplates.map { template in
            BandTemplateDTO(id: template.id, name: template.name)
        }

        let bandDTOs = bands.map { band in
            BandDTO(id: band.id, name: band.name, startMinutes: band.startMinutes, endMinutes: band.endMinutes, templateID: band.template?.id)
        }

        let bandAssignmentDTOs = bandAssignments.map { assignment in
            BandAssignmentDTO(id: assignment.id, weekday: assignment.weekday, date: assignment.date, templateID: assignment.template?.id)
        }

        let focusSessionDTOs = focusSessions.map { session in
            FocusSessionDTO(id: session.id, start: session.start, end: session.end, taskID: session.taskID, subjectID: session.subjectID, roomID: session.roomID, participantCount: session.participantCount)
        }

        let subjectDTOs = subjects.map { subject in
            SubjectDTO(id: subject.id, name: subject.name, colorHex: subject.colorHex,
                       dailyGoalMinutes: subject.dailyGoalMinutes,
                       weeklyGoalMinutes: subject.weeklyGoalMinutes,
                       pomodoroMinutes: subject.pomodoroMinutes)
        }

        let weekReviewDTOs = weekReviews.map { wr in
            WeekReviewDTO(id: wr.id, weekStart: wr.weekStart, closedAt: wr.closedAt,
                         focusTotalSec: wr.focusTotalSec, moneyTotal: wr.moneyTotal, doneCount: wr.doneCount)
        }

        let payload = BackupPayload(
            formatVersion: formatVersion,
            exportedAt: .now,
            tasks: taskDTOs,
            categories: categoryDTOs,
            places: placeDTOs,
            dayStats: dayStatDTOs,
            bandTemplates: bandTemplateDTOs,
            bands: bandDTOs,
            bandAssignments: bandAssignmentDTOs,
            focusSessions: focusSessionDTOs,
            subjects: subjectDTOs,
            weekReviews: weekReviewDTOs
        )

        // ペイロード暗号化
        let encryptedPayload = try encryptPayload(payload, passphrase: passphrase)

        // ファイルフォーマット: magic + version + 暗号化ペイロード
        var result = Data("STR8".utf8)
        result.append(UInt8(formatVersion))
        result.append(encryptedPayload)

        return result
    }

    /// 復号+デコード+バージョン検証のみ。ストアには書き込まない。
    /// UI が復元確認前に exportedAt 等を表示するために使う。
    static func readPayload(data: Data, passphrase: String) throws -> BackupPayload {
        // ファイルフォーマット検証
        guard data.count >= 5 else {
            throw BackupError.corruptData
        }

        let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        guard magic == "STR8" else {
            throw BackupError.corruptData
        }

        // ファイルレイヤーのバージョン検証（不明値は破損扱い）
        let fileVersion = Int(data[4])
        guard fileVersion == 1 else {
            throw BackupError.corruptData
        }
        let encryptedPayload = data.subdata(in: 5..<data.count)

        // ペイロード復号
        let payload = try decryptPayload(encryptedPayload, passphrase: passphrase)

        // バージョン検証（未来バージョンは unsupportedVersion）
        if payload.formatVersion > formatVersion {
            throw BackupError.unsupportedVersion(payload.formatVersion)
        }

        return payload
    }

    /// 暗号化ファイルを復号し、全モデルを挿入。既存データは全削除。
    @MainActor
    static func restore(data: Data, passphrase: String, context: ModelContext) throws {
        let payload = try readPayload(data: data, passphrase: passphrase)
        try restore(payload: payload, context: context)
    }

    /// 全消去+挿入+save（save 失敗時は rollback して rethrow）。
    @MainActor
    static func restore(payload: BackupPayload, context: ModelContext) throws {
        // 全既存データ削除（参照する側から個別 delete。
        // バッチ削除 delete(model:) は inverse リレーション制約で失敗するため使わない）
        // save は挿入完了後に1回だけ：途中クラッシュでも旧データが残る（データ消失窓を作らない）。
        try deleteAllModels(context: context)

        // ID 辞書を事前構築（リレーション復元用）
        var categoryMap: [UUID: Category] = [:]
        var placeMap: [UUID: PlaceTag] = [:]
        var templateMap: [UUID: BandTemplate] = [:]
        var bandMap: [UUID: Band] = [:]

        // Category 挿入
        for catDTO in payload.categories {
            let cat = Category(id: catDTO.id, name: catDTO.name, colorHex: catDTO.colorHex, symbolName: catDTO.symbolName)
            context.insert(cat)
            categoryMap[cat.id] = cat
        }

        // Subject 挿入（subjectID は UUID 値参照なので順序依存なし。旧 .str8 は nil → 空配列）
        for subjectDTO in payload.subjects ?? [] {
            context.insert(Subject(id: subjectDTO.id, name: subjectDTO.name, colorHex: subjectDTO.colorHex,
                                   dailyGoalMinutes: subjectDTO.dailyGoalMinutes,
                                   weeklyGoalMinutes: subjectDTO.weeklyGoalMinutes,
                                   pomodoroMinutes: subjectDTO.pomodoroMinutes))
        }

        // PlaceTag 挿入
        for placeDTO in payload.places {
            let place = PlaceTag(id: placeDTO.id, name: placeDTO.name, latitude: placeDTO.latitude, longitude: placeDTO.longitude)
            context.insert(place)
            placeMap[place.id] = place
        }

        // BandTemplate 挿入
        for templateDTO in payload.bandTemplates {
            let template = BandTemplate(id: templateDTO.id, name: templateDTO.name)
            context.insert(template)
            templateMap[template.id] = template
        }

        // Band 挿入（templateID でリンク）
        for bandDTO in payload.bands {
            let band = Band(id: bandDTO.id, name: bandDTO.name, startMinutes: bandDTO.startMinutes, endMinutes: bandDTO.endMinutes)
            if let templateID = bandDTO.templateID {
                band.template = templateMap[templateID]
            }
            context.insert(band)
            bandMap[band.id] = band
        }

        // BandAssignment 挿入（templateID でリンク）
        for assignmentDTO in payload.bandAssignments {
            let assignment: BandAssignment
            if let weekday = assignmentDTO.weekday {
                assignment = BandAssignment(id: assignmentDTO.id, weekday: weekday)
            } else if let date = assignmentDTO.date {
                assignment = BandAssignment(id: assignmentDTO.id, date: date)
            } else {
                // weekday も date も nil は不正（但し復元時は無視して続行）
                continue
            }
            if let templateID = assignmentDTO.templateID {
                assignment.template = templateMap[templateID]
            }
            context.insert(assignment)
        }

        // TaskItem 挿入（categoryID/placeID/subjectID でリンク）
        for taskDTO in payload.tasks {
            let task = TaskItem(
                id: taskDTO.id,
                title: taskDTO.title,
                category: taskDTO.categoryID.flatMap { categoryMap[$0] },
                startDate: taskDTO.startDate,
                duration: taskDTO.duration,
                isAllDay: taskDTO.isAllDay,
                place: taskDTO.placeID.flatMap { placeMap[$0] },
                phase: SortPhase(rawValue: taskDTO.phase) ?? .someday,
                status: TaskStatus(rawValue: taskDTO.status) ?? .active,
                completedAt: taskDTO.completedAt,
                approvedAt: taskDTO.approvedAt,
                unlockDate: taskDTO.unlockDate,
                approverID: taskDTO.approverID,
                rrule: taskDTO.rrule,
                eventKitID: taskDTO.eventKitID,
                isFromEventKit: taskDTO.isFromEventKit,
                createdAt: taskDTO.createdAt,
                notes: taskDTO.notes,
                isImportant: taskDTO.isImportant,
                colorHex: taskDTO.colorHex,
                notificationOffsets: taskDTO.notificationOffsets,
                timeZoneIdentifier: taskDTO.timeZoneIdentifier,
                amount: taskDTO.amount,
                paymentMethod: taskDTO.paymentMethod,
                actualDuration: taskDTO.actualDuration,
                isTimePinned: taskDTO.isTimePinned,
                sortIndex: taskDTO.sortIndex,
                lastSortedDay: taskDTO.lastSortedDay,
                snoozeUntil: taskDTO.snoozeUntil,
                subjectID: taskDTO.subjectID
            )
            context.insert(task)
        }

        // DayStat 挿入
        for statDTO in payload.dayStats {
            let stat = DayStat(day: statDTO.day, completedCount: statDTO.completedCount, focusSeconds: statDTO.focusSeconds)
            context.insert(stat)
        }

        // FocusSession 挿入
        for sessionDTO in payload.focusSessions {
            let session = FocusSession(id: sessionDTO.id, start: sessionDTO.start, end: sessionDTO.end, taskID: sessionDTO.taskID, subjectID: sessionDTO.subjectID, roomID: sessionDTO.roomID, participantCount: sessionDTO.participantCount)
            context.insert(session)
        }

        // WeekReview 挿入
        for wrDTO in payload.weekReviews ?? [] {
            let wr = WeekReview(id: wrDTO.id, weekStart: wrDTO.weekStart, closedAt: wrDTO.closedAt,
                               focusTotalSec: wrDTO.focusTotalSec, moneyTotal: wrDTO.moneyTotal, doneCount: wrDTO.doneCount)
            context.insert(wr)
        }

        do {
            try context.save()
        } catch {
            // 「全削除+再挿入」の dirty 状態を共有 mainContext に残さない
            // （残すと後続の無関係な save で破壊が確定する）。
            context.rollback()
            throw error
        }
    }
}
