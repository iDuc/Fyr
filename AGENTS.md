# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Fyr is an iOS app to control DRU fireplaces via ModbusTCP, with Siri integration and home screen widgets. It's a 100% local solution with no cloud services.

**Tech Stack:** Swift 6 language mode, SwiftUI, iOS 27.1+, Xcode 27.1

**Local Mac mini:** Xcode 27.1 at `/Applications/Xcode.app`.

## Compatibility

Fyr works with DRU gas fireplaces that have the Honeywell BRDG-03EM01 WiFi bridge.

### Supported DRU Series
- **Maestro series** (13 models) - 60, 75, 80, 100, 105 variants with Eco Wave
- **Metro series** (12 models) - 100XT, 130XT, 150XT, 200XT variants with Eco Wave
- **Lugo series** (2 models) - 80/2, 80/3 with Eco Wave

### Not Supported
- DRU Global series (no RCH control)
- DRU Diablo series (no RCH control)
- DRU Virtuo electric fires (Bluetooth only, different protocol)
- Newer Bluetooth-only RCH models (no WiFi bridge)

### Hardware Requirements
- **WiFi Bridge:** Honeywell BRDG-03EM01 (older RCH control system)
- **RCH Receiver:** DFGT V04 or newer
- **Connection:** Bridge connected via Ethernet to router

For detailed compatibility information, see [COMPATIBILITY.md](COMPATIBILITY.md).

## Build Commands

On SloerieServer (the shared Mac mini), always run native builds and tests
inside a heavy simulator reservation (see the simulator pool section below):

```bash
make build-reserved      # app + widget, generic iOS Simulator, Swift 6
make test-reserved       # FyrTests on the reserved iOS 27.1 simulator (default: duo)
make doctor              # environment check (read-only)
```

`make build` / `make test` run the same commands without a reservation (for
other Macs). `make test` needs `TEST_DESTINATION=id=<udid>` or `SIMULATOR_UDID`.
DerivedData lives in `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/DerivedData`;
builds use `-jobs 2` and tests run without parallel clones.

The minimum iOS version is 27.1, so tests need an iOS 27.1 simulator; on the
mini that is the shared `duo` device. Never use the "iPhone 18 Pro" /
"KoE Tests" device (`test-iphone`) for Fyr.

Do not run `scripts/bootstrap-mac-mini.sh` on the shared mini: it makes
machine-wide changes (`sudo xcode-select`, `xcodebuild -runFirstLaunch`,
Homebrew ownership).

## Architecture

### Core Layer (`Fyr/Core/`)

**Networking (`Core/Networking/`):**
- `BridgeTransport` - byte-stream protocol; `NWBridgeTransport` is the Network.framework implementation. `withDeadline` gives real timeouts by closing the transport (NWConnection ignores task cancellation)
- `ModbusProtocol` - pure MBAP/PDU framing: Read Holding Registers (0x03) and Write Single Register (0x06) only
- `ModbusTCPClient` - actor; serialized FIFO requests, exact framing (7-byte header, then `length - 1` bytes), transaction-id check (stale frames discarded), connection closed on timeout so late replies can never be misread
- `RateLimiter` - actor; `tryAcquire` checks and stamps atomically (3 s reads, 3 s writes, 10 s flame height; flame also counts as a write)

**DRU Integration (`Core/DRU/`):**
- `DRUFireplaceService` - actor singleton, the only owner of the bridge connection: one gate for connect + rate-limit slot + request, reconnect backoff for automatic polling, idle release (30 s) and `releaseConnection()` (app background, end of every App Intent), flame height "latest wins" coalescing and persistence, `IgnitionAuthorization` required for turning on
- `BridgeError` - user-facing error states (bridge busy / unreachable / not responding / rejected ...) with recovery suggestions
- `DRURegisterMap` - registers, `DRUAddressing` (register number / zero-based / one-based), action values, `DRUStatusWord` decoder
- `DRUDiscovery` - network scanning to find bridge IP (scans 1-254 on local subnet)

**Persistence (`Core/Persistence/`):**
- `SettingsStore` - app-group settings (bridge IP, unit id, addressing) with nonisolated accessors for actors and intents

