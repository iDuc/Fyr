# Register dump — 25 October 2026

**Result: not performed. No Modbus request reached the bridge.**

## What was tried

- Bridge address: taken from the project's git history (the address used in
  the v1 troubleshooting notes). It is a personal network detail, so it is not
  repeated here. It is on the Mac mini's own subnet (/24, `en0`/`en1`).
- Tool: `scripts/modbus-readonly-dump.py` (this branch). It only ever sends
  function code 0x03 (hard-asserted before sending), opens one TCP connection at
  a time, waits ≥ 3.2 s between requests and 1.5 s after connecting, and closes
  the connection at the end. Plan: unit 2, registers 40200–40250 in three
  address conventions (PDU 200 = 40200−40000, PDU 199 = 40200−40001, and the raw
  register number 40200 that Fyr v1 uses); units 1/3/207 only if unit 2 fails.
- Run at 13:56 from the Mac mini. Raw log (no IP in it):

```
[13:56:48] unit 2 pdu-200 (40200-40000, register 40203 -> 203): read 51 @ 200
[13:56:48] connect failed: OSError(65, 'No route to host')
[13:56:48] retrying connect in 5s
[13:56:53] connect failed: OSError(65, 'No route to host')
[13:56:53] retrying connect in 15s
```

The run was stopped by hand after the second failure. No TCP connection was
ever opened, so nothing was read or written.

## Why it failed

This was not the bridge and not the DRU app holding the connection slot. From
this agent's process tree, **every** LAN address fails immediately with
`EHOSTUNREACH`, including the router (`ping` and `curl` to the gateway fail the
same way). The routing table is correct (`route get` resolves to `en0`) and
internet access works. That pattern is macOS **Local Network privacy** denying
the app the agent runs under (the `claude` CLI via node), not a network fault.
Granting that permission needs a person in System Settings, so the agent did
not try to work around it.

## How to run it (Richard, ~2 minutes)

From a Terminal window that has Local Network access (System Settings → Privacy
& Security → Local Network → enable Terminal/Ghostty), on the home LAN:

```bash
cd /Volumes/ThunderSloerie/Development/Fyr
python3 -I scripts/modbus-readonly-dump.py <BRIDGE_IP> /Volumes/ThunderSloerie/BuildArtifacts/Fyr/register-dump/dump-$(date +%F-%H%M).json
```

Close the DRU app first. Ideally run it three times and note the fire's state
each time: **off**, **on**, and **on + wave mode**. Each run takes about 30
seconds when the bridge answers, or a few minutes if it backs off.

## What the dump will decide

- Which address convention the bridge accepts. Fyr v1 (and this branch by
  default) sends register numbers (40203 → PDU 40203); `DRUAddressing` also
  supports 202/203.
- Whether the status bits match v1's observed values: `0x3C00` off, `0xB804` on,
  `0xBA04` on + wave (bit 9). Until then, "on" stays v1's rule (anything except 0
  and `0x3C00`).
- Whether the response unit id echoes the request (the client checks the
  transaction id strictly and only logs a unit id mismatch).
- Whether any register in 40200–40250 reports the actual flame height (40201
  is write-only; Fyr persists the last value it set).
- Whether 40250 (thermostat) exists on the Metro 100XT.
