@preconcurrency import CoreBluetooth
import Foundation
import Observation

/// Connects to a Hunter SIMPLEconnect plug-in controller over Bluetooth and
/// sends it commands.
///
/// ```swift
/// let controller = FanController()
/// controller.connect()
/// // once controller.state == .ready:
/// try await controller.send(.light)
/// ```
///
/// The controller accepts one Bluetooth connection at a time, so the official
/// app must not be connected while this is in use.
///
/// Everything that happens is recorded in `log`, including the raw packets.
@MainActor
@Observable
public final class FanController: NSObject {
    public enum State: Equatable, Sendable {
        /// Bluetooth is off, unauthorized or unsupported.
        case unavailable
        case disconnected
        case scanning
        case connecting
        /// Connected and ready for commands.
        case ready
    }

    public enum ControllerError: Error, Equatable {
        case notReady
        case busy
        case disconnected
        case writeFailed(String)
    }

    public private(set) var state: State = .disconnected

    /// Protocol log, oldest first. Keeps the most recent `maxLogEntries`.
    public private(set) var log: [FanLogEntry] = []
    public var maxLogEntries = 500

    static let serviceUUID = CBUUID(string: "F4641530-2F5C-11E3-8B00-0002A5D5C51B")
    static let characteristicUUID = CBUUID(string: "F4641535-2F5C-11E3-8B00-0002A5D5C51B")

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var characteristic: CBCharacteristic?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var pendingWrite: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var lastSent: Data?
    @ObservationIgnored private var nextLogID = 0

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Scans for the controller and connects. Watch `state` for `.ready`.
    public func connect() {
        wantsConnection = true
        guard central.state == .poweredOn, state == .disconnected else { return }
        state = .scanning
        record(.info, "Scanning for controller")
        central.scanForPeripherals(withServices: [Self.serviceUUID])
    }

    public func disconnect() {
        wantsConnection = false
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
            record(.info, "Disconnecting")
        }
        reset(to: central.state == .poweredOn ? .disconnected : .unavailable)
    }

    /// Sends a command and waits for the controller to acknowledge it.
    public func send(_ command: FanCommand) async throws {
        guard state == .ready else {
            record(.error, "\(command.rawValue): not connected")
            throw ControllerError.notReady
        }
        try await write(FanPacket.packet(for: command), label: command.rawValue)
    }

    public func clearLog() {
        log.removeAll()
    }

    private func write(_ data: Data, label: String) async throws {
        guard let peripheral, let characteristic else { throw ControllerError.notReady }
        guard pendingWrite == nil else {
            record(.error, "\(label): busy with another write")
            throw ControllerError.busy
        }
        record(.sent, label, data)
        lastSent = data
        let start = Date()
        do {
            try await withCheckedThrowingContinuation { continuation in
                pendingWrite = continuation
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            record(.acknowledged, "\(label) acknowledged in \(milliseconds) ms")
        } catch {
            record(.error, "\(label) failed: \(error)")
            throw error
        }
    }

    private func record(_ kind: FanLogEntry.Kind, _ message: String, _ data: Data? = nil) {
        log.append(FanLogEntry(id: nextLogID, date: Date(), kind: kind, message: message, data: data))
        nextLogID += 1
        if log.count > maxLogEntries {
            log.removeFirst(log.count - maxLogEntries)
        }
    }

    private func finishWrite(_ result: Result<Void, Error>) {
        let continuation = pendingWrite
        pendingWrite = nil
        continuation?.resume(with: result)
    }

    private func reset(to newState: State) {
        finishWrite(.failure(ControllerError.disconnected))
        peripheral = nil
        characteristic = nil
        state = newState
    }

    /// Sends the hello packet the official app sends after connecting.
    private func handshake() {
        Task {
            do {
                try await write(FanPacket.helloPacket(), label: "hello")
                state = .ready
                record(.info, "Ready")
            } catch {
                disconnect()
            }
        }
    }
}

extension FanController: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                if state == .unavailable { state = .disconnected }
                if wantsConnection { connect() }
            } else {
                reset(to: .unavailable)
                record(.error, "Bluetooth unavailable (state \(central.state.rawValue))")
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        MainActor.assumeIsolated {
            guard state == .scanning else { return }
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            state = .connecting
            record(.info, "Found \(peripheral.name ?? "unnamed device") (RSSI \(RSSI) dBm), connecting")
            central.connect(peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            record(.info, "Connected, discovering services")
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            reset(to: .disconnected)
            record(.error, "Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            reset(to: .disconnected)
            if let error {
                record(.error, "Disconnected: \(error.localizedDescription)")
            } else {
                record(.info, "Disconnected")
            }
        }
    }
}

extension FanController: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                record(.error, "Controller service not found")
                disconnect()
                return
            }
            peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
                record(.error, "Command characteristic not found")
                disconnect()
                return
            }
            self.characteristic = characteristic
            // The controller acknowledges commands with indications; the
            // official app enables them before sending anything.
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            if let error {
                record(.error, "Enabling indications failed: \(error.localizedDescription)")
                disconnect()
            } else {
                record(.info, "Indications enabled, sending hello")
                handshake()
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            if let error {
                finishWrite(.failure(ControllerError.writeFailed(error.localizedDescription)))
            } else {
                finishWrite(.success(()))
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard let value = characteristic.value else { return }
            // The controller echoes each packet it accepts back as an indication.
            if value == lastSent {
                record(.received, "Echo (matches sent packet)", value)
            } else {
                record(.received, "Indication", value)
            }
        }
    }
}
