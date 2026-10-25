# Fyr audit — upgrade 2026

*Date: 25 October 2026 · Audit only: no source changes, no commits, no network traffic to any Modbus device.*
*Executed on SloerieServer (Mac mini, user `kat`), branch `main`, commit `3e38d26` + uncommitted local changes.*

---

## 0. Short version

- **The app builds cleanly** with Xcode 27.1 / iOS Simulator SDK 27.1 (0 warnings, 0 errors). There are **no tests**.
- **The project is not really Swift 6.** It is set to `SWIFT_VERSION = 5.0`. In Swift 6 language mode, only the widget fails, with one error, so the step up is small.
- **The Modbus client is the weakest part.** Four things to fix first:
  - Its timeout does not really work.
  - It does not frame TCP responses.
  - It does not check transaction IDs.
  - It can hold the bridge's only connection for too long.
- **Safety:** Siri and Shortcuts can **light a gas fire without any confirmation**, also from the Lock Screen. This should change before anyone else uses the app.
- **The uncommitted changes are good.** Keep them. The main one is a real bug fix: Siri flame height used to be sent on a 0–15 scale. Only the new Siri entitlement is questionable.
- **TestFlight:**
  - Both bundle IDs already exist in the developer account.
  - There is **no App Store Connect app record for Fyr yet**.
  - There is **no privacy manifest**.
  - The app group name (`group.com.fyr.app`) should change.
- **iPhone Duo:** the app runs on the Duo simulator, but the layout is not adapted. The SDK has real Duo APIs (`onHingeChange`, `ArrangementView`, `ReservedRegion.division`).

---

## 1. Build and test results

