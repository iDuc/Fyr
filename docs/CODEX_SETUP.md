# Codex Setup for Fyr

This repository is configured for Codex work on the Mac mini at:

```bash
/Volumes/ThunderSloerie/Development/Fyr
```

## One-Time Machine Setup

**Not on the shared SloerieServer mini.** `scripts/bootstrap-mac-mini.sh` makes
machine-wide changes (`sudo xcode-select`, Xcode license and first-launch,
Homebrew ownership) that affect every project and agent on that Mac. The
`make bootstrap` target was removed for that reason. On a personal Mac you may
run the script by hand:

```bash
scripts/bootstrap-mac-mini.sh
```

It selects Xcode with `xcode-select`, accepts the license, runs first-launch
setup, repairs `/opt/homebrew` ownership if needed, installs `libmodbus` and
`xcbeautify`, and reruns `make doctor`. It asks for sudo once at the start.

## Daily Codex Commands

```bash
make doctor
make list
make build-reserved   # on SloerieServer: build inside a heavy simulator reservation
make test-reserved    # on SloerieServer: FyrTests on the reserved iOS 27.1 simulator
make clean
```

Builds use `generic/platform=iOS Simulator`; tests need a concrete iOS 27.1
simulator (`TEST_DESTINATION=id=<udid>` or the reservation's `SIMULATOR_UDID`).
DerivedData: `/Volumes/ThunderSloerie/BuildArtifacts/Fyr/DerivedData`.

## Project Context

Codex should read `AGENTS.md` first. It contains the Fyr architecture, Modbus
register map, rate limits, compatibility notes, build commands, and local Mac
mini setup details.

The active Codex config should include:

```toml
[projects."/Volumes/ThunderSloerie/Development/Fyr"]
trust_level = "trusted"

[features]
goals = true
```

## Expected Final Health Check

The environment is ready when these commands pass:

```bash
make verify
```

If `make doctor` fails on Xcode license, first-launch, `xcode-select`, or
Homebrew ownership on the shared mini, ask the machine owner instead of
running the bootstrap script.

`make doctor` intentionally fails when these are missing, because this Mac mini
is intended to be a complete Codex workstation for Fyr rather than a partial
checkout that can only edit files.
