# DRU HomeKit App - Technical Implementation Reference

## Quick Start Code Snippets

### 1. ModbusTCP Client - Complete Implementation

```swift
import Foundation
import Network

// MARK: - ModbusTCP Client

actor ModbusTCPClient {
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private let slaveId: UInt8
    private var transactionId: UInt16 = 0
    
    enum ModbusError: Error {
        case connectionFailed(String)
        case timeout
        case invalidResponse
        case modbusException(code: UInt8)
        case notConnected
    }
    
    init(host: String, port: UInt16 = 502, slaveId: UInt8 = 2) {
        self.host = host
        self.port = port
        self.slaveId = slaveId
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        
        connection = NWConnection(to: endpoint, using: .tcp)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: ModbusError.connectionFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection?.start(queue: .global())
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    // MARK: - Read Operations
    
    /// Read Holding Registers (Function Code 0x03)
    func readHoldingRegisters(startAddress: UInt16, quantity: UInt16) async throws -> [UInt16] {
        guard let connection = connection else {
            throw ModbusError.notConnected
        }
        
        transactionId += 1
        
        // Build PDU
        var pdu = Data()
        pdu.append(0x03) // Function code
        pdu.append(contentsOf: startAddress.bigEndianBytes)
        pdu.append(contentsOf: quantity.bigEndianBytes)
        
        let request = buildMBAPHeader(pduLength: pdu.count) + pdu
        let response = try await sendAndReceive(connection: connection, data: request)
        
        return parseReadResponse(response, expectedRegisters: Int(quantity))
    }
    
    // MARK: - Write Operations
    
    /// Write Single Register (Function Code 0x06)
    func writeSingleRegister(address: UInt16, value: UInt16) async throws {
        guard let connection = connection else {
            throw ModbusError.notConnected
        }
        
        transactionId += 1
        
        var pdu = Data()
        pdu.append(0x06) // Function code
        pdu.append(contentsOf: address.bigEndianBytes)
        pdu.append(contentsOf: value.bigEndianBytes)
        
        let request = buildMBAPHeader(pduLength: pdu.count) + pdu
        _ = try await sendAndReceive(connection: connection, data: request)
    }
    
    /// Write Multiple Registers (Function Code 0x10)
    func writeMultipleRegisters(startAddress: UInt16, values: [UInt16]) async throws {
        guard let connection = connection else {
            throw ModbusError.notConnected
        }
        
        transactionId += 1
        
        var pdu = Data()
        pdu.append(0x10) // Function code
        pdu.append(contentsOf: startAddress.bigEndianBytes)
        pdu.append(contentsOf: UInt16(values.count).bigEndianBytes)
        pdu.append(UInt8(values.count * 2)) // Byte count
        
        for value in values {
            pdu.append(contentsOf: value.bigEndianBytes)
        }
        
        let request = buildMBAPHeader(pduLength: pdu.count) + pdu
        _ = try await sendAndReceive(connection: connection, data: request)
    }
    
    // MARK: - Private Helpers
    
    private func buildMBAPHeader(pduLength: Int) -> Data {
        var header = Data()
        header.append(contentsOf: transactionId.bigEndianBytes)  // Transaction ID
        header.append(contentsOf: UInt16(0).bigEndianBytes)      // Protocol ID (0 = Modbus)
        header.append(contentsOf: UInt16(pduLength + 1).bigEndianBytes) // Length (PDU + Unit ID)
        header.append(slaveId)                                    // Unit ID
        return header
    }
    
    private func sendAndReceive(connection: NWConnection, data: Data) async throws -> Data {
        // Send
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        // Receive with timeout
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { content, _, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let data = content {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: ModbusError.invalidResponse)
                        }
                    }
                }
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                throw ModbusError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func parseReadResponse(_ data: Data, expectedRegisters: Int) -> [UInt16] {
        // Skip MBAP header (7 bytes) + function code (1 byte) + byte count (1 byte)
        let dataStart = 9
        var registers: [UInt16] = []
        
        for i in 0..<expectedRegisters {
            let offset = dataStart + (i * 2)
            let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            registers.append(value)
        }
        
        return registers
    }
}

// MARK: - UInt16 Extension

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}
```

### 2. DRU Fireplace Manager

