//
//  ShareViewController.swift
//  str8Share
//
//  iOS 共有シートから起動される Share Extension。テキスト・URL・画像を受け取り、
//  App Group `share-inbox/` に JSON+画像を書き出す。メインアプリが次回起動時に吸い上げる。
//

import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    private var inputItems: [NSExtensionItem] = []
    private var isCompleting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        inputItems = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let items = inputItems
        Task {
            let preview = await ShareInboxWriter.extractPreview(items: items)
            showCompose(preview: preview)
        }
    }

    private func showCompose(preview: (text: String, imageProviders: [NSItemProvider])) {
        let root = ShareComposeView(
            text: preview.text,
            imageProviders: preview.imageProviders,
            onSave: { [weak self] title, notes, startDate, durationMin in
                self?.save(title: title, notes: notes, startDate: startDate, durationMin: durationMin)
            },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func save(title: String, notes: String, startDate: Date?, durationMin: Int?) {
        guard !isCompleting else { return }
        isCompleting = true
        let context = extensionContext
        let items = inputItems
        Task {
            await ShareInboxWriter.write(
                title: title,
                notes: notes,
                items: items,
                startDate: startDate,
                durationMin: durationMin
            )
            context?.completeRequest(returningItems: nil)
        }
    }

    private func cancel() {
        guard !isCompleting else { return }
        isCompleting = true
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}
