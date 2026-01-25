# DRU Modbus Debug Notes

## Hardware Configuration

| Component | Details |
|-----------|---------|
| Fireplace | DRU Metro 100XT-41 RCH (2017) |
| Bridge | Honeywell BRDG-03EM01 |
| Firmware | Version 10 |
| IP Address | 10.0.1.62 |
| MAC Address | 58:f3:87:04:1f:70 |
| Modbus Port | 502 |
| Link Status | ONLINE |
| WiFi Network | SloerieNet |
| Remote Type | Wall-mounted controller (second option in app) |

## Protocol Details

- **Bridge Slave ID**: 207 (gateway itself)
- **Fireplace Slave ID**: 2 (use this for commands)
- **Function Code**: 0x03 (Read Holding Registers), 0x06 (Write Single Register)
- **Register Addressing**: ⚠️ **NON-STANDARD** - Use RAW register numbers (40200), NOT protocol addresses (199)

### Key Registers

| Register | Address to Use | Function | Values |
|----------|----------------|----------|--------|
| 40100 | **40100** | Last seen | Seconds since last communication |
| 40101 | **40101** | **Initiate Binding** | Write to enable Modbus access? (needs testing) |
| 40200 | **40200** | Action command | 3=Off, 101=On, 102=Second burner, 105=Wave |
| 40201 | **40201** | Flame height | 0 (low) to 15 (high) |
| 40203 | **40203** | Status | Read current state (bitfield) |
| 40204 | **40204** | Error codes | Fault codes (no gas, no spark, etc.) |
| 40205 | **40205** | Gateway RSSI | Signal strength gateway side (×-0.5 for dBm) |
| 40206 | **40206** | Device RSSI | Signal strength fireplace side (×-0.5 for dBm) |
| 40207 | **40207** | Room temp | Temperature sensor reading (÷10 for °C) |
| 40220 | **40220** | Wave interval | Interval time in seconds |
| 40250 | **40250** | Thermostat | Target temp (thermostat mode) |
| 40421 | **40421** | Wave pattern | Scene configuration (write multiple) |

### Action Command Values (Register 40200)
**Confirmed from Homey app and Node-RED implementations:**

| Value | Command |
|-------|---------|
| 3 | Main burner OFF |
| 4 | Second burner OFF |
| 7 | **Wave/Eco mode OFF** |
| 100 | Pilot flame |
| 101 | Main burner ON (ignite) |
| 102 | Second burner ON |
| 105 | **Wave/Eco mode ON** |

**Important:** To turn OFF eco mode, send value 7 (not 101). Sending 101 turns on the main burner but doesn't disable wave mode.

### Important Protocol Notes
- **Ignition requires double-send**: To ignite, you often need to send the command twice in quick succession (similar to physical remote safety)
- **Ignition time**: Takes 30-60 seconds for fireplace to fully ignite
- **Status changes**: Register 40203 changes from "Igniting" to "Running" during startup

## ⚠️ KEY FINDING: Network Capture Limitations

### Network Capture Results (2025-01-16)
We captured network traffic while using the DRU app to control the fireplace (change flame height).

**Result: No iPhone↔Bridge traffic visible in capture**

- iPhone IP: 10.0.1.182
- Bridge IP: 10.0.1.62
- Router: Amplifi HD (switched network)
- Captured only: mDNS broadcasts and AirPlay traffic

### Why We Can't See The Traffic
**On a switched network**, tcpdump on the Mac can only see:
1. Traffic TO/FROM the Mac itself
2. Broadcast/multicast traffic (mDNS, ARP)
3. Traffic mirrored by the switch (not configured)

**The DRU app probably IS using Modbus TCP** - we just can't capture it from the Mac because it's unicast traffic that goes directly iPhone→Switch→Bridge without passing through the Mac.

To capture this traffic we would need:
- Port mirroring on router (Amplifi may not support)
- Proxy/MITM setup on Mac
- Capture directly on iPhone (requires jailbreak)

### Bridge Hardware Confirmed
The Honeywell BRDG-03EM01 is an **Ethernet bridge** (NOT Bluetooth):
- Uses RF 868MHz to communicate with fireplace
- Uses Ethernet/TCP for network connectivity
- Advertises as `HWBRDG-DF._modbus._tcp.local` on port 502
- Community implementations (Home Assistant, openHAB, Homey) confirm Modbus TCP works

