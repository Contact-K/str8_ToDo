import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct ShareComposeView: View {
    private enum Kind { case task, calendar }

    let imageProviders: [NSItemProvider]
    let onSave: (_ title: String, _ notes: String, _ startDate: Date?, _ durationMin: Int?) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var kind: Kind = .task
    @State private var startDate = Date()
    @State private var durationMin = 60
    @Environment(\.colorScheme) private var scheme

    init(
        text: String,
        imageProviders: [NSItemProvider],
        onSave: @escaping (_ title: String, _ notes: String, _ startDate: Date?, _ durationMin: Int?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        _title = State(initialValue: parts.first.map(String.init) ?? "")
        _notes = State(initialValue: parts.dropFirst().first.map(String.init) ?? "")
        self.imageProviders = imageProviders
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        let c = S8Palette.of(scheme)
        // ponytail: extension uses default accent; move "s8_accent" to app-group defaults if it matters
        VStack(spacing: 0) {
            S8TopBar("共有を追加", sub: "SHARE") {
                HStack(spacing: 4) {
                    S8IconButton(icon: "x", action: onCancel)
                    S8IconButton(icon: "check", accent: true) {
                        onSave(
                            title,
                            notes,
                            kind == .calendar ? startDate : nil,
                            kind == .calendar ? durationMin : nil
                        )
                    }
                }
            }
            S8Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: S8Space.s5) {
                    S8Field(label: "タイトル", placeholder: "タイトル", text: $title)
                    S8Field(label: "メモ", placeholder: "メモ", text: $notes)

                    if !imageProviders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: S8Space.s2) {
                                ForEach(imageProviders.indices, id: \.self) { index in
                                    ShareThumbnail(provider: imageProviders[index])
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: S8Space.s3) {
                        S8Cap(text: "種類")
                        HStack(spacing: S8Space.s2) {
                            S8Chip("タスク", icon: "check-circle", selected: kind == .task) {
                                kind = .task
                            }
                            S8Chip("カレンダー", icon: "calendar", selected: kind == .calendar) {
                                kind = .calendar
                            }
                        }
                    }

                    if kind == .calendar {
                        VStack(spacing: S8Space.s4) {
                            HStack {
                                Text("開始").font(S8Font.jp(13)).foregroundColor(c.fg2)
                                Spacer()
                                S8DatePicker(date: $startDate, showTime: true, minuteStep: 5)
                            }
                            HStack {
                                Text("所要時間").font(S8Font.jp(13)).foregroundColor(c.fg2)
                                Spacer()
                                S8Stepper(value: $durationMin, range: 5...480, step: 5, unit: "分", width: 132)
                            }
                        }
                    }
                }
                .padding(S8Space.s5)
            }
        }
        .background(c.paper.ignoresSafeArea())
    }
}

private struct ShareThumbnail: View {
    let provider: NSItemProvider
    @State private var image: CGImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                S8Icon(name: "image", size: 20, color: c.fg3)
            }
        }
        .frame(width: 56, height: 56)
        .background(c.surface2)
        .clipShape(RoundedRectangle(cornerRadius: S8Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: S8Radius.lg).stroke(c.line, lineWidth: 1))
        .task { image = await Self.loadThumbnail(from: provider) }
    }

    private static func loadThumbnail(from provider: NSItemProvider) async -> CGImage? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url,
                      let source = CGImageSourceCreateWithURL(url as CFURL, [
                        kCGImageSourceShouldCache: false
                      ] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                let options: CFDictionary = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 168,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
                continuation.resume(returning: CGImageSourceCreateThumbnailAtIndex(source, 0, options))
            }
        }
    }
}
