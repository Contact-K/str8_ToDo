//
//  TaskDetailView.swift
//  str8ToDo
//
//  タスク詳細表示・編集画面。承認フロー＋スター切替＋削除操作。
//

import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let task: TaskItem

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @State private var showDeleteConfirmation = false
    /// P18: フィールド右のペンから該当トピックだけをフォーカス編集で直接開く。
    @State private var focusedTopic: WHCategory? = nil
    /// P18: タイトル横のペンはトピック固定がない（what はフォーカス画面を持たない）ので、
    /// タイルグリッドの EventComposerView をそのまま開く。
    @State private var showFullEditor = false

    var body: some View {
        VStack(spacing: 0) {
            S8TopBar("詳細", sub: task.status.label) {
                HStack(spacing: 6) {
                    S8IconButton(icon: "star", accent: task.isImportant, action: toggleImportant)
                        .accessibilityLabel(task.isImportant ? "重要を解除" : "重要に設定")
                    S8IconButton(icon: "trash", action: { showDeleteConfirmation = true })
                        .accessibilityLabel("削除")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: - ヘッダ
                    headerSection

                    // MARK: - 時間セクション
                    if task.startDate != nil || task.rrule != nil || task.timeZoneIdentifier != nil {
                        timeSection
                    }

                    // MARK: - カテゴリ・場所・参加者・金額
                    if task.category != nil || task.profile != nil || task.place != nil
                        || !task.participantNames.isEmpty || task.amount != nil {
                        metadataSection
                    }

                    // MARK: - 通知
                    notificationSection

                    // MARK: - メモ
                    if !task.notes.isEmpty {
                        notesSection
                    }

                    // MARK: - 承認フロー & アクション
                    approvalSection

                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .confirmationDialog(
            "削除確認",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("削除", role: .destructive) {
                    deleteTask()
                }
            },
            message: {
                Text("\"\(task.title)\" を削除しますか？")
            }
        )
        .sheet(item: $focusedTopic) { category in
            EventComposerView(task: task, initialFocus: category)
        }
        .sheet(isPresented: $showFullEditor) {
            EventComposerView(task: task)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // ドットインジケーター
                Circle()
                    .fill(task.effectiveColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)

                        if task.isImportant {
                            Image(systemName: "star.fill")
                                .foregroundColor(c.accent)
                                .font(.callout)
                        }
                    }

                    statusBadge
                }
                Spacer()
                editPencil { showFullEditor = true }
            }
        }
    }

    /// Handoff: 各ステータスに対応する pill バッジ。
    /// active=accent-wash / done=ok-wash / approved=accent-wash（強調）。
    private var statusBadge: some View {
        let (fg, bg, icon, tag): (Color, Color, String, String) = {
            switch task.status {
            case .active:   return (c.accentInk, c.accentWash, "circle-dot", "active · 進行中")
            case .done:     return (c.ok, c.okWash, "check-circle", "done · 完了")
            case .approved: return (c.accentInk, c.accentWash, "check", "approved · 確定")
            }
        }()
        return HStack(spacing: 5) {
            S8Icon(name: icon, size: 11, color: fg)
            Text(tag).font(S8Font.jp(11, .medium)).foregroundColor(fg)
        }
        .padding(.horizontal, 11).padding(.vertical, 4)
        .background(bg)
        .clipShape(Capsule())
    }

    /// Handoff 07a: 承認フロー3ステップ丸表示（active → done → approved）。
    /// 現ステップは accent 実塗り、通過済みは実線、未来は破線＋lock。
    private func approvalStepRing(_ status: TaskStatus) -> some View {
        let steps: [(TaskStatus, String, String)] = [
            (.active, "check", "ACTIVE"),
            (.done, "check", "DONE"),
            (.approved, "lock", "APPROVED")
        ]
        return HStack(spacing: 0) {
            ForEach(0..<steps.count, id: \.self) { i in
                let (s, icon, tag) = steps[i]
                let state = stepState(current: status, step: s)
                stepNode(icon: icon, tag: tag, state: state)
                if i < steps.count - 1 {
                    let nextReached = Self.rank(steps[i + 1].0) <= Self.rank(status)
                    Rectangle()
                        .fill(nextReached ? c.accent : c.lineStrong)
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private enum StepState { case past, current, future }

    /// active=0, done=1, approved=2 の順序ランク。
    private static func rank(_ s: TaskStatus) -> Int {
        switch s {
        case .active:   return 0
        case .done:     return 1
        case .approved: return 2
        }
    }

    private func stepState(current: TaskStatus, step: TaskStatus) -> StepState {
        let cr = Self.rank(current), sr = Self.rank(step)
        if sr < cr { return .past }
        if sr == cr { return .current }
        return .future
    }

    private func stepNode(icon: String, tag: String, state: StepState) -> some View {
        let borderColor: Color = state == .current ? c.accent : c.lineStrong
        let bgColor: Color = state == .current ? c.accent : c.surface
        let iconColor: Color = state == .current ? c.onAccent : c.fg3
        let dashed = state == .future
        return VStack(spacing: 5) {
            ZStack {
                Circle().fill(bgColor)
                Circle().strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 3] : []))
                S8Icon(name: icon, size: 14, color: iconColor)
            }
            .frame(width: 34, height: 34)
            Text(tag)
                .font(S8Font.mono(8, state == .current ? .bold : .regular))
                .tracking(1.0)
                .foregroundColor(state == .current ? c.accentInk : c.fg3)
        }
        .frame(width: 60)
    }

    // MARK: - Time Section
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderRow(tag: "SCHEDULE", jp: "スケジュール", pencilTopic: .when)

            VStack(alignment: .leading, spacing: 6) {
                if task.isAllDay {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(c.info)
                        Text("終日")
                            .font(.subheadline)
                    }
                } else if let startDate = task.startDate {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(c.info)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("開始: \(formatDate(startDate))")
                                .font(.subheadline)
                            if let endDate = task.endDate {
                                Text("終了: \(formatDate(endDate))")
                                    .font(.subheadline)
                            }
                            Text("所要: \(durationText(task.duration))")
                                .font(S8Font.mono(13.5))
                                .foregroundColor(c.fg3)
                        }
                    }
                }

                if let rrule = task.rrule, !rrule.isEmpty {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundColor(c.info)
                        Text(simplifyRRule(rrule))
                            .font(.subheadline)
                    }
                }

                if let tzId = task.timeZoneIdentifier, !tzId.isEmpty {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(c.info)
                        Text(tzId)
                            .font(.caption)
                            .foregroundColor(c.fg3)
                    }
                }
            }
        }
    }

    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category = task.category {
                HStack {
                    Image(systemName: category.symbolName)
                        .foregroundColor(Color(hex: category.colorHex))
                    Text(category.name)
                        .font(.subheadline)
                    Spacer()
                    editPencil { focusedTopic = .which }
                }
                .padding(.vertical, 4)
            }

            if let profile = task.profile {
                HStack {
                    Image(systemName: profile.iconName)
                        .foregroundColor(c.fg3)
                    Text(profile.name)
                        .font(.subheadline)
                    Spacer()
                    editPencil { focusedTopic = .which }
                }
                .padding(.vertical, 4)
            }

            if let place = task.place, !place.name.isEmpty {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(c.danger)
                    Text(place.name)
                        .font(.subheadline)
                    Spacer()
                    editPencil { focusedTopic = .where_ }
                }
                .padding(.vertical, 4)
            }

            if !task.participantNames.isEmpty {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(c.info)
                    Text(task.participantNames.joined(separator: ", "))
                        .font(.subheadline)
                    Spacer()
                    editPencil { focusedTopic = .who }
                }
                .padding(.vertical, 4)
            }

            if let amount = task.amount, amount > 0 {
                HStack {
                    Image(systemName: "yen.circle.fill")
                        .foregroundColor(c.ok)
                    Text(currencyText(amount))
                        .font(.subheadline)
                    Spacer()
                    editPencil { focusedTopic = .how }
                }
                .padding(.vertical, 4)

                if let method = task.paymentMethod, !method.isEmpty {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(c.fg3)
                        Text(method)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Notification Section
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderRow(tag: "NOTIFY", jp: "通知", pencilTopic: .when)

            if task.notificationOffsets.isEmpty {
                HStack {
                    Image(systemName: "bell.slash")
                        .foregroundColor(c.fg3)
                    Text("なし")
                        .font(.subheadline)
                        .foregroundColor(c.fg3)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.notificationOffsets.sorted(), id: \.self) { offset in
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(c.warn)
                            Text(formatNotificationOffset(offset))
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderRow(tag: "NOTES", jp: "メモ", pencilTopic: .other)

            Text(task.notes)
                .font(.subheadline)
                .lineLimit(nil)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(c.surface2)
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        }
    }

    // MARK: - Approval Section
    /// Handoff 07a: APPROVAL セクション。3ステップリング＋状態別アクション。
    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("APPROVAL", jp: "承認フロー")

            approvalStepRing(task.status)
                .padding(.vertical, 4)

            switch task.status {
            case .active:
                S8Button("完了にする", icon: "check", variant: .primary, action: markDone)
            case .done:
                Text("翌日 0:00 に解除 ── 未来の自分が承認するとstatsに確定")
                    .font(S8Font.jp(11.5))
                    .foregroundColor(c.fg3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 2)
                if task.isAwaitingFutureSelf {
                    // ロック中: 解除時刻を明示
                    HStack(spacing: 8) {
                        S8Icon(name: "lock", size: 13, color: c.fg3)
                        Text(task.unlockDate.map { "解除 \(formatDate($0))" } ?? "解除待ち")
                            .font(S8Font.mono(12)).foregroundColor(c.fg3)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(c.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                } else {
                    S8Button("承認して確定する", icon: "check-circle", variant: .primary, action: approve)
                }
            case .approved:
                HStack(spacing: 8) {
                    S8Icon(name: "check", size: 14, color: c.ok)
                    Text("確定済み").font(S8Font.jp(13.5, .bold)).foregroundColor(c.ok)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(c.okWash)
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
            }
        }
    }

    // MARK: - Section Heading
    /// Handoff: [MONO tag][JP label][hairline][pencil?] の1行見出し。
    /// pencilTopic を渡すと右端にペンボタン。
    private func sectionHeaderRow(tag: String, jp: String, pencilTopic: WHCategory? = nil) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
            if let topic = pencilTopic {
                S8Icon(name: "settings", size: 13, color: c.fg3)
                    .padding(.leading, 4)
                    .onTapGesture { focusedTopic = topic }
                    .accessibilityLabel("編集")
            }
        }
    }

    /// 互換用エイリアス（pencil なし）。
    private func sectionHeading(_ tag: String, jp: String) -> some View {
        sectionHeaderRow(tag: tag, jp: jp, pencilTopic: nil)
    }

    // MARK: - Edit Pencil
    /// P18: フィールド右の共通ペンボタン。タップで該当トピックのフォーカス編集を開く。
    /// iconbtn 相当：fg2 アイコン、押下時は surface の丸背景が浮く。
    private func editPencil(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.caption)
                .foregroundColor(c.fg2)
                .padding(6)
                .background(Circle().fill(c.surface))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("編集")
    }

    // MARK: - Actions
    private func toggleImportant() {
        task.isImportant.toggle()
        save()
    }

    private func markDone() {
        task.markDone()
        save()
    }

    private func approve() {
        task.approve(by: "self-future", context: modelContext)
        save()
    }

    private func deleteTask() {
        // 削除後にプロパティへ触れないよう先に退避
        let hadAmount = task.amount != nil
        let startDate = task.startDate
        let rrule = task.rrule

        NotificationService.cancel(for: task)
        modelContext.delete(task)
        save()

        // 金額がある場合は月別統計を再計算（反復タスクは全月）
        if hadAmount, let startDate {
            recomputeMonthRange(from: startDate, rrule: rrule)
        }

        dismiss()
    }

    /// 削除後にタスク参照が使えないので、start＋rrule だけ受け取って月範囲を独立に再計算する。
    private func recomputeMonthRange(from start: Date, rrule: String?) {
        let cal = Calendar.current
        if rrule == nil {
            MoneyStats.recompute(month: start, context: modelContext)
            return
        }
        let cap = cal.date(byAdding: .year, value: 3, to: .now) ?? .now
        var cursor = cal.dateInterval(of: .month, for: start)?.start ?? cal.startOfDay(for: start)
        let endMonth = cal.dateInterval(of: .month, for: cap)?.end ?? cap
        while cursor < endMonth {
            MoneyStats.recompute(month: cursor, context: modelContext)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting Helpers
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func simplifyRRule(_ rrule: String) -> String {
        // 簡易実装：FREQ から抽出
        if rrule.contains("FREQ=DAILY") {
            return "毎日"
        } else if rrule.contains("FREQ=WEEKLY") {
            return "毎週"
        } else if rrule.contains("FREQ=MONTHLY") {
            return "毎月"
        } else if rrule.contains("FREQ=YEARLY") {
            return "毎年"
        }
        return rrule
    }

    private func formatNotificationOffset(_ offset: Int) -> String {
        let minutes = offset

        if minutes < 60 {
            return "\(minutes)分前"
        } else if minutes < 1440 {
            let hours = minutes / 60
            return "\(hours)時間前"
        } else if minutes == 1440 {
            return "前日"
        } else {
            let days = minutes / 1440
            return "\(days)日前"
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        TaskDetailView(task: TaskItem(title: "サンプルタスク"))
    }
}
