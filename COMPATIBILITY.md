# Fyr Compatibility Guide

This document details which DRU fireplaces are compatible with the Fyr app.

## Requirements

Fyr requires three things to work:

1. **A compatible DRU fireplace** from the Maestro, Metro, or Lugo series with Eco Wave
2. **The Honeywell WiFi bridge** (model BRDG-03EM01)
3. **Both devices on the same network** - your iPhone and the bridge must be on the same WiFi network

## How It Works

Fyr communicates with your fireplace using ModbusTCP, the same protocol as the official DRU Fireplace app. The Honeywell bridge connects to your home router via Ethernet and translates commands to the fireplace's RCH (Remote Control Honeywell) receiver.

```
iPhone (Fyr app)
    ↓ WiFi
Home Router
    ↓ Ethernet
Honeywell BRDG-03EM01 Bridge
    ↓ RF Signal
RCH Receiver (DFGT V04+)
    ↓
DRU Fireplace
```

## Compatible DRU Fireplaces

### Maestro Series (13 models)

| Model | Viewing | Compatible |
|-------|---------|------------|
| Maestro 60 Eco Wave | Single-sided | Yes |
| Maestro 60/2 Eco Wave | 2-sided | Yes |
| Maestro 60/3 Eco Wave | 3-sided | Yes |
| Maestro 75 Eco Wave | Single-sided | Yes |
| Maestro 75 Tall Eco Wave | Single-sided, tall | Yes |
| Maestro 75 Tunnel Eco Wave | See-through | Yes |
| Maestro 75 Tunnel Tall Eco Wave | See-through, tall | Yes |
| Maestro 75XTU Eco Wave | Extra tall unit | Yes |
| Maestro 80/2 Eco Wave | 2-sided | Yes |
| Maestro 80/3 Eco Wave | 3-sided | Yes |
| Maestro 100 Eco Wave | Single-sided | Yes |
| Maestro 105/2 Eco Wave | 2-sided | Yes |
| Maestro 105/3 Eco Wave | 3-sided | Yes |

### Metro Series (12 models)

| Model | Viewing | Compatible |
|-------|---------|------------|
| Metro 100XT Eco Wave | Single-sided | Yes |
| Metro 100XT/2 Eco Wave | 2-sided | Yes |
| Metro 100XT/3 Eco Wave | 3-sided | Yes |
| Metro 100XT Tunnel Eco Wave | See-through | Yes |
| Metro 130XT Eco Wave | Single-sided | Yes |
| Metro 130XT/2 Eco Wave | 2-sided | Yes |
| Metro 130XT/3 Eco Wave | 3-sided | Yes |
| Metro 130XT Tunnel Eco Wave | See-through | Yes |
| Metro 150XT Eco Wave | Single-sided | Yes |
| Metro 150XT Tunnel Eco Wave | See-through | Yes |
| Metro 200XT Eco Wave | Single-sided | Yes |
| Metro 200XT Tunnel Eco Wave | See-through | Yes |

### Lugo Series (2 models)

| Model | Viewing | Compatible |
|-------|---------|------------|
| Lugo 80/2 Eco Wave | 2-sided | Yes |
| Lugo 80/3 Eco Wave | 3-sided | Yes |

## Not Compatible

The following DRU products are **not compatible** with Fyr:

### DRU Global Series
- Global 40, 55XT, 70XT, 100, 120
- **Reason:** Basic gas fires without RCH control or app functionality

### DRU Diablo Series
- Diablo, Diablo Next
- **Reason:** Hanging gas stoves without RCH control

### DRU Virtuo Electric Fires
- Virtuo Evolve 70 / 100 / 130
- **Reason:** Uses Bluetooth only, different communication protocol

### Newer Bluetooth-Only RCH
- DRU is transitioning some models to Bluetooth-only control
- These models don't use the WiFi bridge
- **Reason:** No WiFi bridge support

### Models Without "Eco Wave"
- If your fireplace model name doesn't include "Eco Wave", it may lack app control features
- Check your documentation or contact your dealer

