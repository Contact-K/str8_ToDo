//
//  ProximityGate.swift
//  str8ToDo
//
//  近接ゲート（UWB/BLE）。約10cm 以内で isNear = true。
//  - UWB 対応: NISession + discoveryToken（NINearbyPeerConfiguration）
//  - UWB 非対応: BLE RSSI フォールバック（RSSI > -40 dBm を近接とみなす）
//  - シミュレータ: 両方とも動作不可。simulatorBypass=true で isNear=true 固定（UI テスト用）
//  フォアグラウンド限定。
//

import Foundation
import SwiftUI

#if os(iOS)
import os.log

@MainActor
@Observable
final class ProximityGate: NSObject {
    private let logger = Logger(subsystem: "str8.ProximityGate", category: "proximity")

    #if canImport(NearbyInteraction)
    private var niSession: NISession?
    #endif

    #if canImport(CoreBluetooth)
    private var bleManager: BLEProximityManager?
    #endif

    private(set) var isNear = false
    var unavailableReason: String?
    var isSupported: Bool {
        #if canImport(NearbyInteraction)
        return NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        #else
        return false
        #endif
    }

    /// シミュレータでの UI テスト用。true で isNear=true 固定。
    var simulatorBypass = false

    override init() {
        super.init()
        #if canImport(NearbyInteraction)
        // 接続直後に localTokenData を送り合うため、対応機では最初からセッションを保持
        if isSupported {
            let session = NISession()
            session.delegate = self
            niSession = session
        }
        #endif
    }

    /// 相手の discoveryToken を受け取り、近接測定を開始。
    func start(withPeerToken peerTokenData: Data) {
        if simulatorBypass {
            isNear = true
            return
        }

        #if canImport(NearbyInteraction)
        if isSupported {
            startNI(withPeerToken: peerTokenData)
            return
        }
        #endif

        #if canImport(CoreBluetooth)
        startBLE()
        #endif
    }

    /// トークン交換なしで近接測定を開始（相手が UWB 非対応のとき）。BLE フォールバック直行。
    func startFallback() {
        if simulatorBypass {
            isNear = true
            return
        }
        #if canImport(CoreBluetooth)
        startBLE()
        #endif
    }

    /// 近接測定を停止。
    func stop() {
        #if canImport(NearbyInteraction)
        niSession = nil
        #endif

        #if canImport(CoreBluetooth)
        bleManager?.stop()
        bleManager = nil
        #endif

        isNear = false
    }

    /// 自分の discoveryToken。保持している niSession の実トークンをアーカイブして返す。
    var localTokenData: Data? {
        #if canImport(NearbyInteraction)
        guard let token = niSession?.discoveryToken else { return nil }
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        } catch {
            logger.error("Failed to archive discoveryToken: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(NearbyInteraction)
    private func startNI(withPeerToken peerTokenData: Data) {
        do {
            // niSession がなければ作成（初回のみ）
            if niSession == nil {
                guard isSupported else {
                    logger.error("NI is not supported on this device")
                    #if canImport(CoreBluetooth)
                    startBLE()
                    #endif
                    return
                }
                let session = NISession()
                session.delegate = self
                niSession = session
            }

            guard let session = niSession else {
                logger.error("Failed to create NISession")
                #if canImport(CoreBluetooth)
                startBLE()
                #endif
                return
            }

            guard let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData) else {
                logger.error("Failed to unarchive NIDiscoveryToken")
                #if canImport(CoreBluetooth)
                startBLE()
                #endif
                return
            }

            let config = NINearbyPeerConfiguration(peerToken: peerToken)
            session.run(config)
            // ponytail: invalidate 後の再 start では新しい NISession が作成され、localTokenData も新トークンになる
        } catch {
            logger.error("Failed to start NI session: \(error.localizedDescription)")
            #if canImport(CoreBluetooth)
            startBLE()
            #endif
        }
    }
    #endif

    #if canImport(CoreBluetooth)
    private func startBLE() {
        let manager = BLEProximityManager()
        manager.gate = self
        manager.onProximityChange = { [weak self] isNear in
            Task { @MainActor in
                self?.isNear = isNear
            }
        }
        manager.start()
        self.bleManager = manager
    }
    #endif
}

// MARK: - NISessionDelegate

#if canImport(NearbyInteraction)
import NearbyInteraction

extension ProximityGate: NISessionDelegate {
    nonisolated func sessionWasSuspended(_ session: NISession) {
        // ponytail: 中断の詳細ハンドルは必要時のみ
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        // 再開通知（使用不可は .unsupported で受け取る）
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else {
            Task { @MainActor in
                self.isNear = false
            }
            return
        }

        // ponytail: 0.10m しきい値（単純）。ヒステリシスは実機チューニング時に追加
        let distance = object.distance ?? 0.20
        let shouldBeNear = distance <= 0.10

        Task { @MainActor in
            self.isNear = shouldBeNear
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            self.isNear = false
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        // NI が実行時失敗 → BLE フォールバック開始
        Task { @MainActor in
            self.logger.warning("NI session invalidated: \(error.localizedDescription)")
            self.niSession = nil
            #if canImport(CoreBluetooth)
            self.startBLE()
            #endif
        }
    }
}
#endif

// MARK: - BLE フォールバック

#if canImport(CoreBluetooth)
import CoreBluetooth

private class BLEProximityManager: NSObject, CBPeripheralManagerDelegate, CBCentralManagerDelegate {
    private let peripheralManager: CBPeripheralManager
    private let centralManager: CBCentralManager
    private let serviceUUID: CBUUID
    weak var gate: ProximityGate?

    var onProximityChange: ((Bool) -> Void)?
    private var maxRSSI: Int = Int.min

    override init() {
        self.serviceUUID = CBUUID(string: "12345678-1234-5678-1234-567812345678")
        self.peripheralManager = CBPeripheralManager()
        self.centralManager = CBCentralManager()
        super.init()

        peripheralManager.delegate = self
        centralManager.delegate = self
    }

    func start() {
        // Advertise: 自分をサービスで公開
        let service = CBMutableService(type: serviceUUID, primary: true)
        peripheralManager.add(service)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])

        // Scan: 相手を探す
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func stop() {
        peripheralManager.stopAdvertising()
        centralManager.stopScan()
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        updateGateState(peripheral.state)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error == nil {
            // サービス追加成功
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateGateState(central.state)
    }

    private func updateGateState(_ state: CBManagerState) {
        let reason: String? = {
            switch state {
            case .unauthorized:
                return "Bluetooth が許可されていません"
            case .poweredOff:
                return "Bluetooth がオフです"
            case .poweredOn:
                return nil
            default:
                return nil
            }
        }()

        DispatchQueue.main.async { [weak self] in
            self?.gate?.unavailableReason = reason
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let currentRSSI = RSSI.intValue

        // RSSI > -40 dBm を近接とみなす（ponytail: RSSI しきい値は実機チューニング）
        let isNear = currentRSSI > -40
        maxRSSI = max(maxRSSI, currentRSSI)

        onProximityChange?(isNear)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // 接続成功（詳細ハンドルは不要）
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // 接続失敗（継続スキャン）
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // 切断（継続スキャン）
    }
}

#endif

#else

// tvOS/watchOS/macOS: スタブ実装
@Observable
final class ProximityGate: NSObject {
    private(set) var isNear = false
    var isSupported: Bool { false }
    var simulatorBypass = false

    func start(withPeerToken peerTokenData: Data) {}
    func stop() {}
    var localTokenData: Data? { nil }
}

#endif
