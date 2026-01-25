# Fyr - DRU Fireplace Control App

A modern iOS app to control DRU fireplaces via ModbusTCP, with full Siri integration.

## Features

- **Full Fireplace Control**: On/off, flame height (0-15), temperature setpoint, eco mode
- **Siri Voice Commands**: "Hey Siri, turn on the fireplace"
- **Home Screen Widget**: Monitor status at a glance
- **Apple-Native Design**: Minimalistic UI following iOS design language
- **100% Local**: No cloud services, all communication stays on your network
- **Full Accessibility**: VoiceOver, Dynamic Type support

## Compatibility

Fyr works with DRU gas fireplaces that have the **Honeywell BRDG-03EM01 WiFi bridge**.

### Supported Fireplaces

| Series | Models | App Control |
|--------|--------|-------------|
| **Maestro** | 60, 75, 80, 100, 105 variants | All Eco Wave models |
| **Metro** | 100XT, 130XT, 150XT, 200XT variants | All Eco Wave models |
| **Lugo** | 80/2, 80/3 | All Eco Wave models |

### Not Supported

- DRU Global series (no app control)
- DRU Diablo series (no app control)
- DRU Virtuo electric fires (Bluetooth only)
- Newer Bluetooth-only RCH models (no WiFi bridge)

For the complete list of 27 compatible models, see [COMPATIBILITY.md](COMPATIBILITY.md).

## Requirements

- iOS 26.0+
- Xcode 17.0+
- Swift 6.0
- DRU fireplace with Honeywell BRDG-03EM01 bridge

## Xcode Project Setup

Since the Swift source files are provided without an Xcode project, follow these steps:

### 1. Create New Xcode Project

1. Open Xcode
2. File → New → Project
3. Choose "App" under iOS
4. Configure:
   - **Product Name**: Fyr
   - **Team**: Your development team
   - **Organization Identifier**: com.yourname (e.g., com.richard)
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: None
5. Save in the `Fyr` directory (replace the generated files)

### 2. Add Existing Source Files

1. In Xcode, right-click on the `Fyr` folder in the navigator
2. Choose "Add Files to Fyr..."
3. Navigate to the `Fyr/Fyr` folder
4. Select all folders: `App`, `Core`, `Models`, `Features`, `Intents`, `Components`
5. Ensure "Create groups" is selected
6. Click "Add"

### 3. Add Widget Extension

1. File → New → Target
2. Choose "Widget Extension"
3. Configure:
   - **Product Name**: FyrWidget
   - **Include Configuration App Intent**: No
4. Add the widget source files from `FyrWidget` folder

### 4. Configure App Groups

1. Select the Fyr project in the navigator
2. Select the Fyr target
3. Go to "Signing & Capabilities"
4. Click "+ Capability" → "App Groups"
5. Add: `group.com.fyr.app`
6. Repeat for the FyrWidget target

### 5. Configure Siri Capability

1. Select the Fyr target
2. Go to "Signing & Capabilities"
3. Click "+ Capability" → "Siri"

### 6. Update Info.plist

Add the following to your Info.plist:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Fyr needs local network access to communicate with your DRU fireplace bridge.</string>

<key>NSBonjourServices</key>
<array>
    <string>_modbus._tcp</string>
</array>
```

### 7. Set Deployment Target

1. Select the Fyr project
2. Under "General", set Minimum Deployments to iOS 26.0

### 8. Build and Run

1. Connect your iPhone
2. Select your device as the run destination
3. Build and run (⌘R)

## Project Structure

```
Fyr/
├── Fyr/
│   ├── App/                    # App entry point
│   ├── Core/
│   │   ├── Networking/         # ModbusTCP client
│   │   ├── DRU/                # DRU-specific logic
│   │   └── Persistence/        # Settings storage
│   ├── Models/                 # Data models
│   ├── Features/
│   │   ├── Dashboard/          # Main control view
│   │   ├── Settings/           # Settings view
│   │   └── Onboarding/         # Setup wizard
│   ├── Intents/                # Siri App Intents
│   └── Components/             # Reusable UI components
├── FyrWidget/                  # Home screen widget
├── docs/                       # Technical documentation
└── README.md
```

## Siri Commands

After setup, these commands work automatically:

| Command | Example Phrases |
|---------|-----------------|
| Turn On | "Turn on the fireplace", "Light the fire" |
| Turn Off | "Turn off the fireplace", "Stop the fire" |
| Flame Height | "Set flame to 10", "Set fireplace to level 5" |
| Temperature | "Set fireplace to 22 degrees" |
| Eco Mode | "Enable eco mode", "Turn off eco mode" |
| Status | "What's the fireplace status", "Is the fireplace on" |

## Hardware Setup

### Honeywell Bridge Configuration

1. Ensure your BRDG-03EM01 bridge is connected to your WiFi network
2. Note the bridge's IP address from your router's DHCP client list
3. Recommended: Set up a DHCP reservation for consistent IP address

### Testing Bridge Connectivity

```bash
# Test if bridge is reachable
nc -zv <BRIDGE_IP> 502

# If you have modpoll installed (brew install libmodbus)
modpoll -m tcp -a 2 -r 203 -c 5 <BRIDGE_IP>
```

## Technical Details

### DRU Modbus Registers

| Register | Description |
|----------|-------------|
| 40200 | Action (write) - 9-bit bitmap |
| 40203 | Status (read) - 16-bit bitmap |
| 40204 | Error code (read) |
| 40205 | Flame height (read) - 0-15 |
| 40207 | Temperature (read) - scaled by 10 |
| 40250 | Thermostat setpoint (read/write) |
| 40251 | Flame height target (read/write) |

### Rate Limiting

- Minimum 10 seconds between register reads
- Minimum 10 seconds between flame height changes (regulatory requirement)
- Errors must be reset manually via the physical remote control

## Troubleshooting

### "Could not connect to bridge"
- Verify bridge is powered on
- Check bridge IP address
- Ensure iPhone is on same WiFi network
- Try: `nc -zv <BRIDGE_IP> 502`

### "Flame height not changing"
- Wait 10 seconds between changes (rate limited)
- Check if fireplace is actually on

### "Error F01/F02/F03..."
- Press up (∧) and down (∨) buttons simultaneously on remote to reset
- See error descriptions in app for details

## License

MIT License - see [LICENSE](LICENSE) for details.

## Disclaimer

This project is not affiliated with, endorsed by, or connected to DRU, Honeywell, or any of their subsidiaries. DRU and Honeywell are trademarks of their respective owners. Use at your own risk.
