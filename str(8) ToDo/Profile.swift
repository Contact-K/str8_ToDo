//
//  Profile.swift
//  str8ToDo
//
//  which（どれ）分類の文脈タグ。会社/個人などプロフィール単位でタスクを紐付ける。
//

import Foundation
import SwiftData

@Model
final class Profile {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String

    @Relationship(deleteRule: .nullify)
    var tasks: [TaskItem]?

    init(id: UUID = UUID(), name: String, iconName: String, tasks: [TaskItem]? = nil) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.tasks = tasks
    }
}
