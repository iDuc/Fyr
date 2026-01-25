# DRU HomeKit iOS App - Product Requirements Document

## Executive Summary

Ontwikkel een native iOS app die DRU gashaarden integreert met Apple HomeKit, waardoor bediening via Siri en de Apple Home app mogelijk wordt. De app communiceert direct via ModbusTCP met de Honeywell BRDG-03EM01 bridge die DRU haarden aanstuurt.

---

## 1. Technische Architectuur

### 1.1 Systeemoverzicht

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│  Honeywell       │────▶│  DRU Fireplace  │
│   (HomeKit +    │ TCP │  BRDG-03EM01     │ RF  │  (DFGT Control) │
│   ModbusTCP)    │:502 │  Bridge          │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐
│  Apple HomeKit  │
│  (Siri, Home)   │
└─────────────────┘
```

### 1.2 Communicatie Protocol

**Protocol**: ModbusTCP  
**Port**: 502  
**Gateway Slave ID**: 207  
**Fireplace Slave ID**: 2 (auto-assigned)

---

## 2. DRU Modbus Register Specificatie

### 2.1 Action Register (WRITE) - Register 40200

| Bit | Functie | Beschrijving |
|-----|---------|--------------|
| 0 | Main Burner | 0=Uit, 1=Aan |
| 1 | Second Burner | 0=Uit, 1=Aan |
| 2 | Pilot Flame | 0=Uit, 1=Aan |
| 3 | Wave Active | 0=Uit, 1=Actief |
| 4 | Temperature Control | 0=Uit, 1=Actief |
| 5 | Light | 0=Uit, 1=Aan |
| 6 | Boost Fan | 0=Uit, 1=Aan |
| 7 | Fireplace Off | Trigger om uit te schakelen |
| 8 | Fireplace Reset | Trigger om te resetten |

### 2.2 Status Registers (READ)

| Register | Beschrijving | Type |
|----------|--------------|------|
| 40203 | Status Information (16-bit bitmap) | Read |
| 40204 | Error/Fault Code | Read |
| 40205 | Flame Height (0-15) | Read |
| 40206 | RSSI Signal Strength DFGT | Read |
| 40207 | Measured Temperature (°C) | Read |

### 2.3 Control Registers (READ/WRITE)

| Register | Beschrijving | Type | Range |
|----------|--------------|------|-------|
| 40250 | Thermostat Setpoint | R/W | 5-35°C |
| 40251 | Flame Height Target | R/W | 0-15 |
| 40252 | Wave Interval Time | R/W | 1-60 sec |
| 40421-40430 | Wave Pattern (10 registers) | R/W | 1-15 per nibble |

### 2.4 Error Codes

| Code | Beschrijving |
|------|--------------|
| F01 | Pilot flame failure |
| F02 | Main burner failure |
| F03 | Overheat protection |
| F04 | Communication error |
| F08 | General fault |

---

## 3. Functionele Requirements

### 3.1 Core Features

#### P0 - Must Have
- [ ] Aan/Uit bediening hoofdbrander
- [ ] Vlam hoogte regeling (0-100%)
- [ ] Temperatuur uitlezing
- [ ] Status weergave (aan/uit/fout)
- [ ] HomeKit integratie (basis switch)
- [ ] Siri commando's: "Zet de haard aan/uit"

#### P1 - Should Have
- [ ] Thermostaatbediening met target temperatuur
- [ ] Wave-modus activeren/deactiveren
- [ ] Tweede brander bediening
- [ ] Verlichting bediening
- [ ] Error notificaties
- [ ] HomeKit Thermostat service

#### P2 - Nice to Have
- [ ] Custom Wave patterns instellen
- [ ] Boost fan bediening
- [ ] Energieverbruik statistieken
- [ ] Scheduled automations
- [ ] Multi-fireplace support
- [ ] Widget voor Home Screen

### 3.2 HomeKit Services

```swift
// Te implementeren HomeKit service types:
- HMServiceTypeSwitch          // Main burner on/off
- HMServiceTypeThermostat      // Temperature control
- HMServiceTypeLightbulb       // Ambient lighting (if available)
- HMServiceTypeTemperatureSensor // Current temperature
```

---

## 4. Technische Implementatie

### 4.1 Aanbevolen Swift Libraries

#### ModbusTCP Communicatie
```swift
// Optie 1: SwiftyModbus (aanbevolen)
// URL: https://github.com/DimaRU/SwiftyModbus
// - Native Swift
// - iOS/macOS support
// - Async/await ready

