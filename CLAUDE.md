# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fyr is an iOS app to control DRU fireplaces via ModbusTCP, with Siri integration and home screen widgets. It's a 100% local solution with no cloud services.

**Tech Stack:** Swift 6 language mode, SwiftUI, iOS 27.1+, Xcode 27.1

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
make test-ui-reserved    # FyrUITests against a fake bridge on 127.0.0.1 (default: duo)
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

Code used by both the app and the widget extension lives in `Shared/` (a
synchronized folder in both targets). App-only code lives in `Fyr/`.

### Shared (`Shared/`, app + widget extension)

**Networking (`Core/Networking/`):**
- `BridgeTransport` - byte-stream protocol; `NWBridgeTransport` is the Network.framework implementation. `withDeadline` gives real timeouts by closing the transport (NWConnection ignores task cancellation)
- `ModbusProtocol` - pure MBAP/PDU framing: Read Holding Registers (0x03) and Write Single Register (0x06) only
- `ModbusTCPClient` - actor; serialized FIFO requests, exact framing (7-byte header, then `length - 1` bytes), transaction-id check (stale frames discarded), connection closed on timeout so late replies can never be misread
- `RateLimiter` - actor; `tryAcquire` checks and stamps atomically (3 s reads, 3 s writes, 10 s flame height; flame also counts as a write)

**DRU (`Core/DRU/`):**
- `DRUFireplaceService` - actor singleton, the only owner of the bridge connection: one gate for connect + rate-limit slot + request, reconnect backoff for automatic polling, idle release (30 s) and `releaseConnection()` (app background, end of every App Intent), flame height "latest wins" coalescing and persistence, `IgnitionAuthorization` required for turning on. Publishes every status read (`statusSink`) and every accepted command (`commandSink`) to `FyrSurfaces`
- `BridgeError`, `DRURegisterMap` (registers, `DRUAddressing`, action values, `DRUStatusWord`), `SafetyPolicy` (see Safety)

**Persistence:** `SettingsStore` - app-group settings with nonisolated accessors for actors and intents.
**Design System:** `FyrDesign` tokens (see below), Liquid Glass `glassCard`, `DynamicBackground`.
**Components:** `FlameView` - the drawn fire (Canvas): flickers, rises and falls in wave mode, outline when off; still with Reduce Motion and in widgets (`animated: false`).
**Models:** `FireplaceStatus` (registers 40203-40207), `FireplaceError`.
**`FyrShared.swift`:** app group, widget/control kinds, `FireplaceSnapshot` (last known state + `burningSince`, stale after 15 min; `applying(command)` for accepted commands).

**Surfaces (`Surfaces/`):**
- `FyrSurfaces` - saves the snapshot and refreshes widgets, controls and the Live Activity, on visible changes or every 5 min (`surfacesPublishedAt`)
- `FireLiveActivity` - `FireActivityAttributes`; starts the activity when the fire burns (foreground only), updates it, ends it when the fire is off. No push server: it only changes when Fyr talks to the bridge, and carries a stale date

**Intents (`Intents/`):** all `supportedModes = .background` and `allowedExecutionTargets = .main` (they run in the app process also from widgets and controls, so the bridge connection keeps one owner), run through `FireplaceIntentSupport.execute` (configure, confirm if needed, command, always release the connection). `FireplaceEntity` is returned by Get Status. `SetWaveModeIntent` (`SetValueIntent`, not discoverable) drives the wave toggle in controls, widgets and the Live Activity.
- TurnOn (unlock + confirm), TurnOff, EnableEcoMode / DisableEcoMode (wave on/off), ToggleEcoMode ("Set Wave Mode"), SetFlameHeight, SetTemperature, GetFireplaceStatus. Type names are kept for existing user shortcuts; titles say "wave mode"
- Strings: `Shared/Localizable.xcstrings` (en + nl), compiled into both targets

### App (`Fyr/`)
- `App/FyrApp.swift` - creates `Fireplace` and `FireplaceController`; DEBUG `UITestSupport` (`-FyrUITestReset YES`)
- `Features/Dashboard/` - `DashboardView` (fire and big state first, then on/off, wave, flame height; thermostat tucked away), `DashboardLayout` (one column; two panes split exactly at the iPhone Duo fold via `GeometryProxy.reservedRegions(kind: .division)`; `ArrangementView` `.split` when partly folded; side by side on wide screens; `onHingeChange` in the dashboard), `FireplaceController` (polling 15 s on / 60 s off with backoff, commands), `FireStatusHeader`, `PowerControl` (swipe-to-ignite slider / one-tap off), `WaveModeCard`, `FlameHeightCard`, `ThermostatRow` + sheet
- `Features/Onboarding/`, `Features/Settings/` (incl. Live Activity switch and the controls explanation), `Core/DRU/DRUDiscovery` + `BridgeProbe` (onboarding only)
- `Intents/AppShortcuts.swift` + `AppShortcuts.xcstrings` (Dutch phrases); `InfoPlist.xcstrings` (Local Network text, en + nl); `AppIcon.icon` (Icon Composer); `PrivacyInfo.xcprivacy`

