# Phase 2 — safe control (25 October 2026)

Branch `upgrade-2026`. No traffic to the real bridge; everything below was
tested against the in-process fake bridge and the loopback Modbus server.

## Ignition per surface

| Surface | Turn off | Turn on | Flame / wave on / thermostat |
|---|---|---|---|
| Fyr app (open) | always | swipe-to-ignite slider | only while burning |
| Siri (iPhone, also from the Lock Screen) | always, no prompt | iPhone must be unlocked (Face ID / code) **and** you confirm "Light the fireplace now?" | only while burning; on a locked phone too |
| Shortcuts app / automations | always | same: unlock + confirmation, every run | only while burning |
| HomePod / Watch / CarPlay Siri | always | not on that device: `.requiresLocalDeviceAuthentication` needs the device running the intent to be unlocked | only while burning |
| Widgets, Control Center, Lock Screen controls, Action button | not built yet (phase 3) | they must run `TurnOnFireplaceIntent`, so the same two checks apply | — |

"Only while burning" means: Fyr reads the status register right before
the write. If the fire is off, it sends nothing and says "The fireplace is off.
Turn the fireplace on first." Wave **off** is always allowed.

## What changed

- `SafetyPolicy` (new) holds the rules; the service and intents both use it.
  `IgnitionAuthorization.unconfirmedIntent` (the v1 behaviour) is gone.
- `DRUFireplaceService`: the burning check runs under the same gate hold as the
  write, so an "off" that is queued first always wins. It is checked again on retry.
- App Intents: `supportedModes = .background` (replaces the deprecated
  `openAppWhenRun`), wave terminology, `FireplaceEntity` + query, Get Status
  returns the entity (for "if the fireplace is on" in Shortcuts).
- App Shortcuts: on, off, wave on, wave off, status, flame height. Dutch
  phrases are now real `nl` translations (`Fyr/AppShortcuts.xcstrings`); before,
  they were mixed into the English list. Thermostat is not promoted.
- Onboarding: a host with port 502 open is only accepted after a read-only
  probe of 40203 (unit 2) returns a plausible DRU status word. The probe also
  finds which addressing convention answers, and onboarding saves it.
- Dutch translations for the new strings and for the bridge error messages.

## Checks on a real iPhone (Richard)

Only a real iPhone can test Siri, Face ID and the confirmation prompt; the
simulator tests cannot. Install via Xcode or TestFlight, then:

1. Locked phone: "Hé Siri, zet Fyr uit". This should work right away.
2. Locked phone: "Hé Siri, zet Fyr aan". Siri should ask you to unlock first,
   then ask "De openhaard nu aansteken?". Say "nee" and check that nothing happens.
3. Repeat step 2 and answer "ja". The fire should light.
4. Fire off: "Zet wave-modus aan met Fyr". You should hear "De openhaard staat
   uit…" and the fire must stay off.
5. In Shortcuts: "Status openhaard opvragen" → "If Fireplace On" should work as a condition.
6. Onboarding scan finds the bridge (and nothing else with port 502).

## Open points

- The plausibility rule (bits `0x3800` set) is based on the three status
  words v1 observed. The register dump (see `register-dump-2026-10-25.md`)
  should confirm it. If a real bridge is rejected, the onboarding test
  offers "Use this address anyway" (with a warning). It only appears when the
  device answered Modbus but not with a DRU status word.
- Is it acceptable that Siri on a HomePod can turn the fire *off* but never *on*?
  This follows from the "unlocked device" rule.