// Optie 2: SwiftLibModbus
// URL: https://github.com/ktsakaguchi/SwiftLibModbus
// - Wrapper rond libmodbus
// - Bewezen stabiel

// Optie 3: Custom implementatie met Network.framework
import Network
// Direct TCP socket communicatie
```

#### HomeKit Accessory Protocol
```swift
// Bouke/HAP - Swift HAP implementatie
// URL: https://github.com/Bouke/HAP
// Features:
// - Complete HAP implementatie
// - QR code pairing (iOS 11+)
// - Custom services & characteristics
// - Persistent configuration

// Alternatief: Native HomeKit.framework
// (alleen voor client-side, niet voor accessory creation)
```

### 4.2 App Architectuur

```
DRUHomeKit/
├── App/
│   ├── DRUHomeKitApp.swift
│   └── ContentView.swift
├── Core/
│   ├── ModbusClient/
│   │   ├── ModbusTCPClient.swift
│   │   ├── DRURegisterMap.swift
│   │   └── ModbusProtocol.swift
│   ├── HomeKit/
│   │   ├── DRUAccessoryServer.swift
│   │   ├── FireplaceService.swift
│   │   └── ThermostatService.swift
│   └── Models/
│       ├── Fireplace.swift
│       ├── FireplaceStatus.swift
│       └── ErrorCode.swift
├── Features/
│   ├── Dashboard/
│   ├── Settings/
│   └── Diagnostics/
├── Services/
│   ├── FireplaceManager.swift
│   ├── NetworkDiscovery.swift
│   └── NotificationService.swift
└── Resources/
    └── Assets.xcassets
```

### 4.3 ModbusTCP Client Implementatie

```swift
import Network

class ModbusTCPClient {
    private var connection: NWConnection?
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port = 502
    private let slaveId: UInt8
    
    init(host: String, slaveId: UInt8 = 2) {
        self.host = NWEndpoint.Host(host)
        self.slaveId = slaveId
    }
    
    // Read Holding Registers (Function Code 0x03)
    func readHoldingRegisters(startAddress: UInt16, quantity: UInt16) async throws -> [UInt16] {
        let request = buildReadRequest(
            functionCode: 0x03,
            startAddress: startAddress,
            quantity: quantity
        )
        return try await sendRequest(request)
    }
    
    // Write Single Register (Function Code 0x06)
    func writeSingleRegister(address: UInt16, value: UInt16) async throws {
        let request = buildWriteRequest(
            functionCode: 0x06,
            address: address,
            value: value
        )
        try await sendRequest(request)
    }
    
    // Write Multiple Registers (Function Code 0x10)
    func writeMultipleRegisters(startAddress: UInt16, values: [UInt16]) async throws {
        // Implementation for wave patterns etc.
    }
    
    private func buildModbusTCPFrame(pdu: Data) -> Data {
        var frame = Data()
        // Transaction ID (2 bytes)
        frame.append(contentsOf: [0x00, 0x01])
        // Protocol ID (2 bytes) - always 0 for Modbus
        frame.append(contentsOf: [0x00, 0x00])
        // Length (2 bytes)
        let length = UInt16(pdu.count + 1)
        frame.append(contentsOf: length.bigEndianBytes)
        // Unit ID
        frame.append(slaveId)
        // PDU
        frame.append(pdu)
        return frame
    }
}
```

### 4.4 DRU Register Map

```swift
enum DRURegister: UInt16 {
    // Action Register (Write)
    case action = 40200
    