```swift
import Foundation

// MARK: - DRU Register Definitions

enum DRURegister: UInt16 {
    case action = 200           // 40200 → offset 200
    case status = 203           // 40203
    case errorCode = 204        // 40204
    case flameHeight = 205      // 40205
    case rssi = 206             // 40206
    case temperature = 207      // 40207
    case thermostatSetpoint = 250  // 40250
    case flameHeightTarget = 251   // 40251
    case waveInterval = 252        // 40252
    case wavePatternStart = 421    // 40421
}

struct DRUAction: OptionSet {
    let rawValue: UInt16
    
    static let mainBurner = DRUAction(rawValue: 1 << 0)
    static let secondBurner = DRUAction(rawValue: 1 << 1)
    static let pilotFlame = DRUAction(rawValue: 1 << 2)
    static let waveActive = DRUAction(rawValue: 1 << 3)
    static let temperatureControl = DRUAction(rawValue: 1 << 4)
    static let light = DRUAction(rawValue: 1 << 5)
    static let boostFan = DRUAction(rawValue: 1 << 6)
    static let fireplaceOff = DRUAction(rawValue: 1 << 7)
    static let fireplaceReset = DRUAction(rawValue: 1 << 8)
}

struct FireplaceStatus {
    let isOn: Bool
    let temperature: Double
    let flameHeight: Int
    let hasError: Bool
    let errorCode: String?
    let rssi: Int
    
    // Parse from status register (40203)
    static func from(statusBits: UInt16, errorCode: UInt16, temp: UInt16, flame: UInt16, rssi: UInt16) -> FireplaceStatus {
        FireplaceStatus(
            isOn: (statusBits & 0x01) != 0,
            temperature: Double(temp) / 10.0, // Temperature often scaled by 10
            flameHeight: Int(flame),
            hasError: errorCode != 0,
            errorCode: errorCode != 0 ? "F\(String(format: "%02d", errorCode))" : nil,
            rssi: Int(rssi)
        )
    }
}

// MARK: - Fireplace Manager

@MainActor
class DRUFireplaceManager: ObservableObject {
    private let modbusClient: ModbusTCPClient
    private var pollTimer: Timer?
    
    @Published var status: FireplaceStatus?
    @Published var isConnected = false
    @Published var lastError: Error?
    
    // Rate limiting
    private var lastCommandTime: Date = .distantPast
    private let minimumCommandInterval: TimeInterval = 10 // 10 seconds
    
    init(bridgeIP: String) {
        self.modbusClient = ModbusTCPClient(host: bridgeIP, slaveId: 2)
    }
    
    func connect() async {
        do {
            try await modbusClient.connect()
            isConnected = true
            startPolling()
        } catch {
            lastError = error
            isConnected = false
        }
    }
    
    func disconnect() async {
        stopPolling()
        await modbusClient.disconnect()
        isConnected = false
    }
    
    // MARK: - Commands
    
    func turnOn() async throws {
        try await throttledCommand {
            try await self.modbusClient.writeSingleRegister(
                address: DRURegister.action.rawValue,
                value: DRUAction.mainBurner.rawValue
            )
        }
    }
    
    func turnOff() async throws {
        try await throttledCommand {
            try await self.modbusClient.writeSingleRegister(
                address: DRURegister.action.rawValue,
                value: DRUAction.fireplaceOff.rawValue
            )
        }
    }
    
    func setFlameHeight(_ height: Int) async throws {
        let clampedHeight = max(0, min(15, height))
        try await throttledCommand {
            try await self.modbusClient.writeSingleRegister(
                address: DRURegister.flameHeightTarget.rawValue,
                value: UInt16(clampedHeight)
            )
        }
    }
    
    func setThermostat(_ temperature: Double) async throws {
        let clampedTemp = max(5, min(35, temperature))
        try await throttledCommand {
            try await self.modbusClient.writeSingleRegister(
                address: DRURegister.thermostatSetpoint.rawValue,
                value: UInt16(clampedTemp * 10) // Scale by 10
            )
        }
    }
    
    func toggleWaveMode(_ enabled: Bool) async throws {
        try await throttledCommand {
            var action = DRUAction.mainBurner
            if enabled {
                action.insert(.waveActive)
            }
            try await self.modbusClient.writeSingleRegister(
                address: DRURegister.action.rawValue,
                value: action.rawValue
            )
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { await self?.pollStatus() }
        }
        Task { await pollStatus() }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func pollStatus() async {
        do {
            // Read registers 40203-40207 (5 registers)
            let registers = try await modbusClient.readHoldingRegisters(
                startAddress: DRURegister.status.rawValue,
                quantity: 5
            )
            
            status = FireplaceStatus.from(
                statusBits: registers[0],
                errorCode: registers[1],
                temp: registers[4],
                flame: registers[2],
                rssi: registers[3]
            )
        } catch {
            lastError = error
        }
    }
    
    // MARK: - Rate Limiting
    
    private func throttledCommand(_ command: @escaping () async throws -> Void) async throws {
        let now = Date()
        let timeSinceLastCommand = now.timeIntervalSince(lastCommandTime)
        
        if timeSinceLastCommand < minimumCommandInterval {
            let waitTime = minimumCommandInterval - timeSinceLastCommand
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        
        try await command()
        lastCommandTime = Date()
    }
}
```

