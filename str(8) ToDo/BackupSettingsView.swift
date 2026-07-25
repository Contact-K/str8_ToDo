import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @AppStorage(AppSettingsKey.lastBackupExportDate) var lastBackupExportDate = 0.0

    // バックアップ関連の状態管理
    @State private var exportDocument: Str8BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showExportPassphrasePrompt = false
    @State private var showImportPassphrasePrompt = false
    @State private var passphraseInput = ""
    @State private var passphraseConfirm = ""
    @State private var pendingImportData: Data?
    @State private var pendingPayload: BackupService.BackupPayload?
    @State private var showRestoreConfirmation = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        VStack(spacing: 0) {
            S8TopBar("バックアップ", sub: "backup · .str8") { EmptyView() }
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - バックアップセクション（Handoff 07b: str8 計器スタンプカード）
                    S8SectionLabel(text: "バックアップ（.str8）")
                    VStack(alignment: .leading, spacing: 10) {
                        // 計器スタンプ: 「STR8 · AES-GCM · V3 · LOCAL ONLY」— 色はアクセント追従
                        HStack(spacing: 8) {
                            Circle().fill(c.accent).frame(width: 5, height: 5)
                            Text("STR8 · AES-GCM · ")
                                .font(S8Font.mono(9.5)).tracking(1.4)
                                .foregroundColor(c.fg3)
                                + Text("V3")
                                .font(S8Font.mono(9.5, .bold)).tracking(1.4)
                                .foregroundColor(c.fg2)
                                + Text(" · LOCAL ONLY")
                                .font(S8Font.mono(9.5)).tracking(1.4)
                                .foregroundColor(c.fg3)
                        }
                        // 最終エクスポート日時
                        HStack(spacing: 4) {
                            Text("最終エクスポート").font(S8Font.jp(12)).foregroundColor(c.fg2)
                            if lastBackupExportDate > 0 {
                                Text(Date(timeIntervalSinceReferenceDate: lastBackupExportDate),
                                     format: .dateTime.month().day().hour().minute())
                                    .font(S8Font.mono(12, .bold))
                                    .foregroundColor(c.fg1)
                            } else {
                                Text("未実施").font(S8Font.mono(12)).foregroundColor(c.fg3)
                            }
                        }
                        // エクスポート / インポート
                        HStack(spacing: 10) {
                            Button(action: {
                                passphraseInput = ""
                                passphraseConfirm = ""
                                showExportPassphrasePrompt = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("エクスポート")
                                }
                                .font(S8Font.jp(13.5, .medium))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button(action: { showImporter = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc")
                                    Text("インポート")
                                }
                                .font(S8Font.jp(13.5, .medium))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("月1回、古くなると控えめにリマインドします。")
                            .font(S8Font.jp(10.5)).foregroundColor(c.fg3)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 15)

                    // 30日超過時の警告
                    if shouldShowBackupWarning() {
                        Label("最後のバックアップから30日以上経っています", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear.frame(height: 32)
                }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .str8,
            defaultFilename: exportDefaultFileName()
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.str8],
            onCompletion: handleImportSelection
        )
        .alert("エクスポート用のパスフレーズ", isPresented: $showExportPassphrasePrompt) {
            SecureField("パスフレーズ", text: $passphraseInput)
            SecureField("パスフレーズ（確認）", text: $passphraseConfirm)
            Button("キャンセル", role: .cancel) {
                clearPassphrases()
            }
            Button("エクスポート") {
                if passphraseInput.isEmpty {
                    errorMessage = "パスフレーズを入力してください"
                    showErrorAlert = true
                } else if passphraseInput != passphraseConfirm {
                    errorMessage = "パスフレーズが一致しません"
                    showErrorAlert = true
                } else {
                    performExport(passphrase: passphraseInput)
                }
                clearPassphrases()
            }
        } message: {
            Text("バックアップを保護するため、パスフレーズを2回入力してください。このパスフレーズは復元に必須です。忘れるとバックアップを開けません。")
        }
        .alert("復元用のパスフレーズ", isPresented: $showImportPassphrasePrompt) {
            SecureField("パスフレーズ", text: $passphraseInput)
            Button("キャンセル", role: .cancel) {
                pendingImportData = nil
                clearPassphrases()
            }
            Button("次へ") {
                decryptPendingImport(passphrase: passphraseInput)
                clearPassphrases()
            }
        } message: {
            Text("バックアップを復元するため、パスフレーズを入力してください")
        }
        .alert("復元の確認", isPresented: $showRestoreConfirmation) {
            Button("キャンセル", role: .cancel) {
                pendingImportData = nil
                pendingPayload = nil
            }
            Button("消去して復元", role: .destructive) {
                performRestore()
            }
        } message: {
            Text("このバックアップの作成日時: \(pendingPayload.map { formattedDateTime($0.exportedAt) } ?? "不明")\n現在のデータを全て消去して復元します。取り消せません。")
        }
        .alert("エラー", isPresented: $showErrorAlert) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラーが発生しました")
        }
    }

    // MARK: - バックアップヘルパー関数

    private func performExport(passphrase: String) {
        do {
            let data = try BackupService.export(context: modelContext, passphrase: passphrase)
            exportDocument = Str8BackupDocument(data: data)
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            // 実際に保存できた時だけ「最終エクスポート」を更新（保存ダイアログのキャンセルは対象外）
            lastBackupExportDate = Date().timeIntervalSinceReferenceDate
        case .failure(let error):
            errorMessage = "エクスポートに失敗しました: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// ファイル選択直後にセキュリティスコープ内で読み込んでおく（スコープ解放後に URL を読まない）。
    private func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "ファイルにアクセスできませんでした"
                showErrorAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // OOM防止: 読み込み前にサイズを確認（50MB上限）
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard fileSize <= 50 * 1024 * 1024 else {
                errorMessage = "バックアップファイルが大きすぎます"
                showErrorAlert = true
                return
            }

            do {
                pendingImportData = try Data(contentsOf: url)
                passphraseInput = ""
                showImportPassphrasePrompt = true
            } catch {
                errorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
                showErrorAlert = true
            }
        case .failure(let error):
            errorMessage = "ファイル選択に失敗しました: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// 復号+検証のみ行い、成功したら作成日時つきの復元確認へ進む。
    private func decryptPendingImport(passphrase: String) {
        guard let data = pendingImportData else { return }
        do {
            pendingPayload = try BackupService.readPayload(data: data, passphrase: passphrase)
            showRestoreConfirmation = true
        } catch {
            // ponytail: 誤パスフレーズは破棄してやり直し（再入力リトライはフロー多段化するため見送り）
            pendingImportData = nil
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func performRestore() {
        guard let payload = pendingPayload else { return }
        pendingPayload = nil
        pendingImportData = nil

        do {
            try BackupService.restore(payload: payload, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func clearPassphrases() {
        passphraseInput = ""
        passphraseConfirm = ""
    }

    private func shouldShowBackupWarning() -> Bool {
        guard lastBackupExportDate > 0 else { return true }
        let lastBackupDate = Date(timeIntervalSinceReferenceDate: lastBackupExportDate)
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .now
        return lastBackupDate < thirtyDaysAgo
    }

    private func exportDefaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "str8-backup-\(formatter.string(from: Date())).str8"
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - FileDocument for Backup Export

struct Str8BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.str8] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - UTType Extension

extension UTType {
    static let str8 = UTType(exportedAs: "str8.todo.str8backup", conformingTo: .data)
}

#Preview {
    NavigationStack {
        BackupSettingsView()
    }
    .modelContainer(PreviewData.container)
}