    // Status Registers (Read)
    case status = 40203
    case errorCode = 40204
    case flameHeight = 40205
    case rssi = 40206
    case temperature = 40207
    
    // Control Registers (Read/Write)
    case thermostatSetpoint = 40250
    case flameHeightTarget = 40251
    case waveInterval = 40252
    
    // Wave Pattern (10 registers)
    case wavePatternStart = 40421
}

struct DRUActionBits: OptionSet {
    let rawValue: UInt16
    
    static let mainBurner = DRUActionBits(rawValue: 1 << 0)
    static let secondBurner = DRUActionBits(rawValue: 1 << 1)
    static let pilotFlame = DRUActionBits(rawValue: 1 << 2)
    static let waveActive = DRUActionBits(rawValue: 1 << 3)
    static let temperatureControl = DRUActionBits(rawValue: 1 << 4)
    static let light = DRUActionBits(rawValue: 1 << 5)
    static let boostFan = DRUActionBits(rawValue: 1 << 6)
    static let fireplaceOff = DRUActionBits(rawValue: 1 << 7)
    static let fireplaceReset = DRUActionBits(rawValue: 1 << 8)
}
```

### 4.5 HomeKit Accessory Server

```swift
import HAP

class DRUAccessoryServer {
    let device: Device
    let fireplace: Accessory.Thermostat
    
    init(fireplaceInfo: Service.Info) {
        // Create thermostat accessory with temperature control
        fireplace = Accessory.Thermostat(info: fireplaceInfo)
        
        // Configure characteristics
        fireplace.thermostat.currentHeatingCoolingState.value = .off
        fireplace.thermostat.targetHeatingCoolingState.value = .off
        fireplace.thermostat.currentTemperature.value = 20.0
        fireplace.thermostat.targetTemperature.value = 21.0
        
        // Create device (bridge)
        device = Device(
            bridgeInfo: Service.Info(name: "DRU Bridge", serialNumber: "DRU-001"),
            setupCode: .random,
            storage: FileStorage(filename: "dru-config"),
            accessories: [fireplace]
        )
    }
    
    func updateFromModbus(status: FireplaceStatus) {
        fireplace.thermostat.currentTemperature.value = Float(status.temperature)
        fireplace.thermostat.currentHeatingCoolingState.value = status.isOn ? .heat : .off
    }
    
    func handleTargetStateChange(_ newState: Enums.TargetHeatingCoolingState) async {
        switch newState {
        case .heat:
            try await modbusClient.turnOn()
        case .off:
            try await modbusClient.turnOff()
        default:
            break
        }
    }
}
```

---

## 5. Belangrijke Restricties & Veiligheid

### 5.1 DRU Apparaat Limieten

⚠️ **KRITIEKE BEPERKINGEN**:

1. **Polling interval**: Minimaal 10 seconden tussen requests
2. **Vlam hoogte wijziging**: Maximaal 1x per 10 seconden (regelgeving)
3. **Algemene commando's**: Maximaal 1x per 30 seconden aanbevolen
4. **Fault handling**: Fouten MOETEN handmatig gereset worden via afstandsbediening (∧∨ knoppen)

### 5.2 Error Handling

```swift
enum DRUError: Error {
    case connectionFailed
    case communicationTimeout
    case faultDetected(code: String)
    case operationThrottled
    case invalidResponse
}

