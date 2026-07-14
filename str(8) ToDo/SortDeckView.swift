//
//  SortDeckView.swift
//  str8ToDo
//
//  朝の仕分けデッキ UI。スワイプ（右=やった/今日、左=まだ/先送り）＋代替ボタン常設。
//  ロジックは SortDeckEngine に委譲。VoiceOver はボタンだけで完走できる。
//

import SwiftUI
import SwiftData

struct SortDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @State private var engine: SortDeckEngine
    @State private var dragOffset: CGSize = .zero
    /// 仕分けデッキを提示した日（dayKey）。完走時にスタンプ（未完走なら次のフォアグラウンドで再提示）。
    @AppStorage("lastSortPromptDay") private var lastSortPromptDay = 0

    private let commitThreshold: CGFloat = 80

    init(tasks: [TaskItem]) {
        _engine = State(initialValue: SortDeckEngine(tasks: tasks))
    }

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            // Handoff header: [閉じる][朝の仕分け][spacer]
            HStack {
                Button("閉じる") { dismiss() }
                    .font(S8Font.jp(14))
                    .foregroundColor(c.fg2)
                    .accessibilityLabel("仕分けを中断して閉じる")
                Spacer()
                Text("朝の仕分け").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            if engine.isFinished {
                Spacer()
                ContentUnavailableView {
                    Label("仕分け完了", systemImage: "checkmark.circle.fill")
                } description: {
                    Text("今日の浮遊タスクはすべて仕分けました。")
                }
                .onAppear { lastSortPromptDay = dayKey(.now) }
                S8Button("閉じる", variant: .primary, fillWidth: false, action: { dismiss() })
                    .padding(.top, 12)
                Spacer()
            } else if let task = engine.current {
                deckContent(task: task)
            }
            Spacer(minLength: 0)
        }
        .background(c.paper.ignoresSafeArea())
        .onDisappear { try? context.save() }
    }

    /// Handoff 03b: 大判カード + プロンプト + 代替ボタン + undo/redo。
    @ViewBuilder
    private func deckContent(task: TaskItem) -> some View {
        let c = self.c
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(engine.stage == .doneGate ? "もうやった？" : "今日やる？")
                    .font(S8Font.jp(22, .bold)).foregroundColor(c.fg1)
                Text("あと\(engine.queue.count)件")
                    .font(S8Font.mono(11)).tracking(1.2).foregroundColor(c.fg3)
            }
            .padding(.top, 16)

            // カード
            ZStack {
                // 背後のダミー（Handoff の -1.5deg 傾き）
                if engine.queue.count > 1 {
                    RoundedRectangle(cornerRadius: S8Radius.lg)
                        .fill(c.surface)
                        .overlay(RoundedRectangle(cornerRadius: S8Radius.lg).stroke(c.line, lineWidth: 1))
                        .rotationEffect(.degrees(-1.5))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 8)
                }
                bigCard(task: task)
                    .rotationEffect(.degrees(1.5))
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width) / 20))
                    .padding(.horizontal, 24)
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { value in
                                if value.translation.width > commitThreshold {
                                    answer(right: true)
                                } else if value.translation.width < -commitThreshold {
                                    answer(right: false)
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = .zero
                                }
                            }
                    )
                    .accessibilityElement(children: .combine)
            }

            HStack {
                Text("← まだ")
                    .font(S8Font.mono(9.5)).tracking(1.2).foregroundColor(c.fg3)
                Spacer()
                Text("やった →")
                    .font(S8Font.mono(9.5)).tracking(1.2).foregroundColor(c.accentInk)
            }
            .padding(.horizontal, 32)

            // 代替ボタン
            HStack(spacing: 12) {
                S8Button(engine.stage == .doneGate ? "まだ" : "1週間先送り",
                         variant: .secondary, action: { answer(right: false) })
                    .accessibilityLabel(engine.stage == .doneGate ? "まだやっていない" : "1週間先送りする")
                S8Button(engine.stage == .doneGate ? "やった" : "今日",
                         variant: .primary, action: { answer(right: true) })
                    .accessibilityLabel(engine.stage == .doneGate ? "完了にする" : "今日やる")
            }
            .padding(.horizontal, 24)

            // undo / redo
            HStack(spacing: 44) {
                Button(action: { engine.undo(); try? context.save() }) {
                    S8Icon(name: "arrow-left", size: 21, color: engine.canUndo ? c.fg2 : c.fg3.opacity(0.4))
                }
                .disabled(!engine.canUndo)
                .accessibilityLabel("直前の仕分けを巻き戻す")

                Button(action: { engine.redo(); try? context.save() }) {
                    S8Icon(name: "arrow-right", size: 21, color: engine.canRedo ? c.fg2 : c.fg3.opacity(0.4))
                }
                .disabled(!engine.canRedo)
                .accessibilityLabel("巻き戻した仕分けをやり直す")
            }
            .padding(.top, 8)

            Text(engine.stage == .doneGate
                 ? "第2段は「今日やる？」── 右=今日 / 左=1週間先送り"
                 : "第1段は「もうやった？」── 右=やった / 左=まだ")
                .font(S8Font.jp(11)).foregroundColor(c.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    /// Handoff 03b: 大判カード（カテゴリ + タイトル + サブタイトル + DUE/EST/SNOOZE リードアウト）。
    private func bigCard(task: TaskItem) -> some View {
        let c = self.c
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // カテゴリチップ
                if let cat = task.category {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: cat.colorHex)).frame(width: 6, height: 6)
                        Text(cat.name).font(S8Font.jp(11)).foregroundColor(Color(hex: cat.colorHex))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Color(hex: cat.colorHex).opacity(0.14))
                    .clipShape(Capsule())
                }
                Spacer()
                if task.isImportant {
                    S8Icon(name: "star", size: 15, color: c.accent)
                }
            }
            .padding(.horizontal, 22).padding(.top, 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(S8Font.jp(23, .bold)).foregroundColor(c.fg1)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !task.notes.isEmpty {
                    Text(task.notes).font(S8Font.jp(12.5)).foregroundColor(c.fg2)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)

            Rectangle().fill(c.line).frame(height: 1)

            HStack(spacing: 1) {
                readoutTile(cap: "DUE", value: dueText(task), color: dueColor(task))
                Rectangle().fill(c.line).frame(width: 1)
                readoutTile(cap: "EST", value: estText(task), color: c.fg1)
                Rectangle().fill(c.line).frame(width: 1)
                readoutTile(cap: "SNOOZE", value: snoozeText(task), color: c.fg1)
            }
            .background(c.line)
        }
        .background(c.surface)
        .overlay(RoundedRectangle(cornerRadius: S8Radius.lg).stroke(c.lineStrong, lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle().fill(task.effectiveColor ?? c.accent).frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: S8Radius.lg))
        .shadow(color: Color.black.opacity(0.09), radius: 18, x: 0, y: 8)
    }

    private func readoutTile(cap: String, value: String, color: Color) -> some View {
        let c = self.c
        return VStack(alignment: .leading, spacing: 2) {
            Text(cap).font(S8Font.mono(8)).tracking(1.4).foregroundColor(c.fg3)
            Text(value).font(S8Font.mono(14, .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(c.surface)
    }

    private func dueText(_ task: TaskItem) -> String {
        guard let d = task.startDate else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M/d E"
        return f.string(from: d)
    }

    private func dueColor(_ task: TaskItem) -> Color {
        guard let d = task.startDate else { return c.fg3 }
        return d < .now ? c.danger : c.fg1
    }

    private func estText(_ task: TaskItem) -> String {
        let mins = Int(task.duration / 60)
        return mins > 0 ? "\(mins)分" : "—"
    }

    private func snoozeText(_ task: TaskItem) -> String {
        task.snoozeUntil == nil ? "—" : "×1"
    }

    private func answer(right: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if right {
                engine.answerRight()
            } else {
                engine.answerLeft()
            }
        }
        try? context.save()
    }
}

#Preview {
    SortDeckView(tasks: [])
        .modelContainer(PreviewData.container)
}