### 3. HomeKit Integration with HAP Library

```swift
import HAP

// MARK: - Custom DRU Fireplace Accessory

class DRUFireplaceAccessory {
    let accessory: Accessory
    let thermostat: Service.Thermostat
    let temperatureSensor: Service.TemperatureSensor
    
    private let manager: DRUFireplaceManager
    
    init(manager: DRUFireplaceManager, name: String = "DRU Fireplace") {
        self.manager = manager
        
        // Create accessory info
        let info = Service.Info(
            name: name,
            serialNumber: "DRU-100XT-001",
            manufacturer: "DRU",
            model: "100 XT Metrotunnel"
        )
        
        // Create thermostat service
        thermostat = Service.Thermostat(characteristics: [
            .currentHeatingCoolingState(.off),
            .targetHeatingCoolingState(.off),
            .currentTemperature(20.0),
            .targetTemperature(21.0),
            .temperatureDisplayUnits(.celsius)
        ])
        
        // Create temperature sensor
        temperatureSensor = Service.TemperatureSensor(characteristics: [
            .currentTemperature(20.0)
        ])
        
        // Create the accessory
        accessory = Accessory(
            info: info,
            type: .thermostat,
            services: [thermostat, temperatureSensor]
        )
        
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        // Handle target state changes from HomeKit
        thermostat.targetHeatingCoolingState.onValueChange.append { [weak self] newValue in
            guard let self = self, let value = newValue else { return }
            
            Task {
                do {
                    switch value {
                    case .heat:
                        try await self.manager.turnOn()
                    case .off:
                        try await self.manager.turnOff()
                    default:
                        break
                    }
                } catch {
                    print("HomeKit command failed: \(error)")
                }
            }
        }
        
        // Handle target temperature changes
        thermostat.targetTemperature.onValueChange.append { [weak self] newValue in
            guard let self = self, let temp = newValue else { return }
            
            Task {
                do {
                    try await self.manager.setThermostat(Double(temp))
                } catch {
                    print("Temperature change failed: \(error)")
                }
            }
        }
    }
    
    func updateFromStatus(_ status: FireplaceStatus) {
        thermostat.currentTemperature.value = Float(status.temperature)
        temperatureSensor.currentTemperature.value = Float(status.temperature)
        thermostat.currentHeatingCoolingState.value = status.isOn ? .heat : .off
    }
}

// MARK: - HAP Server

class DRUHomeKitServer {
    private let device: Device
    private let fireplaceAccessory: DRUFireplaceAccessory
    private var server: Server?
    
    init(manager: DRUFireplaceManager) {
        fireplaceAccessory = DRUFireplaceAccessory(manager: manager)
        
        device = Device(
            bridgeInfo: Service.Info(
                name: "DRU Bridge",
                serialNumber: "DRUBRIDGE-001"
            ),
            setupCode: .random,
            storage: FileStorage(filename: "dru-homekit"),
            accessories: [fireplaceAccessory.accessory]
        )
    }
    
    func start() throws {
        server = try Server(device: device, listenPort: 0)
        server?.start()
        
        print("HomeKit server started")
        print("Setup code: \(device.setupCode)")
        print("Setup URI: \(device.setupURI)")
    }
    
    func stop() {
        server?.stop()
    }
    
    func updateStatus(_ status: FireplaceStatus) {
        fireplaceAccessory.updateFromStatus(status)
    }
}
```

### 4. SwiftUI Interface