**Design System (`Core/DesignSystem/`):**
- `DesignSystem.swift` - FyrDesign enum with colors, spacing, radius, animation tokens
- Glass card modifier for iOS 26 liquid glass effects
- Dynamic background component (warm/cool gradient transitions)
- Flame color gradient helper based on intensity

### Models (`Fyr/Models/`)
- `Fireplace` - Observable model using iOS 17+ Observation framework
- `FireplaceStatus` - Immutable status snapshots, decoded from registers 40203-40207
- `FireplaceError` - Error code mapping (F01, F02, etc.)

### Components (`Fyr/Components/`)
- `FlameIndicator` - Animated flame visualization with eco mode breathing effect
  - Three sizes: small (80pt), medium (120pt), large (200pt)
  - Multi-layer glow effects
  - Eco mode breathing animation (2-second cycle)

### Features (`Fyr/Features/`)
- `Dashboard/` - Main control interface with liquid glass design
  - `DashboardView` - Hero layout with dynamic background
  - `FlameHeightSlider` - Custom slider with eco mode indicator
  - `TemperatureControl` - Current/target display with presets
  - `IgnitionSlider` - Swipe-to-ignite with multi-stage haptics
- `Settings/` - Bridge IP configuration and compatibility info
  - `SettingsView` - Main settings screen
  - `CompatibilityView` - Detailed compatible model list with search
- `Onboarding/` - First-time setup with network scanning wizard
  - Includes compatibility check step before network scan

### Intents (`Fyr/Intents/`)
Six Siri App Intents with English and Dutch phrases:
- TurnOn, TurnOff, SetFlameHeight, SetTemperature, ToggleEcoMode, GetStatus
- Dutch terms: "openhaard" (fireplace), "vlammen" (flames), "wave-modus" (eco mode)

### Widget (`FyrWidget/`)
Home screen widget extension with:
- Reads the app-group snapshot only (never connects to the bridge); stale after 15 minutes
- Glass-style design matching main app
- Dynamic background (warm when on, cool when off)
- Flame glow effects and eco mode badge

## Key Technical Details

### ModbusTCP Communication
- **Port:** 502, **unit (slave) id:** 2
- **Addressing:** Fyr sends the register number as PDU address (40203 -> 40203), as v1 and the Homey app do. `DRUAddressing` also supports 40203 -> 202 and 40203 -> 203; confirm with a read-only register dump (`scripts/modbus-readonly-dump.py`), never by writing
- **Key Registers:**
  - 40200: Action register (write) - 101 on, 3 off, 105 wave on, 7 wave off
  - 40201: Flame height target (write-only) - percentage 0-100; Fyr persists the last value it set
  - 40203: Status bit field (read) - `0x3C00` off, `0xB804` on, bit 9 (`0x0200`) wave mode
  - 40204-40207: error code, gateway RSSI, fireplace RSSI (x -0.5 dBm), temperature (0.1 °C)
  - 40220: Wave interval (1-60 seconds)
  - 40250: Thermostat setpoint (0.1 °C)

### Connection Lifecycle
- The bridge accepts **one TCP connection**; the official DRU app must be able to connect, so Fyr releases it in the background, after 30 s idle and after every App Intent
- Connect timeout 5 s, request timeout 5 s, post-connect delay 1.5 s
- Status fetch reads 40203-40207 one register at a time; reads retry once, general writes retry once (values are absolute), flame height never retries
- Dashboard polling: 15 s when on, 60 s when off, backoff to 60 s on failures, ±2 s jitter; driven by `.task(id: scenePhase)`
- Failed connects back off exponentially (2 s ... 60 s) for automatic polling; user commands always try

### Rate Limiting
- **Reads:** 3 seconds minimum between status fetches
- **General writes:** 3 seconds minimum
- **Flame height:** 10 seconds minimum (regulatory requirement); enforced inside the request gate, so concurrent callers cannot bypass it

