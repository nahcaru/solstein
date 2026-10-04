# Solstein

> Turn your phone into a Bluetooth trackpad

Solstein emulates a real Bluetooth HID device: your computer (Mac, Windows, or Linux) pairs with it like ordinary hardware — with **zero software to install on the computer**. It works from the login screen, completely offline, with no helper app required. A later optional desktop helper unlocks iOS clients and native-feeling interactive trackpad gestures.

## About the Name

Named after the **sunstone** (*sólarsteinn*) — the legendary optical crystal used by Viking navigators to locate the sun through overcast skies and dense sea fog. Just as Norse voyagers navigated their ships through invisible light, Solstein transforms your mobile screen into a precise instrument to guide your computer over invisible Bluetooth waves.

## Status

🚧 In development — see [docs/roadmap.md](docs/roadmap.md).

## Layout

```
app/     Flutter client (Android first)
helper/  Flutter desktop helper (v2)        — placeholder
docs/    Architecture, HID spec, protocol, gesture mapping, ADRs, roadmap
```

## Docs

- [Architecture](docs/architecture.md)
- [HID Report Descriptor](docs/hid-descriptor.md)
- [Gesture Mapping](docs/gesture-mapping.md) — the three-tier gesture model
- [Wire Protocol](docs/protocol.md) (v2)
- [Decisions (ADRs)](docs/decisions.md)
