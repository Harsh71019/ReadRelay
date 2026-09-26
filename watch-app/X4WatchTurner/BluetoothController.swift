import CoreBluetooth
import Foundation

final class BluetoothController: NSObject, ObservableObject {
    enum ReaderFormat: UInt8, Equatable {
        case none = 0
        case epub = 1
        case text = 2
        case xtc = 3

        var label: String {
            switch self {
            case .none: return "No book"
            case .epub: return "EPUB"
            case .text: return "TXT"
            case .xtc: return "XTC"
            }
        }
    }

    struct ReaderSnapshot: Equatable {
        var format: ReaderFormat = .none
        var title = ""
        var currentPage: UInt32 = 0
        var totalPages: UInt32 = 0
        var progressPercent = 0
        var batteryPercent = 0
        var titleRevision: UInt16 = 0

        var hasBook: Bool { format != .none }
    }

    enum ConnectionState: Equatable {
        case bluetoothUnavailable
        case scanning
        case connecting
        case connected
        case disconnected

        var label: String {
            switch self {
            case .bluetoothUnavailable: return "Bluetooth unavailable"
            case .scanning: return "Finding X4…"
            case .connecting: return "Connecting…"
            case .connected: return "X4 connected"
            case .disconnected: return "X4 not found"
            }
        }
    }

    enum PageCommand: UInt8 {
        case next = 0x01
        case previous = 0x02
    }

    static let serviceUUID = CBUUID(string: "F8A10001-7B4A-4C8B-9C61-4B5D6A731001")
    static let commandUUID = CBUUID(string: "F8A10002-7B4A-4C8B-9C61-4B5D6A731001")
    static let readerStateUUID = CBUUID(string: "F8A10003-7B4A-4C8B-9C61-4B5D6A731001")
    static let bookTitleUUID = CBUUID(string: "F8A10004-7B4A-4C8B-9C61-4B5D6A731001")

    @Published private(set) var state: ConnectionState = .bluetoothUnavailable
    @Published private(set) var readerSnapshot = ReaderSnapshot()
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var forwardTurns = 0
    @Published private(set) var backwardTurns = 0

    private var central: CBCentralManager!
    private var x4: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var readerStateCharacteristic: CBCharacteristic?
    private var bookTitleCharacteristic: CBCharacteristic?
    private var activeTitleRevision: UInt16?

#if DEBUG
    private var isConnectedPreview = false
#endif

    override init() {
        super.init()

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--connected-preview") {
            isConnectedPreview = true
            state = .connected
            readerSnapshot = ReaderSnapshot(
                format: .epub,
                title: "The Left Hand of Darkness",
                currentPage: 18,
                totalPages: 31,
                progressPercent: 42,
                batteryPercent: 78,
                titleRevision: 1
            )
            sessionStartedAt = Date().addingTimeInterval(-12 * 60 - 34)
            forwardTurns = 18
            backwardTurns = 2
            return
        }
#endif

        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isReady: Bool {
#if DEBUG
        if isConnectedPreview { return true }
#endif
        return state == .connected && x4 != nil && commandCharacteristic != nil
    }

    func reconnect() {
#if DEBUG
        if isConnectedPreview { return }
#endif
        guard central.state == .poweredOn else { return }
        x4 = nil
        commandCharacteristic = nil
        readerStateCharacteristic = nil
        bookTitleCharacteristic = nil
        startScanning()
    }

    @discardableResult
    func send(_ command: PageCommand) -> Bool {
#if DEBUG
        if isConnectedPreview { return true }
#endif
        guard
            let x4,
            let commandCharacteristic,
            x4.state == .connected
        else {
            reconnect()
            return false
        }

        let writeType: CBCharacteristicWriteType =
            commandCharacteristic.properties.contains(.writeWithoutResponse)
                ? .withoutResponse
                : .withResponse
        x4.writeValue(Data([command.rawValue]), for: commandCharacteristic, type: writeType)
        switch command {
        case .next: forwardTurns += 1
        case .previous: backwardTurns += 1
        }
        return true
    }

    func resetSession() {
        sessionStartedAt = Date()
        forwardTurns = 0
        backwardTurns = 0
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        central.stopScan()
        state = .scanning
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

extension BluetoothController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff, .unauthorized, .unsupported:
            state = .bluetoothUnavailable
        case .resetting, .unknown:
            state = .disconnected
        @unknown default:
            state = .disconnected
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        central.stopScan()
        x4 = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connecting
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        x4 = nil
        commandCharacteristic = nil
        readerStateCharacteristic = nil
        bookTitleCharacteristic = nil
        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        x4 = nil
        commandCharacteristic = nil
        readerStateCharacteristic = nil
        bookTitleCharacteristic = nil
        state = .disconnected
        startScanning()
    }
}

extension BluetoothController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard let service = services.first(where: { $0.uuid == Self.serviceUUID }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics(
            [Self.commandUUID, Self.readerStateUUID, Self.bookTitleUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard let command = characteristics.first(where: { $0.uuid == Self.commandUUID }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        commandCharacteristic = command
        readerStateCharacteristic = characteristics.first(where: { $0.uuid == Self.readerStateUUID })
        bookTitleCharacteristic = characteristics.first(where: { $0.uuid == Self.bookTitleUUID })

        if let readerStateCharacteristic {
            peripheral.readValue(for: readerStateCharacteristic)
            if readerStateCharacteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: readerStateCharacteristic)
            }
        }
        if let bookTitleCharacteristic {
            peripheral.readValue(for: bookTitleCharacteristic)
        }

        if sessionStartedAt == nil {
            resetSession()
        }
        state = .connected
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case Self.readerStateUUID:
            updateReaderSnapshot(from: data, peripheral: peripheral)
        case Self.bookTitleUUID:
            let title = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var snapshot = readerSnapshot
            snapshot.title = title
            readerSnapshot = snapshot
        default:
            break
        }
    }

    private func updateReaderSnapshot(from data: Data, peripheral: CBPeripheral) {
        guard data.count >= 16, data[0] == 1 else { return }

        let revision = UInt16(data[14]) | (UInt16(data[15]) << 8)
        let format = ReaderFormat(rawValue: data[1]) ?? .none
        let titleChanged = activeTitleRevision != revision

        if format != .none, titleChanged {
            activeTitleRevision = revision
            resetSession()
            if let bookTitleCharacteristic {
                peripheral.readValue(for: bookTitleCharacteristic)
            }
        }

        readerSnapshot = ReaderSnapshot(
            format: format,
            title: titleChanged ? "" : readerSnapshot.title,
            currentPage: uint32(from: data, at: 6),
            totalPages: uint32(from: data, at: 10),
            progressPercent: min(Int(data[3]), 100),
            batteryPercent: min(Int(data[4]), 100),
            titleRevision: revision
        )
    }

    private func uint32(from data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