### Eco (Wave) Mode Behavior
- Varies flame between low and user-set maximum (slider value)
- Changing flame height while eco active updates the maximum
- Register 40220 controls wave interval (1-60 seconds)
- Status bit 9 (`0x0200`) indicates wave mode; the toggle shows the bridge state, with a pending state while a change is in flight

### Safety
- Turning off is always allowed. `turnOn(authorization:)` needs an `IgnitionAuthorization`; Siri/Shortcuts currently pass `.unconfirmedIntent` (v1 behaviour). Phase 2: ignition from Siri, Control Center and widgets only with an unlocked device and a confirmation

### Concurrency Model
Swift 6 language mode (strict concurrency). The app target uses `MainActor` default isolation; core types are `nonisolated`. Network work runs in actors:
- `ModbusTCPClient`, `DRUFireplaceService`, `DRUDiscovery`, `RateLimiter`

### App Groups
Uses `group.com.vanYperen.Fyr` for sharing settings and the last status snapshot (`FireplaceSnapshot`, `Shared/FyrShared.swift`) between app and widget

### Tests (`FyrTests/`)
Swift Testing, hosted in the app. `Support/FakeBridge` models the bridge (one connection slot, registers, exceptions) with fault injection (silent, late reply, refused, illegal address, busy, stale frame, dropped connection, split replies). `FakeTransport` runs it in-process; `ModbusLoopbackServer` serves it over real TCP on 127.0.0.1 for integration tests and, later, UI tests (`-FyrBridgeEndpoint 127.0.0.1:<port>`, DEBUG builds only).

## Design System

### Colors (FyrDesign.Colors)
```swift
// Fire palette
flameYellow, flameOrange, flameRed, ember

// Backgrounds
warmGradientStart/End (fireplace on)
coolGradientStart/End (fireplace off)

// Status
ecoGreen, connected, warning, error

// Glass effects
glassHighlight, glassBorder, glassBackground
```

### Spacing (FyrDesign.Spacing)
```swift
xxs: 2, xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48
```

### Animation (FyrDesign.Animation)
```swift
quick: 0.15s, standard: 0.25s, smooth: 0.35s
breathing: 2.0s (eco mode), backgroundTransition: 2.0s
springResponse: 0.35, springDamping: 0.75
```

## Testing Bridge Connectivity

```bash
# Strictly read-only register dump (function 0x03 only, >=3 s between reads,
# one connection, closed at the end). Pass the bridge IP; do not commit it.
python3 -I scripts/modbus-readonly-dump.py <BRIDGE_IP> /tmp/fyr-dump.json
```

Never write to the bridge from scripts. The terminal running the dump needs
macOS Local Network access (System Settings > Privacy & Security > Local Network).

## Localization

The app supports English and Dutch (Nederlands):
- String catalog: `Fyr/Localizable.xcstrings`
- Dutch Siri phrases in `AppShortcuts.swift`
- Key Dutch terms:
  - openhaard = fireplace
  - vlammen = flames
  - wave-modus = eco/wave mode (DRU terminology)

## Required Capabilities

When modifying the Xcode project, ensure these are configured:
- App Groups capability (both main app and widget): `group.com.vanYperen.Fyr`
- No Siri entitlement: App Intents / App Shortcuts do not need it
- Info.plist: `NSLocalNetworkUsageDescription` and `NSBonjourServices` for `_modbus._tcp`

## Shared SloerieServer simulator pool — 2026-10-01

Before Simulator, UI/MCP, native Apple build or test work on SloerieServer,
read `/Volumes/ThunderSloerie/Development/SloerieServer/docs/simulator-agent-rules.md`
and use the `sloerie-shared-simulators` skill. Run
`/Users/kat/.local/bin/sloerie-simulators status`; reserve the exact device with
`run` or `hold` for the whole operation. Add `--heavy` for builds/tests, use
existing external DerivedData, at most two compiler jobs and no unnecessary
parallel test clones. Pass the reserved UDID explicitly to UI/MCP tools.
Preserve project/account devices, warm caches and all three required runtimes.
Missing Thunder/mounts/rules must stop work, never trigger internal fallback.
Existing chats must reread the rules at their next safe boundary.
