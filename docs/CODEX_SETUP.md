# Codex Setup for Fyr

This repository is configured for Codex work on the Mac mini at:

```bash
/Volumes/ThunderSloerie/Development/Fyr
```

## One-Time Machine Setup

Run this after adding the project to Codex, after Xcode updates, or when
`make doctor` reports machine-level setup issues:

```bash
make bootstrap
```

The bootstrap script:

- Selects `/Applications/Xcode.app/Contents/Developer` with `xcode-select`.
- Accepts the Xcode license.
- Runs Xcode first-launch setup.
- Repairs `/opt/homebrew` ownership if needed.
- Installs required diagnostics/build-log tools: `libmodbus` and `xcbeautify`.
  `libmodbus` is the Homebrew dependency baseline; the separate `modpoll`
  CLI is optional and is not provided by Homebrew's `libmodbus` formula.
- Runs `make doctor` again.

It asks for sudo once at the start.

## Daily Codex Commands

```bash
make doctor
make list
make build
make test
make verify
make clean
```

`make build` and `make test` default to:

```bash
platform=iOS Simulator,name=iPhone 17
```

Use another simulator when needed:

```bash
make build DESTINATION='platform=iOS Simulator,name=iPhone 16'
```

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
Homebrew ownership, rerun:

```bash
make bootstrap
```

`make doctor` intentionally fails when these are missing, because this Mac mini
is intended to be a complete Codex workstation for Fyr rather than a partial
checkout that can only edit files.
