//
//  ContentView.swift
//  str8ToDo
//
//  5本柱のタブバー：カレンダー・タイマー・リスト・承認・Study Hub。
//  P0 ではカレンダーのみ実装。残りはプレースホルダ。
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("カレンダー", systemImage: "calendar") {
                CalendarRootView()
            }
            Tab("タイマー", systemImage: "hourglass") {
                ComingSoonView(
                    title: "砂時計タイマー",
                    detail: "立てる→寝かす→伏せてスタート。\nCoreMotion + AlarmKit（P1以降）。"
                )
            }
            Tab("リスト", systemImage: "checklist") {
                ComingSoonView(
                    title: "ToDo リスト",
                    detail: "朝の仕分けカードの出力を常時見られるビュー。\n今日／いつか(1週間)／いつか(1ヶ月)。"
                )
            }
            Tab("承認", systemImage: "checkmark.seal") {
                ComingSoonView(
                    title: "承認プロトコル",
                    detail: "完了は他者（または未来の自分）の物理ハンコで承認。\nMultipeerConnectivity + NearbyInteraction。"
                )
            }
            Tab("Study Hub", systemImage: "books.vertical") {
                ComingSoonView(
                    title: "Study Hub",
                    detail: "科目管理・集中統計・目標とストリーク。"
                )
            }
        }
    }
}

/// 未実装タブの共通プレースホルダ。
struct ComingSoonView: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "wrench.and.screwdriver")
            } description: {
                Text(detail)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