## The Honeywell WiFi Bridge

### What is it?

The Honeywell BRDG-03EM01 is an Ethernet-to-RF bridge that connects your home network to the fireplace's RCH receiver. It's often sold as an optional accessory or included with premium fireplace packages.

### Specifications

- **Model Number:** BRDG-03EM01
- **Connection:** Ethernet (RJ45) to router
- **Protocol:** ModbusTCP on port 502
- **Power:** External adapter (included)
- **RF Frequency:** Communication with RCH receiver

### Do I Have One?

Look for a small white or grey box near your fireplace or router with:
- An Ethernet cable going to your router
- A power adapter
- LED status lights

If you're unsure, check with your DRU dealer or installer.

### Where to Get One

The WiFi bridge is sold by DRU dealers. Contact your local DRU representative or the dealer who installed your fireplace. Note that availability may vary as DRU transitions to Bluetooth-only models.

## RCH Receiver Compatibility

The RCH (Remote Control Honeywell) receiver inside your fireplace must be version DFGT V04 or newer to support the WiFi bridge. This is typically included in all Eco Wave models manufactured since the feature was introduced.

## Troubleshooting

### "Cannot find bridge"

1. **Check Ethernet connection** - Ensure the bridge is connected to your router with an Ethernet cable
2. **Power cycle** - Unplug the bridge power, wait 10 seconds, plug back in
3. **Check router** - Verify the bridge appears in your router's DHCP client list
4. **Same network** - Make sure your iPhone is on the same WiFi network as the router the bridge is connected to

### "Connection failed"

1. **Check IP address** - Verify you're using the correct IP address for the bridge
2. **Port 502** - ModbusTCP uses port 502; ensure nothing is blocking it
3. **Single connection** - The bridge only supports one connection at a time. Close other apps that might be connected.
4. **DHCP reservation** - Set up a DHCP reservation in your router to prevent IP changes

### "Official DRU app works, but Fyr doesn't"

1. **Single connection limit** - Close the official DRU app completely
2. **Wait** - The bridge may need 30-60 seconds between connections
3. **Check IP** - The IP address may have changed; re-scan in Fyr

### "Commands don't work"

1. **Rate limiting** - Wait 10 seconds between commands (especially flame height changes)
2. **Check error codes** - Look for error codes (F01, F02, etc.) on your fireplace display
3. **Reset errors** - Press up (∧) and down (∨) on the remote simultaneously to clear errors

## Testing Bridge Connectivity

You can test if your bridge is reachable from your Mac or Linux machine:

```bash
# Test if bridge is reachable
nc -zv <BRIDGE_IP> 502

# Example output if successful:
# Connection to 192.168.1.100 port 502 [tcp/asa-appl-proto] succeeded!
```

If you have `modpoll` installed (via Homebrew: `brew install libmodbus`):

```bash
# Read status registers
modpoll -m tcp -a 2 -r 203 -c 5 <BRIDGE_IP>
```

## Quick Compatibility Check

Answer these questions to determine if Fyr will work for you:

1. **Is your fireplace a DRU Maestro, Metro, or Lugo?**
   - If no: Fyr won't work
   - If yes: Continue

2. **Does the model name include "Eco Wave"?**
   - If no: Likely won't work (check documentation)
   - If yes: Continue

3. **Do you have the Honeywell WiFi bridge (BRDG-03EM01)?**
   - If no: You'll need to purchase one
   - If yes: Continue

4. **Is the bridge connected via Ethernet to your router?**
   - If no: Connect it
   - If yes: Fyr should work!

## Getting Help

- **DRU Official Website:** [www.dru.nl](https://www.dru.nl)
- **DRU App Support:** Contact your local DRU dealer
- **Fyr Issues:** [GitHub Issues](https://github.com/your-repo/fyr/issues)

## Disclaimer

Fyr is an independent app not affiliated with DRU or Honeywell. Compatibility information is based on research and user reports. Always consult your dealer for official support.
