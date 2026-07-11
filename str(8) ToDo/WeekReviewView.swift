//
//  WeekReviewView.swift
//  str8ToDo
//
//  週次締めの儀式（Phase 13）。3 セクション: 確定キュー一掃 / 週報 / 来週プレビュー。
//  chop で締めて WeekReview を1件保存。静止画エクスポート付き。読み取りは WeekReportSource 経由。
//

import SwiftUI
import SwiftData
import os.log

struct WeekReviewView: View {
    // MARK: - Inits and State
    /// 対象週内の任意の日（既定は今日）。この日を含む週の月曜〜次週月曜を対象とする。
    var referenceDate: Date = .now
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isShareSheetPresented = false
    @State private var shareImage: UIImage? = nil
    @State private var isSaving = false
    @State private var fetchError = false
    @State private var saveFailed = false
    @State private var saveErrorMessage = ""

    private var range: Range<Date> { WeekMath.weekRange(of: referenceDate) }
    private var nextRange: Range<Date> {
        let nextStart = Calendar.current.date(byAdding: .day, value: 7, to: range.lowerBound)!
        return nextStart ..< Calendar.current.date(byAdding: .day, value: 7, to: nextStart)!
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
                    .disabled(isSaving || fetchError)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportImage) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $isShareSheetPresented) {
                if let img = shareImage {
                    ShareSheet(items: [img])
                }
            }
            .alert("エラー", isPresented: $fetchError) {
                Button("OK") { fetchError = false }
            } message: {
                Text("データ取得に失敗しました。もう一度お試しください。")
            }
            .alert("エラー", isPresented: $saveFailed) {
                Button("リトライ") { saveFailed = false; commitAndClose() }
                Button("閉じる") { saveFailed = false; dismiss(); onClose?() }
            } message: {
                Text("保存に失敗しました：\(saveErrorMessage)")
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
        let focus = WeekReportSource.focusTotalSec(in: range, context: context)
        let money = WeekReportSource.moneyTotal(in: range, context: context)
        let done = WeekReportSource.doneCount(in: range, context: context)
        return VStack(alignment: .leading, spacing: 12) {
            Text("週報").font(.headline)
            HStack {
                statTile(label: "集中", value: formatDuration(focus))
                statTile(label: "完了", value: "\(done)")
                statTile(label: "収支", value: formatMoney(money))
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

    // MARK: 締め（chop or ボタン）
    private func commitAndClose() {
        guard !isSaving else { return }
        isSaving = true

        // fetch 失敗時の保護（修正3）
        do {
            _ = try context.fetch(FetchDescriptor<TaskItem>())
        } catch {
            fetchError = true
            isSaving = false
            return
        }

        let focus = WeekReportSource.focusTotalSec(in: range, context: context)
        let money = WeekReportSource.moneyTotal(in: range, context: context)
        let done = WeekReportSource.doneCount(in: range, context: context)

        // upsert パターン：既存の同 weekStart レコードを fetch し、あれば値を上書き、無ければ insert（修正1b）
        let descriptor = FetchDescriptor<WeekReview>(predicate: #Predicate { $0.weekStart == range.lowerBound })
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.closedAt = .now
                existing.focusTotalSec = focus
                existing.moneyTotal = money
                existing.doneCount = done
            } else {
                let review = WeekReview(weekStart: range.lowerBound, closedAt: .now, focusTotalSec: focus, moneyTotal: money, doneCount: done)
                context.insert(review)
            }
            try context.save()
            isSaving = false
            dismiss()
            onClose?()
        } catch {
            os_log("WeekReview save failed: %@", log: .default, type: .error, error.localizedDescription)
            saveErrorMessage = error.localizedDescription
            saveFailed = true
            isSaving = false
        }
    }

    // MARK: 静止画エクスポート
    @MainActor
    private func exportImage() {
        let renderer = ImageRenderer(content: reportSection.padding(20).background(Color(.systemBackground)))
        renderer.scale = UIScreen.main.scale
        shareImage = renderer.uiImage
        if shareImage != nil { isShareSheetPresented = true }
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
