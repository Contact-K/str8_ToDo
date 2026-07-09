import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CalendarSettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Category.name) var categories: [Category]
    @Query(sort: \BandTemplate.name) private var templates: [BandTemplate]
    @Query private var assignments: [BandAssignment]

    @AppStorage(AppSettingsKey.syncSystemCalendar) var syncSystemCalendar = AppSettingsKey.syncSystemCalendarDefault
    @AppStorage(AppSettingsKey.syncWeather) var syncWeather = AppSettingsKey.syncWeatherDefault
    @AppStorage(AppSettingsKey.enableNotifications) var enableNotifications = AppSettingsKey.enableNotificationsDefault
    @AppStorage(AppSettingsKey.lastBackupExportDate) var lastBackupExportDate = 0.0

    @State private var eventKit = EventKitService()
    @State private var weather = WeatherProvider()

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
        Form {
            // MARK: - 同期セクション
            Section(header: Text("同期")) {
                // システムカレンダー同期
                HStack {
                    Toggle("システムカレンダー同期", isOn: $syncSystemCalendar)
                        .onChange(of: syncSystemCalendar) { oldValue, newValue in
                            if newValue {
                                syncCalendarNow()
                            }
                        }
                }

                // システムカレンダー同期状態
                HStack {
                    Text("状態")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(authStateColor())
                            .frame(width: 8, height: 8)
                        Text(authStateLabel())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 今すぐ同期ボタン
                Button(action: {
                    syncCalendarNow()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("今すぐ同期")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                // 天気同期
                HStack {
                    Toggle("天気を同期", isOn: $syncWeather)
                        .onChange(of: syncWeather) { oldValue, newValue in
                            if newValue {
                                refreshWeatherNow()
                            }
                        }
                }

                // 天気同期状態
                HStack {
                    Text("状態")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(weather.status.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let statusDetail = weather.statusDetail {
                                Text(statusDetail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let temp = weather.temperatureText {
                                Text(temp)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let lastUpdated = weather.lastUpdated {
                            Text("更新: \(formattedTime(lastUpdated))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 天気を取得ボタン
                Button(action: {
                    refreshWeatherNow()
                }) {
                    HStack {
                        Image(systemName: "cloud.fill")
                        Text("天気を取得")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                // WeatherKit注記
                Text("※WeatherKitのCapability追加が必要")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // 通知
                Toggle("通知", isOn: $enableNotifications)
                    .onChange(of: enableNotifications) { oldValue, newValue in
                        if newValue {
                            Task {
                                await NotificationService.requestAuthorization()
                            }
                        }
                    }
            }

            // MARK: - マイ時間割セクション
            Section(header: Text("マイ時間割")) {
                ForEach(templates) { template in
                    NavigationLink(destination: BandTemplateEditorView(template: template)) {
                        HStack {
                            Text(template.name)
                            Spacer()
                            Text("\(template.bands.count)枠")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { templates[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }

                Button("テンプレートを追加") {
                    modelContext.insert(BandTemplate(name: "新しいテンプレート"))
                    try? modelContext.save()
                }
            }

            // MARK: - 曜日割当セクション
            Section(header: Text("曜日割当")) {
                ForEach(1...7, id: \.self) { weekday in
                    Picker(weekdayLabel(weekday), selection: weekdayTemplateBinding(weekday)) {
                        Text("なし").tag(nil as UUID?)
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id as UUID?)
                        }
                    }
                }
            }

            // MARK: - カテゴリ色セクション
            Section(header: Text("カテゴリ色")) {
                ForEach(categories) { category in
                    HStack(spacing: 12) {
                        Text(category.name)
                            .lineLimit(1)

                        Spacer()

                        // 現在色スウォッチ
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 24, height: 24)

                        // プリセットhexスウォッチ群
                        HStack(spacing: 8) {
                            ForEach(["#4F8DFD", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#8E8E93"], id: \.self) { hex in
                                Button(action: {
                                    category.colorHex = hex
                                    try? modelContext.save()
                                }) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(hex: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            category.colorHex == hex
                                                ? RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.primary, lineWidth: 2)
                                                : nil
                                        )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            // MARK: - バックアップセクション
            Section(header: Text("バックアップ")) {
                // エクスポートボタン
                Button(action: {
                    passphraseInput = ""
                    passphraseConfirm = ""
                    showExportPassphrasePrompt = true
                }) {
                    HStack {
                        Image(systemName: "arrow.up.doc")
                        Text("エクスポート (.str8)")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                // インポートボタン
                Button(action: {
                    showImporter = true
                }) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("インポート")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                // 最終エクスポート日時表示
                HStack {
                    Text("最終エクスポート")
                    Spacer()
                    if lastBackupExportDate > 0 {
                        Text(Date(timeIntervalSinceReferenceDate: lastBackupExportDate), style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未実施")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 30日超過時の警告
                if shouldShowBackupWarning() {
                    Label("最後のバックアップから30日以上経っています", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("カレンダー設定")
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

    // MARK: - ヘルパー

    private func weekdayLabel(_ weekday: Int) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][weekday - 1] + "曜日"
    }

    /// 曜日デフォルト割当の Picker バインディング。なし選択で削除、未存在なら作成。
    private func weekdayTemplateBinding(_ weekday: Int) -> Binding<UUID?> {
        Binding(
            get: { assignments.first { $0.weekday == weekday }?.template?.id },
            set: { newID in
                let existing = assignments.filter { $0.weekday == weekday }
                if let newID, let template = templates.first(where: { $0.id == newID }) {
                    if let row = existing.first {
                        row.template = template
                        existing.dropFirst().forEach(modelContext.delete)  // 重複行は掃除
                    } else {
                        modelContext.insert(BandAssignment(weekday: weekday, template: template))
                    }
                } else {
                    existing.forEach(modelContext.delete)
                }
                try? modelContext.save()
            }
        )
    }

    private func authStateColor() -> Color {
        switch eventKit.authState {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func authStateLabel() -> String {
        switch eventKit.authState {
        case .authorized:
            return "許可済み"
        case .denied:
            return "拒否"
        case .unknown:
            return "未確認"
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// システムカレンダー同期（トグルON・今すぐ同期ボタン共通）。
    private func syncCalendarNow() {
        Task {
            if await eventKit.requestAccess() {
                eventKit.sync(into: modelContext)
                eventKit.observeChanges(into: modelContext)
            }
        }
    }

    /// 天気取得（トグルON・取得ボタン共通）。
    private func refreshWeatherNow() {
        Task {
            await weather.refresh(context: modelContext)
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

// MARK: - 枠テンプレートエディタ（最小版、磨き込みは P9）

struct BandTemplateEditorView: View {
    @Bindable var template: BandTemplate
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("テンプレート名") {
                TextField("テンプレート名", text: $template.name)
            }

            Section("枠") {
                ForEach(template.orderedBands) { band in
                    BandRowEditor(band: band)
                }
                .onDelete { offsets in
                    let bands = template.orderedBands
                    offsets.map { bands[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }

                Button("枠を追加") {
                    // 末尾（最大 endMinutes）の後ろに60分枠を置く
                    let start = min(template.bands.map(\.endMinutes).max() ?? 9 * 60, 1380)
                    let band = Band(name: "枠\(template.bands.count + 1)",
                                    startMinutes: start,
                                    endMinutes: min(start + 60, 1440))
                    band.template = template
                    modelContext.insert(band)
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 枠1行の編集（名前＋開始/終了時刻）。
// ponytail: DatePicker は 24:00 を表現できないため終了 24:00 は 0:00 と表示される（保存値は維持）
struct BandRowEditor: View {
    @Bindable var band: Band

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("枠名", text: $band.name)

            HStack {
                // 終了<開始 と隣接枠との重複はクランプで防ぐ（最低5分幅）
                DatePicker("開始",
                           selection: minuteBinding($band.startMinutes, clamp: {
                               max(neighborBounds.lower, min($0, band.endMinutes - 5))
                           }),
                           displayedComponents: .hourAndMinute)
                DatePicker("終了",
                           selection: minuteBinding($band.endMinutes, clamp: {
                               min(neighborBounds.upper, max($0, band.startMinutes + 5))
                           }),
                           displayedComponents: .hourAndMinute)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    /// startMinutes ソートでの前枠 endMinutes / 次枠 startMinutes（隣接枠との重複防止の境界）。
    private var neighborBounds: (lower: Int, upper: Int) {
        let siblings = band.template?.orderedBands ?? [band]
        guard let idx = siblings.firstIndex(where: { $0.id == band.id }) else { return (0, 1440) }
        let lower = idx > 0 ? siblings[idx - 1].endMinutes : 0
        let upper = idx + 1 < siblings.count ? siblings[idx + 1].startMinutes : 1440
        return (lower, upper)
    }

    private func minuteBinding(_ minutes: Binding<Int>, clamp: @escaping (Int) -> Int) -> Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = (minutes.wrappedValue % 1440) / 60
                components.minute = minutes.wrappedValue % 60
                return Calendar.current.date(from: components) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = clamp((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }
}

#Preview {
    NavigationStack {
        CalendarSettingsView()
    }
    .modelContainer(PreviewData.container)
}
