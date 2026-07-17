//
//  ShareViewController.swift
//  str8Share
//
//  iOS 共有シートから起動される Share Extension。テキスト・URL・画像を受け取り、
//  App Group `share-inbox/` に JSON+画像を書き出す。メインアプリが次回起動時に吸い上げる。
//

import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        let text = self.contentText
        let items = (self.extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        // extensionContext は didSelectPost 内で参照して閉じる必要があるため即キャプチャ。
        let ctx = self.extensionContext
        Task {
            await ShareInboxWriter.write(text: text, items: items)
            ctx?.completeRequest(returningItems: nil)
        }
    }

    override func configurationItems() -> [Any]! { [] }
}