| Item | Result |
|---|---|
| Xcode | **27.1** (build 27A9275), `/Applications/Xcode.app` → ThunderSloerie Xcode-27.1 |
| SDK | iPhoneSimulator **27.1** |
| Project settings | `SWIFT_VERSION = 5.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target only, not widget), deployment target **iOS 26.2**, iPhone + iPad |
| Build (app + widget, generic iOS Simulator, as configured) | **BUILD SUCCEEDED, 0 warnings, 0 errors** |
| Build with `SWIFT_VERSION=6` + `SWIFT_STRICT_CONCURRENCY=complete` (test only, not saved) | App target compiles. **Widget fails with 1 error** (on both architectures): `FyrWidget/Provider/FireplaceTimelineProvider.swift:20` — "passing closure as a 'sending' parameter risks causing data races" (`Task { … completion(timeline) }` inside `getTimeline`). The fix is small: move to `AppIntentTimelineProvider` / async `timeline(for:in:)`, or make the completion handler `@Sendable`. |
| Tests | **None.** There is no test target, and the shared scheme has empty `<Testables>`. `make test` prints "No test sources found". |
| Run on simulator | Installed and launched on the shared **iPhone Duo (iOS 27.1)** simulator. Onboarding appears in Dutch. Screenshot: `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/audit-shots/duo-onboarding.png`. The app was uninstalled and the simulator shut down afterwards. |

Logs: `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/audit-build.log` and `audit-build-swift6.log`.
DerivedData: `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/DerivedData` (new; Fyr had no external DerivedData before).

**How the simulator was handled.** The brief asked me to create a "Fyr Audit" simulator. SloerieServer's own simulator rules forbid creating devices, so I did **not** create one. Instead I reserved the existing shared `duo` device (iPhone Duo, iOS 27.1, no account) through `sloerie-simulators run` (`--heavy` for builds). "iPhone 18 Pro" and "KoE Tests" (the same device, `test-iphone`) were not touched.

**Tooling problems found:**
- The `Makefile` and `scripts/codex-doctor.sh` use the destination `name=iPhone 17`. That device no longer exists on this Mac, so **`make build` / `make test` fail as written**. Use `generic/platform=iOS Simulator` for builds and the reserved UDID (`$DESTINATION`) for tests.
- `scripts/bootstrap-mac-mini.sh` runs `sudo xcode-select`, `xcodebuild -runFirstLaunch` and `chown /opt/homebrew`. On this shared Mac these are machine-wide changes and should not run casually.
- `AGENTS.md` still says Xcode 26.3. `PROJECT_OVERVIEW.md` points to `/Volumes/DAS_mini/...`.

---

## 2. Code review — ranked risks and bugs

About 8,500 lines of Swift. The structure is reasonable: actors for networking, an `@Observable` model, SwiftUI views and App Intents. The problems are mostly in robustness, not structure.

### P0 — fix before relying on it daily

**1. The Siri / Shortcuts intents can ignite a gas fireplace with no confirmation.**
- Where: `TurnOnFireplaceIntent` and the other intents.
- They use `openAppWhenRun = false`, with no `requestConfirmation`, no `authenticationPolicy` and no check that the phone is on the home network.
- So "Hey Siri, steek het vuur aan" works from the Lock Screen, by anyone near the phone, and by a mis-heard phrase.
- Later Control Center controls will make this even easier.
- Fix:
  - Ask for confirmation when turning on.
  - Require an unlocked device (`.requiresAuthentication`) for ignition.
  - Turning off can stay frictionless.

**2. The Modbus timeout does not actually fire.**
- Where: `ModbusTCPClient.swift:440-455` `sendAndReceive`.
- It races `receiveResponse` against `Task.sleep` inside a task group.
- When the timer wins, the group still waits for the receive child to finish before it returns. That child is a `withCheckedThrowingContinuation` around `NWConnection.receive`, and it ignores cancellation.
- Result: a silent bridge **hangs the call until the TCP connection dies**. The 15-second "isFetchingStatus timeout" in `DRUFireplaceService` (`:334-345`) exists to paper over this.
- The same pattern is in `DashboardView.executeCommand` (`:286-301`). There, a timeout also reports the misleading error `commandThrottled`.
- Fix: on timeout, cancel the `NWConnection`. That makes `receive` complete. Or use a single continuation with a timer that resumes it once.

**3. TCP responses are not framed, and transaction IDs are not checked.**
- Where: `ModbusTCPClient.swift:458-477`.
- `receive(minimumIncompleteLength: 1, maximumLength: 256)` takes whatever bytes arrive first:
  - A response split over two TCP segments → `invalidResponseSize`.
  - Two responses in one segment → the second is lost or misread.
- The MBAP transaction ID, protocol ID and unit ID in the response are never compared with the request.
- After a timeout, the late answer to the *previous* request is read as the answer to the *next* one. For example, the temperature value could be shown as the status register.
- The comment "flush stale data" (`:184-195`) only sleeps 100 ms. It flushes nothing.
- Fix: read exactly 7 bytes (MBAP header), then read `length - 1` more bytes. Then check the transaction ID and unit ID.

**4. The bridge has only one connection slot, and the app holds it.**
- Docs say the BRDG-03EM01 accepts **one TCP connection**.
- Fyr keeps a connection open while the dashboard is visible. When the app goes to the background it never disconnects; iOS just suspends it.
- The bridge may keep that half-open socket until its own comm timeout (register 40202). Meanwhile the official DRU app, Homey, a second phone or the iPad cannot connect.
- Fix:
  - Disconnect on `.background`.
  - Consider "connect → do the job → disconnect after N seconds idle".
  - Show a clear "bridge busy (another app is connected?)" state.

### P1 — real bugs and fragility

**5. The 10-second flame-height rule is not enforced under concurrency.**
- Where: `RateLimiter.waitIfNeeded`.
- It computes the wait time, then sleeps (an actor re-entrancy point), then stamps the time.
- Two slider releases, or a slider release plus Siri, both compute the same wait and both fire at the same moment.
- Each slider release starts a new `Task` with no debounce or "latest value wins" logic.
- The docs call this limit a regulatory requirement, so it must hold.
- Fix: reserve the next slot *before* sleeping, and coalesce to the latest value.

**6. Reconnect can run in the middle of a command.**
- `ensureConnected()` and `reconnect()` run *before* `acquireCommandSlot()`.
- So a poll can disconnect and replace `modbusClient` while another command is waiting on the old client.
- `ModbusTCPClient` itself is re-entrant too: two concurrent callers could interleave sends on one socket. Today the service-level slot prevents this, but the diagnostics paths bypass the slot.
- Fix: one serial "bridge session" actor that owns connect, request and reconnect.

**7. The eco/wave toggle shows the wrong state and can send commands by itself.**
- The toggle is bound to `fireplace.targetEcoMode`, which is never synced from the polled `ecoModeActive`.
- So the toggle shows "off" while wave mode is on (for example, after using the remote).
- If someone later adds that sync, the `.onChange` would *send* a wave command on every poll.
- Fix: separate the displayed state from the user's intent.

**8. Flame height is fake state.**
- Register 40201 is write-only, so the service tracks `lastSetFlameHeight` **in memory only**.
- After an app restart, or after using the remote, the dashboard, widget and Siri status all report 0 or a stale value.
- Defaults are left over from the old 0–15 scale: `targetFlameHeight = 8` and `@State flameHeight = 8` mean 8 %.
- `GetFireplaceStatusIntent` says "flame level X". It should say "X percent".
- Fix:
  - Persist the last set value.
  - Label it in the UI as "last set".
  - Check whether 40203–40207 or another register exposes the real flame height.

**9. Status decoding is guesswork and the docs disagree with each other.**
- Where: `fetchStatus`, `:398-402`.
- "On" means `status != 15360 && != 0`, using magic numbers.
- Eco is taken from bit 9 (`0x0200`). But `AGENTS.md` says bit 3, `DRURegisterMap.DRUStatus` defines bit 3 (and is never used), and `CLAUDE.md` says bit 9.
- `temperatureControlActive` is hard-coded to `false`.
- Needs a decoding table checked against real register dumps from Richard's fireplace.

**10. The slave-ID / address-offset logic is dead and also wrong.**
- `ModbusDiagnosticScanner` (582 lines), `runDiagnostics()` and `updateConfiguration()` are **never called**. There is no UI that sets the slave ID or offset, so the app always uses slave 2 and raw addresses 40200+ (the Homey-app convention).
- If they were used, offset `1` is documented as "standard 40203 − 40001 = 202". In fact the code computes `40203 + 1 = 40204`, the error-code register.
- That read succeeds. With offset 1 active, the "turn on" command (value 101) would go to **40201, the flame-height register**.
- The scanner also accepts the first slave ID that answers, trying 1 before 2.
- `MODBUS_TROUBLESHOOTING.md` describes the older 202-style addressing that failed. It is not clear whether raw 40200 addressing has been tested on the real bridge.
- Fix:
  - Delete the scanner, or rebuild it with an explicit `addressBase` (0 or 40001), not a ±1 offset.
  - Use a read-only probe.
  - Never auto-apply a configuration that was found by writing.

**11. Polling lifecycle leaks.**
- The polling loop is an unstructured `Task` stored in `@State`.
- The retry-after-failure `Task` (`DashboardView:389-395`) is never cancelled, so repeated failures can create several polling loops.
- In the background the loop keeps waking up just to skip.
- Returning to the foreground triggers a refresh on a socket that is probably dead.
- Fix: one `.task(id: scenePhase)`-driven loop owned by a model object.

**12. The widget can show stale data as if it were live.**
- `FireplaceTimelineProvider` always sets `isConnected: true` and ignores the saved timestamp. A status from yesterday is shown as "On" with no age.
- The cache is only written by the dashboard. Siri actions do not update it.
- `FyrWidget/FyrWidgetExtension.entitlements` is unused (the root copy is the one in use).
- The widget display name is "FyrWidget".

**13. Discovery accepts any device with port 502 open.**
- Onboarding marks a host as "bridge" if TCP port 502 is open. Solar inverters and other Modbus devices also match.
- It assumes a /24 network on `en*` interfaces.
- It saves the bridge IP after only a TCP connect, without a Modbus read.
- It never checks that the address is IPv4.
- Should do a read-only probe of 40203 before saving.

### P2 — quality and cleanup

- **Siri phrases do not work in Dutch as written.** Dutch phrases are mixed into the *English* `AppShortcut` phrase arrays. They need an `AppShortcuts.xcstrings` with an `nl` localization.
- **Several Siri replies are not translated.**
  - Dialogs are partly hard-coded English strings.
  - `IntentDialog(stringLiteral:)` in GetStatus is never translated.
  - 133 of 209 catalog strings have Dutch translations.
- **Error messages are not user-friendly.**
  - Errors are shown as raw `localizedDescription`.
  - `DRUServiceError.commandThrottled` is reused for "timeout" and "scanning".
  - Intents rethrow connection errors instead of returning a clear answer.
- **Leftover code to clean up.**
  - 22 `print()` calls in views; `Logger` would be better.
  - Unused code: `DRUActionCommand`, `DRUStatus`, `gatewaySlaveId`, `readInputRegisters`, `writeMultipleRegisters`, legacy `DRUAction`.
- **The thermostat setpoint (40250) is written but never read back.** The UI starts at 21 °C every launch.
- **Settings has no input checks.** Bridge IP and other inputs are not validated.
- **Key UI pieces lack accessibility support.** The custom sliders and ignition slider should get `accessibilityAdjustableAction` / `accessibilityRepresentation`.
- **`SettingsStore` stores the widget cache as a `[String: Any]` dictionary.** Use a `Codable` struct shared with the widget through a small shared Swift file or package.

### Architecture summary

The layers are right: Networking → DRU service → model → views/intents/widget. The rebuild should add:
1. A `BridgeTransport` protocol, to make the client testable and swappable (see §5).
2. A single `BridgeSession` actor as the only owner of the socket, with a request queue, rate limiter and reconnect policy.
3. A `FireplaceStore` (`@Observable`, MainActor) shared by the app, intents and controls, with a persisted "last known state + timestamp" in the app group.
4. A shared framework or package target (`FyrKit`) used by the app, widget, controls and a future Watch app.

---

## 3. Uncommitted local changes — summary and advice

| Change | What | Keep? |
|---|---|---|
| `SetFlameHeightIntent.swift` | Removes the 0–15 conversion. Siri now sends 0–100 %, which matches register 40201 and `DRUFireplaceService`. | **Keep — real bug fix.** Before this, "50 %" via Siri wrote 8 %. |
| `Fireplace.swift`, `FireplaceStatus.swift`, `DRUFireplaceService.swift` | Comments changed from "0–15" to "0–100 %". | Keep |
| `README.md` | Register table corrected (40201 flame target, 40205/40206 RSSI, 40251 removed), read interval set to 3 s, modpoll note. | Keep. Note that the MODBUS doc still says "minimum 10 s between reads", so it disagrees. |
| `.gitignore` + `Fyr.xcodeproj/xcshareddata/xcschemes/Fyr.xcscheme` | Shares the `Fyr` scheme so command-line builds work. | **Keep.** Required for CI and agents. |
| `project.pbxproj` | Xcode `SystemCapabilities` metadata (App Groups for both targets, Siri for the app). | Keep (harmless). |
| `Fyr/Fyr.entitlements` | Adds `com.apple.developer.siri`. | **Questionable.** App Intents / App Shortcuts do not need this entitlement; it is for the older SiriKit Intents. The Siri capability is **not** enabled on the bundle ID in the developer portal, so automatic signing would need to change the identifier. Advice: remove it unless SiriKit is planned. |
| `CLAUDE.md` | Adds the shared simulator pool section. | Keep. The rest of CLAUDE.md is stale: it says Swift 6, mentions register 40251, and says eco is bit 9. |
| `AGENTS.md`, `Makefile`, `scripts/*`, `docs/CODEX_SETUP.md` (new) | Codex setup and wrappers. | Keep, but update: Xcode 27.1, no `iPhone 17` destination, use `sloerie-simulators run --heavy`, external DerivedData, and remove or guard the sudo bootstrap. |
| `PROJECT_OVERVIEW.md` (new, Dutch) | Overview with open questions. | Keep (move to `docs/`). Fix the `/Volumes/DAS_mini` path. |

All of it looks intentional and consistent. None of it should be thrown away. Committing is Richard's call; this audit did not commit.

---

## 4. Modernization on iOS 27 / Xcode 27.1

Checked against the **installed iPhoneSimulator 27.1 SDK**, not from memory. Everything listed below exists in the SDK unless marked otherwise.

### Worth it (recommended)

| Feature | SDK evidence | Why it fits Fyr |
|---|---|---|
| **Control Center / Lock Screen / Action button controls** | WidgetKit `ControlWidgetToggle`, `ControlWidgetButton` (iOS 18+); AppIntents `ControlConfigurationIntent`, `SetValueIntent` | A "Fire on/off" toggle and a "Wave mode" toggle. This is the single best everyday upgrade. Turning on needs a confirmation step (see P0-1), for example a button that opens the app or asks for confirmation; turning off can be a direct toggle. |
| **Interactive widgets + more sizes** | `Button(intent:)` / `Toggle(intent:)` in widgets; `AccessoryWidgetGroup`; `WidgetFamily.systemExtraLargePortrait` (**iOS 27.0, new**); `WidgetRelevance`; `widgetAccentedRenderingMode`; `WidgetMountingStyle`, `LevelOfDetail` (iOS 26) | Lock Screen accessory (temperature + flame), small/medium widgets with an off button, StandBy (system families render there automatically). The new portrait XL family is probably more relevant to iPad than to Duo. |
| **Live Activity / Dynamic Island while the fire burns** | ActivityKit (Live Activities); `LiveActivityIntent`; WidgetKit `isDynamicIslandLimitedInWidth` (**iOS 27.0, new**) | "Fire on since 19:42 · 21.4 °C · wave" on the Lock Screen and in the Dynamic Island, with an off button. Limit: without a server there are no push updates. The app can only update it while it runs, so show "last updated" and end it on a timer. Still useful as a reminder that the fire is on. |
| **App Intents upgrade** | `AppEntity` for the fireplace, `SnippetIntent`, `AppShortcuts` localization; `LongRunningIntent`, `IntentExecutionTargets`, `RelevantEntities` (**iOS 27.0, new**) | A `FireplaceEntity` lets Siri and Shortcuts read state and gives better Apple Intelligence results. Use `SnippetIntent` for an interactive status card in Siri. Dutch phrases go into a proper `AppShortcuts.xcstrings`. |
| **iPhone Duo adaptive layout** | SwiftUI `onHingeChange(_:)` with `DeviceHingeContext` / `DeviceHinge` (`status`: closed / partiallyOpen / fullyOpen, `angle`), `ArrangementView` with `.split` / `.overlay` styles, `splitArrangementLayoutRatio`, `GeometryProxy.reservedRegions(kind: .division / .occlusion)`; UIKit `UIHingeInteraction` (**all iOS 27.1**) | Folded: same as the phone layout. Open: a two-pane layout, with the flame and status on one side and the controls on the other, kept clear of the `.division` region. Half-open on a table: a "tent"/StandBy-like view with a big flame on the top half and controls on the bottom. The app needs to raise its minimum to 27.1 or use `#available` guards. |
| **Swift 6 language mode + Swift Testing** | Xcode 27.1 | Only one widget error blocks it (§1). |

**What the Duo test showed:** on the open Duo screen (1398×2034 px) onboarding runs, but it is not adapted. The text block sits left of centre and the "Aan de slag" button sits right of centre, with a lot of empty space. There is no hinge awareness anywhere. Folded mode was not tested.

**About Apple documentation for Duo:** I found no Apple developer page through a quick web search. Press and third-party guides mention `onHingeChange` / `UIHingeInteraction` and size-class-driven layouts. Treat the SDK headers (quoted above) as the source of truth, and read Apple's documentation in Xcode 27.1 before designing.

### Maybe later

- **Apple Watch app.** The watchOS platform is installed. A watch cannot open a local TCP connection to the bridge on its own, except possibly on the same Wi-Fi network, so it would rely on the phone. Only worth it after the core works. A control or complication through intents may be enough.
- **Apple Intelligence / model delegation.** AppIntents has underscored `_ModelDelegation*` types; those are private, so don't use them. Plain App Intents and entities are what Siri uses.
- **HomeKit / Matter** (from the PRD). Not possible as an App Store app acting as a HAP bridge in the background. It needs a bridge device (Homebridge/Home Assistant) — out of scope for this project.

### Not worth it now
Push-updated widgets (`WidgetPushHandler`) and push Live Activities. Both need a server, which breaks the "100 % local" rule.

---

## 5. Testing strategy without the real fireplace

1. **Pure unit tests (Swift Testing).** Cover `ModbusProtocol` encoding and decoding with golden bytes, using the request/response pairs from `MODBUS_TROUBLESHOOTING.md`. Also cover:
   - status decoding table
   - error-code mapping
   - rate limiter (with an injectable clock)
   - polling backoff
   - temperature scaling
2. **`BridgeTransport` protocol + in-memory fake bridge.** An actor that holds a register map (40200–40250) and behaves like the DRU:
   - action 101 sets the "on" status after N seconds
   - 105/7 toggle wave mode
   - 40201 is write-only
   - exception 0x02 for unknown addresses, 0x05 "busy"
   Test the service, store and intents against it.
3. **Fault injection on the fake.** Silent device (timeout), split TCP frames, two frames in one read, late or stale transaction IDs, connection refused because the slot is taken, connection drop in the middle of a command, slow connect (> 1.5 s).
4. **Loopback Modbus server for integration and UI tests.** A small `NWListener` server, written in Swift inside the test bundle, on `127.0.0.1:15020`, wrapping the same fake bridge. Point the app at it with a launch argument (for example `-FyrBridgeEndpoint 127.0.0.1:15020`).
   - Use this for XCUITests: onboarding (with manual IP), ignite slider, flame slider and the cooldown, wave toggle, connection-lost banner.
   - Run them on the reserved `duo` and `test-iphone-ios26` simulators.
   - Alternative: `pymodbus` simulator on the Mac, but the Swift version needs no extra tooling.
5. **Snapshot or preview checks** for widget families, the Live Activity and the Duo folded/open layouts.
6. **Real-hardware checklist (manual, Richard).** Read-only dump of 40200–40250 in on, off, wave and error states. This becomes the golden data for the decoder. Then a short write test, with Richard present at the fireplace.

---

## 6. TestFlight readiness

| Item | Status |
|---|---|
| Bundle IDs | `com.vanYperen.Fyr` (portal ID B9MYW3C72W) and `com.vanYperen.Fyr.FyrWidget` (922V52R4Y5) **exist** in the developer account, created by Xcode ("XC …"). |
| Capabilities on bundle IDs | Both: `APP_GROUPS`, `IN_APP_PURCHASE` (default). **No `SIRI`**, which matters only if the Siri entitlement is kept. No provisioning profiles listed for the app ID. |
| Team | `DEVELOPMENT_TEAM = SZWSVWQSP3`, automatic signing, all configurations. |
| App group | `group.com.fyr.app` in both targets. The ASC API cannot list app groups, so I could not confirm it is registered under this team. Group IDs are global and this one looks generic. **Advice: change to `group.com.vanYperen.Fyr`** (the app is not released, so there is no migration cost). |
| App Store Connect app record | **Does not exist.** Checked read-only with `asc apps list` (profile "spullio"). The account has Spullio, KeepOfEchoes and Functie Elders, but no Fyr. Creating it is Richard's decision (name, SKU, primary language). Whether the name "Fyr" is free is unknown until he tries. |
| Version / build | `MARKETING_VERSION 1.0`, `CURRENT_PROJECT_VERSION 1`. Needs a build-number bump per upload (agvtool or CI). Suggest 2.0 for the rebuild. |
| App icon | 1024 px light, dark and tinted PNGs in `AppIcon.appiconset` — sufficient. An Icon Composer file `docs/Fyr-icon.icon` exists but is **not used** by the project. Move it into the target for the iOS 26+ Liquid Glass icon. |
| Privacy manifest | **Missing** in both targets. Both use `UserDefaults`, a required-reason API (reason `CA92.1`, plus `1C8F.1` for app group access). Add `PrivacyInfo.xcprivacy` to app and widget; no tracking, no data collected. |
| Local network | `NSLocalNetworkUsageDescription` present (English only; add Dutch). `NSBonjourServices` has `_modbus._tcp` and `_fyr-preflight._tcp`. OK. |
| Export compliance | `ITSAppUsesNonExemptEncryption` not set. Add `NO` to avoid the question on every upload. |
| Device families | iPhone + iPad (`1,2`). Fine. The iPad needs a layout check too. |
| Review | Internal TestFlight (Richard only) needs no Beta App Review. External testers would need review, and the "ignite gas without confirmation" behaviour may raise questions. |
| Secrets | An ASC key `AuthKey_QSKWP2WVYV.p8` sits in `/Volumes/ThunderSloerie/Development/` (contents not opened). `asc` is configured through its keychain profile. Consider moving the loose `.p8` into a protected location. |

---

## 7. Questions only Richard can answer

1. **Does the current build (raw addresses 40200+, slave 2) work on your fireplace today?** Which actions have you seen work: on, off, flame, wave, thermostat? Have you seen the "Illegal Data Address" error since the switch to raw addresses?
2. **Which DRU model, bridge firmware and RCH version do you have?** Can you allow one supervised **read-only** register dump (40200–40250, slave 1/2/3/207) in on, off and wave states, to fix the status decoding?
3. **Other bridge users:** does anything else talk to the bridge (official DRU app, Homey, Home Assistant, a second phone or iPad)? This decides how aggressively Fyr must release the single connection.
4. **Safety policy:** should Siri, Control Center and widgets be allowed to *ignite* the fire, or only turn it off and show status? If ignition is allowed, should it require an unlocked phone and/or a confirmation?
5. **Is there a thermostat (40250) on your unit,** and do you use thermostat mode at all?
6. **Duo:** do you (or will you) own an iPhone Duo? Should the open layout be a richer "two-pane" app, or just the phone layout centred?
7. **Scope:** a Live Activity while the fire burns, Apple Watch, iPad — which of these do you want in the first TestFlight?
8. **App Store Connect:** may an agent create the "Fyr" app record (SKU, primary language Dutch or English)? Personal TestFlight only, or eventually public?
9. **May we rename the app group** to `group.com.vanYperen.Fyr` and remove the Siri entitlement?
10. **Minimum iOS:** raise to 27.1 (needed for the Duo hinge APIs without `#available` checks), or keep 26.2?
11. **Commit the current local changes** as a "baseline" commit before the upgrade work starts?
