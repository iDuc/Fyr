# Fyr Project Overview

> *Laatst bijgewerkt: 2 februari 2026*

---

## 1. Wat is Fyr?

Fyr is een **native iOS app** om DRU gashaarden draadloos te bedienen. De app communiceert rechtstreeks met de Honeywell WiFi-bridge die in de haard zit, via het industriële ModbusTCP protocol.

**Kernfilosofie:** 100% lokaal. Geen cloud, geen account, geen externe servers. Alles blijft op je eigen netwerk.

**Wat kun je ermee?**
- Haard aan/uit zetten
- Vlamhoogte regelen (0-100%)
- Temperatuur instellen (thermostaat)
- Eco/Wave modus activeren (automatisch variërende vlam)
- Status monitoren via home screen widget
- Siri spraakcommando's in Nederlands én Engels

De naam "Fyr" is Noors voor "vuur" — kort, krachtig, en past bij de Scandinavische minimalistische UI.

---

## 2. Tech Stack

| Component | Technologie |
|-----------|-------------|
| **Taal** | Swift 6.0 |
| **UI Framework** | SwiftUI |
| **Minimum iOS** | iOS 26.0+ |
| **IDE** | Xcode 17.0+ |
| **Networking** | Network.framework (native TCP) |
| **Protocol** | ModbusTCP |
| **Concurrency** | Swift Actors (thread-safe) |
| **Persistence** | UserDefaults + App Groups |
| **Voice** | App Intents (Siri) |
| **Design** | iOS 26 Liquid Glass design language |

### Architectuur

```
Fyr/
├── App/                 # App entry point
├── Core/
│   ├── Networking/      # ModbusTCP client (actor-based)
│   ├── DRU/             # Register map, discovery, rate limiter
│   ├── Persistence/     # Settings storage
│   └── DesignSystem/    # Kleuren, spacing, animaties
├── Models/              # Fireplace, FireplaceStatus, errors
├── Features/
│   ├── Dashboard/       # Hoofdscherm met controls
│   ├── Settings/        # Bridge IP configuratie
│   └── Onboarding/      # Setup wizard
├── Intents/             # 6 Siri App Intents
├── Components/          # Flame indicator, sliders
└── FyrWidget/           # Home screen widget
```

---

## 3. Hoe werkt de Modbus Integratie?

### Protocol Basics

De Honeywell BRDG-03EM01 bridge spreekt **ModbusTCP** — een industrieel protocol voor apparaatcommunicatie.

| Parameter | Waarde |
|-----------|--------|
| **Poort** | 502 |
| **Slave ID** | 2 (standaard, kan afwijken!) |
| **Function Codes** | 0x03 (read), 0x06 (write single), 0x10 (write multiple) |

### Belangrijke Registers

| Register | Beschrijving | Type |
|----------|--------------|------|
| **40200** | Action command values (101 aan, 3 uit, 105 wave aan, 7 wave uit) | Write |
| **40201** | Vlamhoogte target (0-100%) | Write |
| **40203** | Status bitmap | Read |
| **40204** | Foutcode (F01, F02, etc.) | Read |
| **40205** | Gateway RSSI | Read |
| **40206** | Fireplace RSSI | Read |
| **40207** | Temperatuur (÷10 voor °C) | Read |
| **40250** | Thermostaat setpoint | R/W |
| **40220** | Wave interval (1-60 sec) | R/W |

### Rate Limiting (Kritiek!)

| Operatie | Minimum interval |
|----------|------------------|
| Register reads | 3 seconden |
| Vlam hoogte wijziging | **10 seconden** (regelgeving!) |
| Algemene writes | 3 seconden |
| Wave pattern opslaan | **1x per dag** (EEPROM limiet) |

### Connection Flow

```
1. TCP connect naar bridge:502
2. Wacht 1500ms (bridge startup delay)
3. Poll elke 15s met exponential backoff bij fouten
4. Keepalive elke 30s
5. Timeout na 30s, retry 3x
```

### Bekende Problemen

Uit `MODBUS_TROUBLESHOOTING.md`:

1. **Slave ID kan afwijken** — Standaard is 2, maar kan ook 1, 3, of 207 zijn (afhankelijk van installatie)
2. **Address offset ambiguïteit** — Register 40203 kan address 202 óf 203 zijn (twee conventies)
3. **Enkele connectie** — Bridge accepteert maar 1 TCP verbinding tegelijk

---

## 4. HomeKit Setup

### Huidige Status: Geen echte HomeKit integratie

De app heeft momenteel **Siri App Intents**, maar géén native HomeKit accessory functionaliteit.

### Siri Commando's (6 intents)

