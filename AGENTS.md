# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Fyr is an iOS app to control DRU fireplaces via ModbusTCP, with Siri integration and home screen widgets. It's a 100% local solution with no cloud services.

**Tech Stack:** Swift 6.0, SwiftUI, iOS 26.0+, Xcode 17.0+

**Local Mac mini:** `/Applications/Xcode.app` is installed and currently reports
Xcode 26.3 (`17C529`). The project was generated with Xcode tools 26.2.

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

```bash
# Check this Mac/Codex environment before building
make doctor

# One-time machine setup for this Mac mini
make bootstrap

# Build the project
make build

# Build and run tests (tests directory exists but is currently empty)
make test

# Full Codex readiness gate
make verify

# Clean build
make clean

# Direct xcodebuild wrapper when custom arguments are needed
scripts/xcodebuild-fyr.sh -project Fyr.xcodeproj -scheme Fyr -destination 'platform=iOS Simulator,name=iPhone 17' build
```

On this Mac mini, Xcode is installed at `/Applications/Xcode.app`, while
`xcode-select` may point at Command Line Tools. Use `make` or
`scripts/xcodebuild-fyr.sh` so `DEVELOPER_DIR` is set correctly per command.
For a one-time machine setup or after Xcode updates, run:

```bash
make bootstrap
```

The bootstrap asks for sudo once, then configures `xcode-select`, accepts the
Xcode license, runs Xcode first-launch setup, repairs Homebrew ownership if
needed, installs required `libmodbus`/`xcbeautify` tooling when missing, and reruns
`make doctor`.

See `docs/CODEX_SETUP.md` for the local setup checklist and final health gates.

If doing the setup manually, the required system-level commands are:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -license accept
sudo DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -runFirstLaunch
```

Required local tools for this Mac mini baseline:

```bash
sudo chown -R "$(id -un)" /opt/homebrew
brew install libmodbus xcbeautify
```

The project includes a shared `Fyr` scheme under
`Fyr.xcodeproj/xcshareddata/xcschemes/` so CLI builds do not depend on local
Xcode user data.

## Architecture

### Core Layer (`Fyr/Core/`)

**Networking (`Core/Networking/`):**
- `ModbusTCPClient` - Actor-based TCP client using Network.framework for ModbusTCP protocol
- Supports function codes: Read Holding Registers (0x03), Write Single (0x06), Write Multiple (0x10)
- Uses MBAP headers with proper transaction IDs
- Post-connection delay: 1500ms for DRU bridge readiness
- Keepalive interval: 30s for connection health monitoring

**DRU Integration (`Core/DRU/`):**
- `DRUFireplaceService` - Singleton actor service that wraps ModbusTCPClient
- `DRURegisterMap` - Register addresses and constants for Honeywell BRDG-03EM01 bridge
- `DRUDiscovery` - Network scanning to find bridge IP (scans 1-254 on local subnet)
- `RateLimiter` - Enforces rate limits (3s for reads, 10s for flame height changes)

**Persistence (`Core/Persistence/`):**
- `SettingsStore` - UserDefaults wrapper with App Groups for widget data sharing

**Design System (`Core/DesignSystem/`):**
- `DesignSystem.swift` - FyrDesign enum with colors, spacing, radius, animation tokens
- Glass card modifier for iOS 26 liquid glass effects
- Dynamic background component (warm/cool gradient transitions)
- Flame color gradient helper based on intensity

### Models (`Fyr/Models/`)
- `Fireplace` - Observable model using iOS 17+ Observation framework
- `FireplaceStatus` - Immutable status snapshots
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
- Glass-style design matching main app
- Dynamic background (warm when on, cool when off)
- Flame glow effects and eco mode badge

## Key Technical Details

### ModbusTCP Communication
- **Port:** 502
- **Slave ID:** 2
- **Key Registers:**
  - 40200: Action register (write) - command values such as 101 on, 3 off, 105 wave on, 7 wave off
  - 40201: Flame height target (write) - percentage 0-100
  - 40203-40207: Status registers (read) - status bits, error code, flame height, RSSI, temperature
  - 40250: Thermostat setpoint (read/write)
  - 40220: Wave interval (1-60 seconds)

### Connection Stability
- Post-connection delay: 1500ms (increased for DRU bridge)
- Polling interval: 15s with exponential backoff on failures
- Backoff max: 60s after 4+ consecutive failures
- Polling jitter: ±2s to prevent thundering herd
- Command timeout: 30s
- Retry count: 3 attempts before failure

### Rate Limiting
- **Reads:** 3 seconds minimum (reduced for responsiveness)
- **Flame height:** 10 seconds minimum (regulatory requirement)
- **General writes:** 3 seconds minimum
- **Wave pattern EEPROM:** 1x per day (hardware limitation)

### Eco Mode Behavior
- Varies flame between low and user-set maximum (slider value)
- Changing flame height while eco active updates the maximum
- Register 40220 controls wave interval (1-60 seconds)
- Status bit 3 (`0x0008`) indicates wave/eco mode active

### Concurrency Model
All network operations use Swift actors for thread safety:
- `ModbusTCPClient` is an actor
- `DRUFireplaceService` is an actor singleton
- `DRUDiscovery` is an actor
- `RateLimiter` is an actor

### App Groups
Uses `group.com.fyr.app` for sharing data between main app and widget

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
# Check if bridge is reachable
nc -zv <BRIDGE_IP> 502

# Read registers with modpoll if you have installed it separately
modpoll -m tcp -a 2 -r 203 -c 5 <BRIDGE_IP>
```

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
- App Groups capability (both main app and widget)
- Siri capability
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
