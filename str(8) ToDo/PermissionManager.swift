//
//  PermissionManager.swift
//  str(8) ToDo
//
//  起動時に P2P 通信で必要な権限（ローカルネットワーク / Bluetooth）をユーザーに要求する。
//  実装は str(8)_Talk (151E_copy/iosApp/Q1E/PermissionManager.swift) と同じ流儀：
//    - NWBrowser を Bonjour サービス型 _str8-approve._tcp で 2秒だけ起動 → ローカルネットワーク許可の
//      システムダイアログを誘発
//    - CBCentralManager を初期化 → Bluetooth 許可のシステムダイアログを誘発
//  権限は Info.plist の NSLocalNetworkUsageDescription / NSBluetoothAlwaysUsageDescription 等が必要。
//

import Foundation
import CoreBluetooth
import Network

@MainActor
final class PermissionManager: NSObject {
    static let shared = PermissionManager()

    private var bluetoothManager: CBCentralManager?
    private var localNetworkBrowser: NWBrowser?
    private var hasRequestedLocalNetwork = false

    private override init() {
        super.init()
    }

    /// アプリ起動時（str_8__ToDoApp.onAppear）に一度だけ呼ぶ。二度目以降は no-op。
    func requestRequiredPermissions() {
        requestLocalNetworkPermissionIfNeeded()
        requestBluetoothPermissionIfNeeded()
    }

    private func requestLocalNetworkPermissionIfNeeded() {
        guard !hasRequestedLocalNetwork else { return }
        hasRequestedLocalNetwork = true

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        // Info.plist の NSBonjourServices に宣言済みのサービス型を使う。
        // 未宣言の型をブラウズすると iOS にブロックされ、ローカルネットワーク許可が
        // 正しく要求されない。
        let browser = NWBrowser(
            for: .bonjour(type: "_str8-approve._tcp", domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.stopLocalNetworkBrowser()
                }
            default:
                break
            }
        }

        browser.start(queue: .main)
        localNetworkBrowser = browser

        // 2秒だけ探索して停止（許可ダイアログはこの間に出る）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.stopLocalNetworkBrowser()
        }
    }

    private func stopLocalNetworkBrowser() {
        localNetworkBrowser?.cancel()
        localNetworkBrowser = nil
    }

    private func requestBluetoothPermissionIfNeeded() {
        guard bluetoothManager == nil else { return }
        bluetoothManager = CBCentralManager(delegate: self, queue: .main)
    }
}

extension PermissionManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 状態が確定するまで manager を保持し続けて許可ダイアログを維持する。
            self.bluetoothManager = central
            if central.state == .poweredOn {
                self.stopLocalNetworkBrowser()
            }
        }
    }
}