// Bij foutdetectie: toon instructies voor handmatige reset
func handleFault(code: String) {
    let message = """
    Fout gedetecteerd: \(code)
    
    Reset de haard handmatig:
    Druk gelijktijdig op ∧ en ∨ op de afstandsbediening
    """
    showAlert(message)
}
```

---

## 6. UI/UX Vereisten

### 6.1 Hoofdscherm

- Grote aan/uit knop (prominent)
- Huidige temperatuur weergave
- Vlam hoogte slider
- Status indicator (aan/uit/fout)
- Snelle toegang tot HomeKit setup

### 6.2 HomeKit Integratie

- QR code voor snelle pairing
- Setup PIN weergave
- Status in Control Center
- Siri Shortcuts suggesties

### 6.3 Design Principes

- Native iOS design language (SwiftUI)
- Dark mode support (past bij haard ambiance)
- Haptic feedback bij acties
- Accessibility ondersteuning

---

## 7. Netwerk Discovery

### 7.1 Bridge Detectie

```swift
import Network

class DRUBridgeDiscovery {
    // De Honeywell bridge is te vinden via:
    // 1. mDNS/Bonjour scanning
    // 2. Network scanning op port 502
    // 3. Handmatige IP invoer
    
    func discoverBridges() async -> [DiscoveredBridge] {
        // Scan lokaal netwerk voor Modbus devices
        let scanner = NWBrowser(for: .tcp, using: .tcp)
        // Check port 502 responses
    }
}
```

---

## 8. Bestaande Referentie Implementaties

### 8.1 Te Bestuderen Projecten

| Project | Platform | URL |
|---------|----------|-----|
| Homey DRU App | JavaScript | github.com/stemmr/com.athom.dru |
| Home Assistant DRU | Python | github.com/lion7/hass-dru |
| OpenHAB NodeRed | Node.js | github.com/snoekieboe/DRU-Modbus-Openhab2-NodeRed |
| Domoticz DRU | Node-RED | forum.domoticz.com/viewtopic.php?t=29060 |

### 8.2 Nuttige Documentatie

- DRU Modbus Protocol: "20190607 - Dru - Info_07_EN_26319_Remote_Access_DFGT-2.pdf"
- HAP Specification: developer.apple.com/homekit/specification/
- Modbus TCP Spec: modbus.org/specs/Modbus_Application_Protocol_V1_1b.pdf

---

## 9. Development Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Project setup met Swift Package Manager
- [ ] ModbusTCP client implementatie
- [ ] Basic connectivity test met bridge
- [ ] Read status registers

### Phase 2: Core Control (Week 3-4)
- [ ] Aan/uit functionaliteit
- [ ] Vlam hoogte regeling
- [ ] Temperatuur uitlezing
- [ ] Error handling

### Phase 3: HomeKit Integration (Week 5-6)
- [ ] HAP server setup
- [ ] Switch service
- [ ] Thermostat service
- [ ] Pairing flow

### Phase 4: Polish (Week 7-8)
- [ ] UI refinement
- [ ] Widget development
- [ ] Testing & debugging
- [ ] Documentation

---

## 10. Test Setup

### 10.1 Benodigdheden

1. DRU haard met Honeywell BRDG-03EM01 bridge
2. iOS device (iPhone/iPad) op zelfde netwerk
3. Mac voor development
4. Optioneel: Modbus TCP simulator voor initial testing

### 10.2 Test Commands

```bash
# Test bridge connectivity (vanaf Mac terminal)
nc -zv <BRIDGE_IP> 502

# Modbus register read test (met modbus CLI tool)
modbus -m tcp -a 2 -t 4 -r 40207 <BRIDGE_IP>
```

---

## 11. Appendix: Modbus Protocol Quick Reference

### Request Frame Format (ModbusTCP)

```
| Transaction ID | Protocol ID | Length | Unit ID | Function | Data    |
| 2 bytes        | 2 bytes     | 2 bytes| 1 byte  | 1 byte   | n bytes |
```

### Function Codes

| Code | Name | Description |
|------|------|-------------|
| 0x03 | Read Holding Registers | Lees register waarden |
| 0x06 | Write Single Register | Schrijf één register |
| 0x10 | Write Multiple Registers | Schrijf meerdere registers |

---

*Document versie: 1.0*  
*Gemaakt voor: Claude Code development*  
*Target device: DRU 100 XT Metrotunnel met Honeywell BRDG-03EM01*