### User Tested
- Disabled Bluetooth permission for DRU app
- Disabled cellular data for DRU app
- App still controls fireplace successfully
- Confirms app uses WiFi/network (we just can't capture it)

---

## ~~Current Issue~~ RESOLVED (2025-01-16)

### Original Symptoms (NOW FIXED)
- TCP connection to 10.0.1.62:502 succeeds
- Bridge responds to Modbus requests
- ALL register reads return "Illegal Data Address" (exception 0x02)
- Tested addresses 0-500+ across slave IDs 1-2

### Root Cause
**We were using wrong register addresses.** The DRU bridge expects RAW register numbers (40200, 40203) not standard Modbus protocol addresses (199, 202). See "FIX APPLIED" section below for details.

### Current Status: ✅ WORKING
- Can read status, temperature, signal strength
- Can turn fireplace on/off
- Can set flame height
- Can toggle eco-wave mode

## Diagnostic Tests to Perform

### Test 1: Check RF Communication via Bridge Web Interface
Access http://10.0.1.62 and look for:
- RF signal strength indicators
- Paired device list
- Any error messages

### Test 2: Try Slave ID 207
The bridge hardware shows "192.168.0.207" which might indicate slave ID 207 is used for gateway communication.

```bash
# Try reading from gateway slave ID
modpoll -m tcp -a 207 -r 0 -c 10 10.0.1.62
```

### Test 3: Try Function Code 0x04 (Input Registers)
Some devices use input registers instead of holding registers for status.

### Test 4: Try Full Register Address (40200 instead of 199)
Some Modbus implementations don't subtract 40001.

### Test 5: Capture DRU App Traffic
Use Wireshark or mitmproxy to capture what the official DRU app actually sends.

## Community References

Working implementations:
- Home Assistant: https://github.com/lion7/hass-dru
- Homey: https://github.com/amstelzone/com.amstelzone.dru
- openHAB/Node-RED: https://github.com/snoekieboe/DRU-Modbus-Openhab2-NodeRed

Video tutorial:
- Honeywell Modbus Control: https://www.youtube.com/watch?v=LpGQEiKDa9w
  (Shows installation and basic operation of Honeywell module)

## Security Notes

The Honeywell bridge has no authentication on the local network. Ensure your IoT network is properly segmented from your main network.

## Things To Try

### 1. Write to Binding Register (40101)
Per GitHub issue, register 40101 is "Initiate Binding". Try:
```
Write value 1 to address 100 (register 40101)
```
This might enable external Modbus access.

### 2. ⭐ USE RAW REGISTER ADDRESSES (CRITICAL!)
**The working Homey app uses RAW Modbus register numbers WITHOUT conversion!**

From `amstelzone/com.amstelzone.dru` device.js:
```javascript
FIREPLACE_STATUS_REG = 40203  // Passed directly to readHoldingRegisters()
FIREPLACE_ACTION_REG = 40200  // Passed directly to writeSingleRegister()
```

**Our code does:**
- Register 40200 → address 199 (40200 - 40001) ❌ WRONG

**Working code does:**
- Register 40200 → address 40200 (no conversion) ✅ CORRECT

This is likely our bug! The DRU bridge expects raw register numbers (40200) not protocol addresses (199).

### 3. Query Gateway (Slave ID 207)
The bridge itself may have registers we can read:
- Slave ID 207 is the gateway
- Slave ID 2 is the fireplace

### 4. Try Function Code 0x04 (Read Input Registers)
Status might be on input registers instead of holding registers.

## Investigation History

### 2025-01-16
- Performed comprehensive scan of addresses 0-500+ across slave IDs 1-10
- All slave ID 1-2 requests return "Illegal Data Address" (0x02)
- All slave ID 3+ requests return "Gateway Path Unavailable" (0x0A)
- Network capture unable to see iPhone→Bridge traffic (switched network limitation)
- Confirmed DRU app uses WiFi (not Bluetooth/cellular) by disabling those permissions
- Found reference to register 40101 "Initiate Binding" - needs testing
- **Key insight**: Bridge responds to Modbus, so protocol is correct; issue is device-level

### Working Implementations Studied
- [Home Assistant Integration](https://github.com/lion7/hass-dru) - Uses pymodbus
- [Node-RED + OpenHAB](https://github.com/snoekieboe/DRU-Modbus-Openhab2-NodeRed) - Working JSON config
- [Homey App](https://github.com/amstelzone/com.amstelzone.dru)
- [Home Assistant Community Thread](https://community.home-assistant.io/t/dru-fireplace/324780)
- [OpenHAB Community Thread](https://community.openhab.org/t/dru-fireplace-control-using-oh2-nodered-modbus/53876)

---

## ✅ FIX APPLIED (2026-01-16)

### Root Cause Identified
The DRU Honeywell bridge expects **RAW Modbus register numbers** directly, NOT standard protocol addresses.

**Standard Modbus convention:**
```
Register 40200 → Protocol address 199 (40200 - 40001)
```

**What DRU bridge actually expects:**
```
Register 40200 → Address 40200 (no conversion!)
```

This was confirmed by analyzing the working [Homey app](https://github.com/amstelzone/com.amstelzone.dru) source code:
```javascript
// From device.js - Homey passes raw register numbers directly
FIREPLACE_STATUS_REG = 40203  // NOT 202
FIREPLACE_ACTION_REG = 40200  // NOT 199
```

### Files Updated

1. **`Fyr/Core/DRU/DRURegisterMap.swift`**
   - Changed all register enum values from converted addresses to RAW register numbers
   - Example: `case action = 199` → `case action = 40200`
   - Updated action commands: `mainBurnerOff = 3` (was incorrectly 1)

2. **`Fyr/Core/DRU/ModbusDiagnosticScanner.swift`**
   - Updated `statusRegisterBase` from 202 to 40203
   - Updated key addresses array to prioritize raw register numbers
   - Updated full range scan to test raw registers first

3. **`Fyr/Core/DRU/DRUFireplaceService.swift`**
   - Updated diagnostic test addresses to use raw register numbers (40200, 40203, etc.)

### Action Command Values (Confirmed from Homey app)
```swift
mainBurnerOn = 101    // Turn on main burner
mainBurnerOff = 3     // Turn off (NOT 1!)
secondBurnerOn = 102  // Turn on second burner
secondBurnerOff = 4   // Turn off second burner
waveMode = 105        // Eco-wave mode
```

### Key Lesson Learned
**Always analyze working third-party implementations** before trying to reverse-engineer a protocol. The Homey app source code provided the exact answer in minutes, while protocol guessing took hours.

---

## ✅ WORKING - Status Register Details (2026-01-16)

Communication is now working. Here are the observed status codes and register behaviors:

### Status Register 40203 - Bitfield Values

| Status Code | Hex | Binary | Meaning |
|-------------|-----|--------|---------|
| 15360 | 0x3C00 | 0011 1100 0000 0000 | Fireplace OFF |
| 47108 | 0xB804 | 1011 1000 0000 0100 | ON, normal mode |
| 47620 | 0xBA04 | 1011 1010 0000 0100 | ON, eco-wave mode |

**Eco Mode Detection:**
- Bit 9 (0x0200) indicates eco-wave mode is active
- Use `(statusCode & 0x0200) != 0` to detect eco mode
- Do NOT use exact value matching (values may vary slightly)

### Register 40201 - Flame Height (WRITE-ONLY)

⚠️ **Important:** Register 40201 is **write-only**. You cannot read the current flame height from the fireplace.

**Value Range:** 0-100 (percentage)
- 0 = Minimum flame
- 100 = Maximum flame
- Values are NOT discrete levels (0-15), but a continuous percentage

**Workaround:** Track the last set flame height value locally in the app.

### Register 40207 - Temperature

- Returns raw value that needs to be divided by 10
- Example: Value 210 = 21.0°C

### Register 40205/40206 - RSSI Signal Strength

- Multiply raw value by -0.5 to get dBm
- Example: Value 116 = -58 dBm

### Modbus Exception 0x05 (Acknowledge)

The bridge occasionally returns exception 0x05 (Acknowledge) during reads. This is a transient error - retry after a short delay.

### Eco-Wave Configuration (Advanced)

**Register 40420:** Wave interval time in seconds (e.g., 15)

**Register 40421:** Wave pattern (10 registers, write multiple)
- Comfort pattern: `[2569, 3340, 3854, 3342, 2572, 1801, 773, 514, 1027, 2054]`
- Eco pattern: `[1797, 2312, 2569, 2313, 1800, 1029, 259, 257, 513, 1283]`

**Note:** Wave patterns require Function Code 0x10 (Write Multiple Registers) to set all 10 values at once.

### Temperature/Thermostat Control

**Register 40250** is documented as thermostat setpoint, but:
- May not exist on all models (DRU Metro 100XT may not have it)
- Register 40207 (room temperature) is **READ-ONLY**
- Thermostat control via Modbus may not be available on all fireplaces

---

## App Implementation Notes

### Files with Key Logic

| File | Purpose |
|------|---------|
| `DRURegisterMap.swift` | Register addresses and action command values |
| `DRUFireplaceService.swift` | High-level service, status parsing, flame height tracking |
| `ModbusTCPClient.swift` | Low-level Modbus TCP protocol |
| `ModbusDiagnosticScanner.swift` | Diagnostic scanning for troubleshooting |

### Status Parsing (DRUFireplaceService.swift)

```swift
// Eco mode is indicated by bit 9 (0x0200) being set
let ecoModeActive = (statusCode & 0x0200) != 0

// OFF state
let isOn = statusCode != 15360 && statusCode != 0

// Flame height tracked locally (write-only register)
flameHeight: self.lastSetFlameHeight
```

### Handling Task Cancellation

When the user navigates away from the Dashboard, polling tasks are cancelled. The app must:
1. Catch `CancellationError` separately from other errors
2. NOT change connection state on cancellation
3. NOT retry on cancellation - propagate immediately

This prevents false "Reconnecting..." states when navigating between views.
