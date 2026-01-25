# DRU Fireplace Modbus Troubleshooting Guide

## Problem Summary

The Fyr app is receiving **"Modbus exception: Illegal Data Address (0x02)"** errors when attempting to read or write registers on the Honeywell BRDG-03EM01 bridge.

## Log Analysis

From the test logs:
```
Reading 1 registers from address 202 [txn:1]
Sending request: 00 01 00 00 00 06 02 03 00 CA 00 01
Received response (9 bytes): 00 01 00 00 00 03 02 83 02
```

Breaking down the request:
- Transaction ID: `00 01`
- Protocol ID: `00 00` (Modbus TCP)
- Length: `00 06` (6 bytes follow)
- Unit/Slave ID: `02`
- Function Code: `03` (Read Holding Registers)
- Start Address: `00 CA` (202 decimal)
- Quantity: `00 01` (1 register)

Response:
- Transaction ID: `00 01`
- Protocol ID: `00 00`
- Length: `00 03`
- Unit ID: `02`
- Function Code: `83` (0x03 + 0x80 = exception response)
- Exception Code: `02` (Illegal Data Address)

## Root Cause Analysis

### Primary Issue: Incorrect Slave/Unit ID

The most likely cause is the **wrong slave ID**. Research shows:

1. **Gateway slave ID**: 207 (for gateway-specific registers)
2. **Fireplace slave ID**: 2 (default, but **auto-assigned upon registration**)

A user in the openHAB community reported: *"the problem was that my slave ID is actually 3 (which is not what the documentation says)"*

**Action**: The slave ID can vary by installation. Need to scan multiple slave IDs (1, 2, 3, 207).

### Secondary Issue: Address Convention Ambiguity

There are two common Modbus addressing conventions:

| Convention | Formula | 40203 becomes |
|------------|---------|---------------|
| Standard (40001 = 0) | addr - 40001 | 202 |
| Alternative (40000 = 0) | addr - 40000 | 203 |

The current code uses the standard convention (202), but some devices use the alternative (203).

**Current Code** (DRURegisterMap.swift):
```swift
case status = 202    // Register 40203 → address 202 (40203 - 40001)
case action = 199    // Register 40200 → address 199 (40200 - 40001)
```

**Action**: Try both address offsets during diagnostics.

## DRU/Honeywell BRDG-03EM01 Protocol Reference

### Register Map (from community documentation)

| Modbus Register | Purpose | Type | Notes |
|-----------------|---------|------|-------|
| 40200 | Action control | Write | Values: 1=off, 101=main on, 102=2nd on, 105=wave |
| 40201 | Flame height | Write | 0-100 percentage |
| 40202 | Comm timeout | Read | Communication timeout value |
| 40203 | Status | Read | Status codes (15360=off, 47116=dual burner) |
| 40204 | Fault code | Read | Error code (0 = no error) |
| 40205 | RSSI Gateway | Read | Signal strength (multiply by -0.5 for dBm) |
| 40206 | RSSI DFGT | Read | Fireplace signal (multiply by -0.5 for dBm) |
| 40207 | Room temperature | Read | Divide by 10 for °C |
| 40250 | Thermostat | R/W | Temperature setpoint |

### Protocol Details

- **Port**: 502 (Modbus TCP standard)
- **Function Codes**:
  - 0x03: Read Holding Registers
  - 0x06: Write Single Register
  - 0x10: Write Multiple Registers
- **Polling Interval**: Minimum 10 seconds between reads (regulatory requirement)
- **Connection**: Single TCP connection only; bridge rejects concurrent connections

### Slave/Unit ID Configuration

The Honeywell BRDG-03EM01 acts as a Modbus TCP gateway:
- It assigns slave IDs dynamically when devices register
- Default fireplace slave ID is 2, but can be 1, 3, or other values
- Gateway itself responds on slave ID 207 for certain registers

## Diagnostic Recommendations

### 1. Scan Multiple Slave IDs

Try slave IDs: 1, 2, 3, 207

```bash
# Using modpoll (brew install libmodbus)
for SLAVE in 1 2 3 207; do
  echo "Testing slave $SLAVE..."
  modpoll -m tcp -a $SLAVE -r 203 -c 1 10.0.1.62
done
```

### 2. Scan Address Variants

Test both address conventions:
- Standard: 202, 199
- Alternative: 203, 200

### 3. Test with Known Working Tools

```bash
# Read status register with modpoll
modpoll -m tcp -a 2 -r 203 -c 5 10.0.1.62

# Try alternative addressing
modpoll -m tcp -a 2 -r 204 -c 5 10.0.1.62
```

## Sources

- [Home Assistant Community - DRU fireplace](https://community.home-assistant.io/t/dru-fireplace/324780)
- [openHAB Community - DRU fireplace control](https://community.openhab.org/t/dru-fireplace-control-using-oh2-nodered-modbus/53876)
- [GitHub - hass-dru](https://github.com/lion7/hass-dru)
- [GitHub - DRU-Modbus-Openhab2-NodeRed](https://github.com/snoekieboe/DRU-Modbus-Openhab2-NodeRed)
- [GitHub - com.athom.dru (Homey)](https://github.com/stemmr/com.athom.dru)

## Modbus Protocol Reference

- [Modbus Exception Codes](https://store.chipkin.com/articles/modbus-exception-responses)
- [Modbus Offset vs Addressing](https://blog.softwaretoolbox.com/topserver-modbus-offset-vs-addressing)
- [Understanding Modbus Register Addressing](https://www.elkor.net/support/knowledgebase.php?article=14)
