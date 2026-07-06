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

    @State private var engine: SortDeckEngine
    @State private var dragOffset: CGSize = .zero
    /// 仕分けデッキを提示した日（dayKey）。完走時にスタンプ（未完走なら次のフォアグラウンドで再提示）。
    @AppStorage("lastSortPromptDay") private var lastSortPromptDay = 0

    private let commitThreshold: CGFloat = 80

    init(tasks: [TaskItem]) {
        _engine = State(initialValue: SortDeckEngine(tasks: tasks))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if engine.isFinished {
                    Spacer()
                    ContentUnavailableView {
                        Label("仕分け完了", systemImage: "checkmark.circle.fill")
                    } description: {
                        Text("今日の浮遊タスクはすべて仕分けました。")
                    }
                    .onAppear { lastSortPromptDay = dayKey(.now) }
                    Button("閉じる") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("仕分けを閉じる")
                    Spacer()
                } else if let task = engine.current {
                    Text(engine.stage == .doneGate ? "もうやった？" : "今日やる？")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("あと\(engine.queue.count)件")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TaskCardView(task: task)
                        .padding(.horizontal, 24)
                        .offset(dragOffset)
                        .rotationEffect(.degrees(Double(dragOffset.width) / 20))
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

                    // スワイプの代替ボタン常設
                    HStack(spacing: 16) {
                        Button(engine.stage == .doneGate ? "まだ" : "1週間先送り") {
                            answer(right: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel(engine.stage == .doneGate ? "まだやっていない" : "1週間先送りする")

                        Button(engine.stage == .doneGate ? "やった" : "今日") {
                            answer(right: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityLabel(engine.stage == .doneGate ? "完了にする" : "今日やる")
                    }
                }

                Spacer()

                // undo / redo 常設（画面下中央）
                HStack(spacing: 32) {
                    Button(action: { engine.undo(); try? context.save() }) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!engine.canUndo)
                    .accessibilityLabel("直前の仕分けを巻き戻す")

                    Button(action: { engine.redo(); try? context.save() }) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!engine.canRedo)
                    .accessibilityLabel("巻き戻した仕分けをやり直す")
                }
                .font(.title3)
                .padding(.bottom, 12)
            }
            .padding(.top, 24)
            .navigationTitle("朝の仕分け")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityLabel("仕分けを中断して閉じる")
                }
            }
        }
        .onDisappear { try? context.save() }
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
