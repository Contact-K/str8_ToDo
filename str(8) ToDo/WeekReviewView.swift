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
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
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
        // ponytail: NavigationStack+toolbar を廃止。iOS26 の toolbar が自動 liquid glass を付けるので
        // s8 統一の S8TopBar+S8Button に置換
        VStack(spacing: 0) {
            S8TopBar("今週の締め", sub: "weekly review") {
                S8IconButton(icon: "share", action: exportImage)
                    .accessibilityLabel("画像でシェア")
            }

            HStack(spacing: 10) {
                S8Button("閉じる", icon: "x", variant: .ghost, fillWidth: false, action: { dismiss(); onClose?() })
                Spacer()
                S8Button("締める", icon: "check", variant: .primary, fillWidth: false, action: commitAndClose)
                    .disabled(fetchError)
            }
            .padding(.horizontal, 24).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 24) {
                    approvalSection
                    reportSection
                    nextWeekPreviewSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .background(c.paper.ignoresSafeArea())
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

    // MARK: 確定キュー（Handoff 06a: QUEUE 未確定件数バナー）
    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCap("QUEUE", jp: "確定キュー一掃")
            let pending = WeekReportSource.pendingApprovalCount(in: range, context: context)
            HStack(spacing: 12) {
                Text("\(pending)件")
                    .font(S8Font.mono(15, .bold)).foregroundColor(c.accentInk)
                Text(pending > 0 ? "未確定のタスクが残っています" : "未確定なし。清々しい")
                    .font(S8Font.jp(13)).foregroundColor(c.fg2)
                Spacer()
                if pending > 0 {
                    Text("承認タブへ →")
                        .font(S8Font.jp(12.5, .bold)).foregroundColor(c.accentInk)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(c.surface)
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(c.lineStrong, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 週報（Handoff 06a: REPORT 3タイル）
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCap("REPORT · \(rangeCaptionText())", jp: "週報")
            if let report = cachedReport {
                HStack(spacing: 10) {
                    statTile(label: "集中", value: formatDuration(report.focusTotalSec))
                    statTile(label: "完了", value: "\(report.approvedCount)")
                    statTile(label: "収支", value: formatMoney(report.moneyTotal))
                }
            } else {
                ProgressView("読み込み中…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 来週プレビュー（Handoff 06a: NEXT WEEK 予定リスト）
    private var nextWeekPreviewSection: some View {
        let tasks = WeekReportSource.timedTasks(in: nextRange, context: context)
        return VStack(alignment: .leading, spacing: 8) {
            sectionCap("NEXT WEEK · \(tasks.count)", jp: "来週の予定")
            if tasks.isEmpty {
                Text("時刻付きの予定はありません").font(S8Font.jp(12.5)).foregroundColor(c.fg3)
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        HStack(spacing: 12) {
                            Text(formatDate(task.startDate ?? .now))
                                .font(S8Font.mono(11)).foregroundColor(c.fg3)
                                .frame(width: 90, alignment: .leading)
                            Text(task.title).font(S8Font.jp(13.5)).foregroundColor(c.fg1).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .top) { S8Rule() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Handoff 見出し行: [MONO tag][JP label][hairline]。
    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
    }

    private func rangeCaptionText() -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"
        let start = range.lowerBound
        let end = Calendar.current.date(byAdding: .day, value: -1, to: range.upperBound) ?? range.upperBound
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private func statTile(label: String, value: String) -> some View {
        VStack {
            Text(value).font(S8Font.mono(13.5)).fontWeight(.bold)
            Text(label).font(S8Font.mono(11)).tracking(1.5).foregroundStyle(c.fg3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(c.surface2)
        .clipShape(RoundedRectangle(cornerRadius: S8Radius.lg))
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
        let renderer = ImageRenderer(content: reportSection.padding(20).background(c.paper))
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