| Intent | Nederlandse phrases |
|--------|---------------------|
| TurnOn | "Zet de openhaard aan", "Steek het vuur aan" |
| TurnOff | "Zet de openhaard uit" |
| SetFlameHeight | "Zet de vlammen op 10" |
| SetTemperature | "Zet de haard op 22 graden" |
| ToggleEcoMode | "Activeer wave-modus" |
| GetStatus | "Wat is de status van de haard?" |

### Toekomstige HomeKit (uit PRD)

De documentatie beschrijft een **gewenste** HomeKit integratie via de [HAP library](https://github.com/Bouke/HAP):

```
Gewenste HomeKit services:
- HMServiceTypeSwitch (aan/uit)
- HMServiceTypeThermostat (temperatuur)
- HMServiceTypeTemperatureSensor (huidige temp)
- HMServiceTypeLightbulb (sfeerverlichting, indien aanwezig)
```

Dit is **nog niet geïmplementeerd**.

---

## 5. Huidige Status

### ✅ Compleet

- Swift project architectuur
- ModbusTCP client (actor-based, thread-safe)
- DRU register mapping
- Bridge discovery (netwerk scan)
- Rate limiting
- Dashboard UI met liquid glass design
- Flame height slider met eco indicator
- Ignition slider (swipe-to-ignite)
- 6 Siri App Intents (NL + EN)
- Home screen widget
- Onboarding wizard
- Compatibility checker (27 modellen)
- Error code mapping (F01-F08)

### ⚠️ Onderzocht maar niet opgelost

- **Modbus exception errors** (Illegal Data Address 0x02) — Slave ID en address offset issues zijn gedocumenteerd maar het is onduidelijk of dit opgelost is

### ❌ Niet geïmplementeerd

- Echte HomeKit accessory server (HAP integratie)
- Multi-fireplace support
- Energieverbruik statistieken
- Scheduled automations

---

## 6. Hardware Requirements

### Vereist

| Component | Model | Notities |
|-----------|-------|----------|
| **WiFi Bridge** | Honeywell BRDG-03EM01 | Oudere RCH control system |
| **RCH Receiver** | DFGT V04+ | In de haard |
| **Netwerk** | Ethernet | Bridge moet bekabeld aan router |

### Ondersteunde DRU Modellen (27 totaal)

| Serie | Modellen |
|-------|----------|
| **Maestro** | 60, 75, 80, 100, 105 varianten (13 modellen) |
| **Metro** | 100XT, 130XT, 150XT, 200XT varianten (12 modellen) |
| **Lugo** | 80/2, 80/3 (2 modellen) |

### ❌ Niet Ondersteund

- DRU Global series (geen RCH control)
- DRU Diablo series (geen RCH control)
- DRU Virtuo elektrische haarden (alleen Bluetooth)
- Nieuwere Bluetooth-only RCH modellen (geen WiFi bridge)

### Test Commando's

```bash
# Check bridge bereikbaarheid
nc -zv <BRIDGE_IP> 502

# Lees status registers met modpoll als die CLI los is geinstalleerd
modpoll -m tcp -a 2 -r 203 -c 5 <BRIDGE_IP>

# Test alternatieve slave IDs
for SLAVE in 1 2 3 207; do
  modpoll -m tcp -a $SLAVE -r 203 -c 1 <BRIDGE_IP>
done
```

---

## 7. Open Vragen

### Technisch

1. **Is het Modbus connectiviteitsprobleem opgelost?**
   - De troubleshooting doc beschrijft "Illegal Data Address" errors
   - Slave ID scanning en address offset fixes zijn voorgesteld, maar is dit getest?

2. **Wat is de daadwerkelijke slave ID bij jullie installatie?**
   - Standaard is 2, maar community meldt ook 1, 3, of 207

3. **Werkt de app met echte hardware?**
   - Is er een werkende test setup?

### Product

4. **HomeKit integratie — nog steeds gewenst?**
   - PRD beschrijft het als feature, maar het is niet geïmplementeerd
   - Zou de app in de App Store als HAP bridge kunnen draaien?

5. **Multi-fireplace support — relevant?**
   - Heeft iemand meerdere DRU haarden in één huis?

6. **Release planning?**
   - Is dit voor persoonlijk gebruik of publieke release?
   - App Store vs TestFlight vs alleen development?

### Hardware

7. **Test hardware beschikbaar?**
   - Welk DRU model staat er?
   - Bridge versie/firmware?

---

## Quick Links

- **Code:** `/Volumes/DAS_mini/Development/Fyr/`
- **GitHub:** [iDuc/Fyr](https://github.com/iDuc/Fyr)
- **Compatibility:** `COMPATIBILITY.md`
- **Troubleshooting:** `MODBUS_TROUBLESHOOTING.md`
- **PRD:** `docs/DRU-HomeKit-App-PRD.md`
- **Tech Ref:** `docs/DRU-HomeKit-Technical-Reference.md`

---

*Generated by Katt 🐱 — Fyr project exploration*
