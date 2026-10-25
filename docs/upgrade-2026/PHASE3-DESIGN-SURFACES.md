# Phase 3 — design, iOS 27 surfaces, iPhone Duo (25 October 2026)

Branch `upgrade-2026`, version 2.0. Everything was tested against the fake
bridge (in-process, the loopback server in `FyrTests`, `FakeDRUBridge` in
`FyrUITests`, and `scripts/fake-dru-bridge.py` for screenshots). No traffic to
the real bridge.

## Design

- One clear order: the fire and its state ("Brandt" / "Uit", since when,
  wave, room temperature), then on/off, wave, flame height. The thermostat is a
  quiet row at the bottom that opens a sheet (Richard does not use it).
- Off is one tap ("Uitzetten"). On is the swipe-to-ignite slider. VoiceOver
  users get the named action "Steek het vuur aan", which asks for confirmation.
- Wave is a full card with its own color (fjord blue) and says what it does.
- Flame height: native slider in steps of 5 %, "Hoogste vlam" in wave mode,
  shows "instellen…" and the 10-second countdown. Changes that do not come from
  dragging (VoiceOver, UI tests) are sent 0.7 s after the last step.
- Palette: birch and soot neutrals, ember accent, adaptive for light and dark;
  real Liquid Glass (`glassEffect`, `.glass` buttons).
- `FlameView`: a drawn fire (three tongues over a glowing bed) that flickers,
  rises and falls in wave mode and becomes an outline when off. Still with
  Reduce Motion. Haptics on ignite, off, wave, flame steps and hinge changes.
- Dutch and English for every new string.

## New surfaces (iOS 27.1 SDK APIs, checked in the SDK)

| Surface | What | Safety |
|---|---|---|
| Control Center / Lock Screen / Action button | Fire Off (button), Wave (toggle), Light Fire (button) | Off and wave: any time. Light Fire runs `TurnOnFireplaceIntent`: unlock + confirm. Wave on is refused while the fire is off |
| Home Screen widget small / medium | State, since, Turn Off, wave toggle (medium) | Turn Off whenever the fire is, or may be, burning. No ignition; tap opens Fyr |
| Lock Screen widgets | circular / rectangular / inline status | read only |
| StandBy | the small widget (works without its background) | as above |
| Live Activity / Dynamic Island | while burning: state, since, temperature, Turn Off, wave on/off | no ignition |

All fireplace intents declare `allowedExecutionTargets = .main` (new in iOS
27): a tap in a widget, control or Live Activity runs in the app process, so
`DRUFireplaceService.shared` stays the only owner of the bridge connection.
After every accepted command and every status read, `FyrSurfaces` saves the
snapshot and refreshes widgets, controls and the Live Activity.

**Honest limits of the Live Activity and widgets.** Fyr has no server, so
nothing can push updates. They change only when Fyr talks to the bridge:
while the app is open (polling every 15–60 s), and when Siri, Shortcuts, a
widget or a control runs a command. If the fire is switched with the remote
or the DRU app while Fyr is closed, they do not know. After 15 minutes without
news the Live Activity says "Niet bevestigd sinds …" and the widget "Laatst
bekend …". A Live Activity can only *start* while Fyr is in the foreground;
iOS ends it after at most 8 hours.

## iPhone Duo

`DashboardLayout` decides from the space and the reserved regions, not the
device model:

- closed (outer display) and phones: one column;
- open and flat: two panes split exactly at the fold (`GeometryProxy.reservedRegions(kind: .division, options: .includeInactive)`), the fire on one side, the controls on the other;
- partly folded: `ArrangementView` with `.split` keeps both halves clear of the fold;
- iPad / wide windows: two panes side by side;
- accessibility text sizes: one column.

`onHingeChange` gives the hinge state (a smaller flame when half folded, and a
light haptic on changes). Settings and onboarding keep a readable column.

Screenshots: `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/phase3/screens/`
(`scripts/duo-screenshots.sh`). Simulator only; the real Duo, widgets on a
Home Screen, controls and the Live Activity on a locked device need Richard.

## App Store prerequisites

- Icon Composer icon `Fyr/AppIcon.icon` is the app icon (the old PNG set is gone).
- `PrivacyInfo.xcprivacy` in app and widget: no tracking, no data collected,
  UserDefaults (CA92.1, 1C8F.1).
- `ITSAppUsesNonExemptEncryption = NO`, `NSSupportsLiveActivities = YES`.
- Local Network text in English and Dutch (`Fyr/InfoPlist.xcstrings`).

## Tests

- `FyrTests`: unit and integration tests (Swift Testing), including the new
  snapshot, refresh and Duo layout rules and the intent declarations.
- `FyrUITests`: swipe to ignite (a partial swipe sends nothing) and one-tap off,
  wave toggle follows the bridge, one flame height per release, thermostat
  sheet, unreachable bridge message. `make test-ui-reserved`.

## Checks on a real iPhone (Richard)

1. Control Center: add Fyr's Fire Off, Wave and Light Fire. Locked: Fire Off works, Light Fire asks to unlock and to confirm.
2. Light the fire in the app: a Live Activity appears; Turn Off in it works.
3. Widget small/medium on the Home Screen and in StandBy (charging, landscape).
4. The DRU app can still connect while Fyr is closed.
5. On the iPhone Duo (when it arrives): closed, open, half folded on a table.