### Widget extension (`FyrWidget/`)
Never connects to the bridge; shows the app-group snapshot.
- `FyrWidget` - small, medium (interactive: Turn Off, wave toggle), Lock Screen circular / rectangular / inline; StandBy uses the small one. Turn Off is offered whenever the fire is, or may be, burning
- `FyrControls` - Control Center / Lock Screen / Action button: Fire Off, Wave (toggle), Light Fire (runs `TurnOnFireplaceIntent`: unlock + confirm)
- `FireLiveActivityWidget` - Lock Screen + Dynamic Island, with Turn Off and wave buttons; says "not confirmed" when stale

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
Policy in `Core/DRU/SafetyPolicy.swift` (Richard's decision, Oct 2026), tested in `SafetyPolicyTests` / `IntentLogicTests`:
- **Off** (and wave off) is always allowed, from every surface, also on a locked device, without confirmation.
- **On, in the app:** only through the swipe-to-ignite slider (`IgnitionAuthorization.appSlider`).
- **On, from any App Intent** (Siri, Shortcuts, interactive widgets, Control Center / Lock Screen controls, Action button): `TurnOnFireplaceIntent` has `authenticationPolicy = .requiresLocalDeviceAuthentication` (the device running it must be unlocked) and calls `requestConfirmation(actionName: .turnOn, ...)` before connecting. `FireplaceIntentSupport.execute` refuses ignition without a confirmation step (`.ignitionNotAuthorized`). Every future surface must run `TurnOnFireplaceIntent`, never call `turnOn` directly.
- **Flame height, wave on, thermostat, wave interval:** only while the fire burns. The service reads 40203 under the same gate hold, right before the write, and throws `BridgeError.fireplaceOff` otherwise (checked again on retry). These may run on a locked device.
- **Widgets, controls, Live Activity:** Turn Off and the wave toggle only; the Light Fire control runs `TurnOnFireplaceIntent`. In the app, VoiceOver users light the fire with the named action "Light the fire", which asks for confirmation first.
- `authenticationPolicy` must be a literal (App Intents metadata); `IntentDeclarationTests` checks each literal against `FireplaceIntentSupport.authenticationPolicy(for:)`

### Concurrency Model
Swift 6 language mode (strict concurrency). The app target uses `MainActor` default isolation; core types are `nonisolated`. Network work runs in actors:
- `ModbusTCPClient`, `DRUFireplaceService`, `DRUDiscovery`, `RateLimiter`

### App Groups
Uses `group.com.vanYperen.Fyr` for sharing settings and the last status snapshot (`FireplaceSnapshot`, `Shared/FyrShared.swift`) between app and widget

### Tests (`FyrTests/`, `FyrUITests/`)
`FyrUITests` start `FakeDRUBridge` (a Modbus server on 127.0.0.1 inside the test runner) and launch the DEBUG app with `-FyrBridgeEndpoint`. Screenshots: `scripts/duo-screenshots.sh` (inside a `duo` reservation) with `scripts/fake-dru-bridge.py`.

Swift Testing, hosted in the app. `Support/FakeBridge` models the bridge (one connection slot, registers, exceptions) with fault injection (silent, late reply, refused, illegal address, busy, stale frame, dropped connection, split replies). `FakeTransport` runs it in-process; `ModbusLoopbackServer` serves it over real TCP on 127.0.0.1 for integration tests and, later, UI tests (`-FyrBridgeEndpoint 127.0.0.1:<port>`, DEBUG builds only).

## Design System

Scandinavian and quiet, light and dark: birch / soot neutrals, one ember
accent, fjord blue for wave mode. All colors in `FyrDesign.Colors` adapt to
the appearance; cards are real Liquid Glass (`glassEffect`).

```swift
// Fire (same in both modes): flameYellow, flameOrange, flameRed, ember, glow
// Accents: accent (ember), wave (fjord blue), waveSubtle
// Backgrounds: coolGradientStart/End (off), warmGradientStart/End (burning)
// Status: connected, warning, error
// Text: textPrimary, textSecondary, textTertiary; hairlines: glassBorder(Subtle)
// Spacing: xxs 2, xs 4, sm 8, md 16, lg 24, xl 32, xxl 48
// Animation.spring (0.4 / 0.82), breathing 8 s (one wave cycle)
// Size.readableWidth 560 (one column on iPad / open Duo)
```

Accessibility: Dynamic Type everywhere (text styles), VoiceOver labels and a
named ignite action, Reduce Motion stops the flame and background animations,
haptics on ignite, off, wave, flame steps and hinge changes.

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
