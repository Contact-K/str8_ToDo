//
//  WeekReviewView.swift
//  str8ToDo
//
//  週次締めの儀式（Phase 13）。3 セクション: 確定キュー一掃 / 週報 / 来週プレビュー。
//  WeekReview モデルは廃止（閲覧 UI なし＋書き込み専用は不要というオーナー判断、2026-07-11）。
//  「締める」は都度計算した週報を確認して閉じるだけの操作で、永続化はしない。
//  読み取りは WeekReportSource 経由。
//

import SwiftUI
import SwiftData

struct WeekReviewView: View {
    // MARK: - Inits and State
    /// 対象週内の任意の日（既定は今日）。この日を含む週の月曜〜次週月曜を対象とする。
    /// sheet 表示中に日付境界を跨いでも週が切り替わらないよう、init 時に @State へ固定する。
    @State private var referenceDate: Date
    var onClose: (() -> Void)? = nil

    init(initialReferenceDate: Date = .now, onClose: (() -> Void)? = nil) {
        _referenceDate = State(initialValue: initialReferenceDate)
        self.onClose = onClose
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @AppStorage(AppSettingsKey.weekShowSevenDays) private var showSevenDays = AppSettingsKey.weekShowSevenDaysDefault
    @State private var isShareSheetPresented = false
    @State private var shareImage: UIImage? = nil
    @State private var fetchError = false
    @State private var exportFailed = false
    @State private var cachedReport: WeekReportSource.WeekReport? = nil

    /// WeekView と週境界（firstWeekday）を統一する（WeekMath 参照、ハードコードしない）。
    private var firstWeekday: Int { WeekMath.firstWeekday(showSevenDays: showSevenDays) }
    private var range: Range<Date> { WeekMath.weekRange(of: referenceDate, firstWeekday: firstWeekday) }
    private var nextRange: Range<Date> {
        let nextDate = Calendar.current.date(byAdding: .day, value: 7, to: referenceDate) ?? referenceDate
        return WeekMath.weekRange(of: nextDate, firstWeekday: firstWeekday)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    approvalSection
                    reportSection
                    nextWeekPreviewSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("今週の締め")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss(); onClose?() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: commitAndClose) {
                        Label("締める", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(fetchError)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: exportImage) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task(id: referenceDate) {
                cachedReport = WeekReportSource.load(in: range, context: context)
            }
            .sheet(isPresented: $isShareSheetPresented) {
                // ponytail: ShareLink(item:) は URL/String のみ対応（このSDKに UIImage 向けの直接オーバーロードなし）。
                // Data/URL 化するには一時ファイル書き出しが必要で ShareSheet より複雑になるため、UIActivityViewController のままにする。
                if let img = shareImage {
                    ShareSheet(items: [img])
                }
            }
            .alert("エラー", isPresented: $fetchError) {
                Button("OK") { fetchError = false }
            } message: {
                Text("データ取得に失敗しました。もう一度お試しください。")
            }
            .alert("エラー", isPresented: $exportFailed) {
                Button("OK") { exportFailed = false }
            } message: {
                Text("画像の生成に失敗しました")
            }
        }
    }

    // MARK: 確定キュー
    private var approvalSection: some View {
        // ApprovalQueueView を丸ごと埋め込むと NavigationStack が二重になるので、
        // ApprovalQueueView の本体（.approvalPending の一覧＋chop での確定ロジック）は既に承認タブで機能している。
        // ここではリンクだけ提供（ユーザーは既存タブで一掃する）。ponytail: 統合 UI は将来
        VStack(alignment: .leading, spacing: 8) {
            Text("確定キュー一掃").font(.headline)
            Text("未確定タスクは『承認』タブで一掃してから戻ってください。").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 週報
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("週報").font(.headline)
            if let report = cachedReport {
                HStack {
                    statTile(label: "集中", value: formatDuration(report.focusTotalSec))
                    statTile(label: "完了", value: "\(report.approvedCount)")
                    statTile(label: "収支", value: formatMoney(report.moneyTotal))
                }
            } else {
                // .task(id: referenceDate) が読み込むまでの初回描画用（M3）
                ProgressView("読み込み中…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 来週プレビュー
    private var nextWeekPreviewSection: some View {
        let tasks = WeekReportSource.timedTasks(in: nextRange, context: context)
        return VStack(alignment: .leading, spacing: 8) {
            Text("来週の予定 (\(tasks.count))").font(.headline)
            if tasks.isEmpty {
                Text("時刻付きの予定はありません").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    HStack {
                        Text(formatDate(task.startDate ?? .now)).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(task.title).font(.callout)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statTile(label: String, value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: 締め（確認して閉じるだけ。WeekReview モデル廃止のため永続化はしない）
    private func commitAndClose() {
        // fetch 失敗時の保護：データが読めない状態のまま締めない
        do {
            _ = try context.fetch(FetchDescriptor<TaskItem>())
        } catch {
            fetchError = true
            return
        }
        dismiss()
        onClose?()
    }

    // MARK: 静止画エクスポート
    @MainActor
    private func exportImage() {
        let renderer = ImageRenderer(content: reportSection.padding(20).background(Color(.systemBackground)))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else {
            exportFailed = true
            return
        }
        shareImage = image
        isShareSheetPresented = true
    }

    // MARK: ヘルパー
    private func formatDuration(_ sec: TimeInterval) -> String {
        let h = Int(sec / 3600); let m = Int((sec.truncatingRemainder(dividingBy: 3600)) / 60)
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
    private func formatMoney(_ d: Decimal) -> String {
        let ns = NSDecimalNumber(decimal: d)
        return NumberFormatter.localizedString(from: ns, number: .decimal) + "円"
    }
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMdEEE HH:mm"); return f
    }()
    private func formatDate(_ d: Date) -> String { Self.df.string(from: d) }
}

// UIActivityViewController ラッパ
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    WeekReviewView().modelContainer(PreviewData.container)
}
