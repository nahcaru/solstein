# Helm

Turn your Android phone (iPhone planned) into a Bluetooth trackpad + keyboard for your Mac — no software to install on the computer.

Helm emulates a real Bluetooth HID device: your Mac (or Windows/Linux machine) pairs with it like ordinary hardware. It works from the login screen, offline, with no helper app. A later optional desktop helper unlocks iOS clients and native-feeling interactive trackpad gestures.

## Status

🚧 Design phase — see [docs/roadmap.md](docs/roadmap.md).

## Layout

```
app/     Flutter client (Android first)     — not yet scaffolded, see CLAUDE.md Bootstrap
helper/  Flutter desktop helper (v2)        — placeholder
docs/    Architecture, HID spec, protocol, gesture mapping, ADRs, roadmap
```

## Docs

- [Architecture](docs/architecture.md)
- [HID Report Descriptor](docs/hid-descriptor.md)
- [Gesture Mapping](docs/gesture-mapping.md) — the three-tier gesture model
- [Wire Protocol](docs/protocol.md) (v2)
- [Decisions (ADRs)](docs/decisions.md)