```swift
import SwiftUI

struct FireplaceControlView: View {
    @StateObject private var manager: DRUFireplaceManager
    @State private var targetTemperature: Double = 21.0
    @State private var flameHeight: Double = 8.0
    
    init(bridgeIP: String) {
        _manager = StateObject(wrappedValue: DRUFireplaceManager(bridgeIP: bridgeIP))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status Card
                statusCard
                
                // Main Control
                mainControlButton
                
                // Temperature Control
                temperatureControl
                
                // Flame Height
                flameHeightControl
                
                Spacer()
            }
            .padding()
            .navigationTitle("DRU Haard")
            .task {
                await manager.connect()
            }
        }
    }
    
    private var statusCard: some View {
        VStack {
            if let status = manager.status {
                HStack {
                    Image(systemName: status.isOn ? "flame.fill" : "flame")
                        .font(.system(size: 40))
                        .foregroundStyle(status.isOn ? .orange : .gray)
                    
                    VStack(alignment: .leading) {
                        Text(status.isOn ? "Aan" : "Uit")
                            .font(.headline)
                        Text("\(status.temperature, specifier: "%.1f")°C")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if status.hasError {
                        Label(status.errorCode ?? "Error", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView("Verbinden...")
            }
        }
    }
    
    private var mainControlButton: some View {
        Button {
            Task {
                if manager.status?.isOn == true {
                    try? await manager.turnOff()
                } else {
                    try? await manager.turnOn()
                }
            }
        } label: {
            Circle()
                .fill(manager.status?.isOn == true ? Color.orange : Color.gray.opacity(0.3))
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "power")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(manager.status?.isOn == true ? .white : .gray)
                }
        }
    }
    
    private var temperatureControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Doeltemperatuur")
                .font(.headline)
            
            HStack {
                Slider(value: $targetTemperature, in: 15...30, step: 0.5)
                Text("\(targetTemperature, specifier: "%.1f")°C")
                    .frame(width: 60)
            }
            .onChange(of: targetTemperature) { _, newValue in
                Task {
                    try? await manager.setThermostat(newValue)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var flameHeightControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vlam Hoogte")
                .font(.headline)
            
            HStack {
                Slider(value: $flameHeight, in: 0...15, step: 1)
                Text("\(Int(flameHeight))")
                    .frame(width: 40)
            }
            .onChange(of: flameHeight) { _, newValue in
                Task {
                    try? await manager.setFlameHeight(Int(newValue))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

### 5. Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DRUHomeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DRUModbus", targets: ["DRUModbus"]),
        .library(name: "DRUHomeKit", targets: ["DRUHomeKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Bouke/HAP.git", from: "0.7.0"),
        // Alternative Modbus library if needed:
        // .package(url: "https://github.com/DimaRU/SwiftyModbus.git", from: "2.2.1"),
    ],
    targets: [
        .target(
            name: "DRUModbus",
            dependencies: []
        ),
        .target(
            name: "DRUHomeKit",
            dependencies: [
                "DRUModbus",
                .product(name: "HAP", package: "HAP"),
            ]
        ),
        .testTarget(
            name: "DRUModbusTests",
            dependencies: ["DRUModbus"]
        ),
    ]
)
```

---

## Testing Commands

### Verify Bridge Connectivity

```bash
# Check if port 502 is open
nc -zv <BRIDGE_IP> 502

# Install modbus CLI tool (macOS)
brew install libmodbus

# Read temperature register (40207)
modpoll -m tcp -a 2 -r 207 -c 1 <BRIDGE_IP>

# Read status registers (40203-40207)
modpoll -m tcp -a 2 -r 203 -c 5 <BRIDGE_IP>
```

### Modbus Simulator for Development

```bash
# Install diagslave for testing without hardware
# https://www.modbusdriver.com/diagslave.html

# Run as server
diagslave -m tcp -p 502
```

---

## Important Notes

1. **Polling**: Minimaal 10 seconden tussen register reads
2. **Commands**: Minimaal 10 seconden tussen vlam hoogte wijzigingen
3. **Errors**: Moeten ALTIJD handmatig gereset worden via afstandsbediening
4. **Wave patterns**: Maximaal 1x per dag opgeslagen in non-volatile memory
5. **Connection**: Houd TCP connectie open voor betere response tijd

---

*Ready for Claude Code development*
