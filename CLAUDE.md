# Helm

## Purpose

Android app (iPhone in v3) that acts as a Bluetooth trackpad + keyboard for macOS — and Windows/Linux for free — with **zero software installed on the computer** in v0.1.

## Tech Stack

- **Flutter (Dart)**: client UI + gesture engine; raw pointer events via `Listener` for trackpad-grade latency
- **Kotlin platform channel**: `BluetoothHidDevice` HID transport (no Flutter plugin exists for the HID Device profile)
- **Flutter desktop** (v2 helper): macOS/Windows/Linux; per-OS input injection via FFI (`CGEvent` / `SendInput` / `uinput`)

## Key Constraints

- minSdk 28 (`BluetoothHidDevice` requires API 28); permissions `BLUETOOTH_CONNECT/SCAN/ADVERTISE` on API 31+
- HID transport runs in a foreground service (`connectedDevice` type)
- iOS **cannot** be a BT HID peripheral → iOS client is BLE + helper only (v3)
- Wire protocol streams **phased gesture events from v1** — never collapse to discrete flags in the protocol (Tier 3 depends on this)
- Interactive gesture scrubbing (Tier 3) uses private macOS APIs: must be version-gated with auto-fallback to shortcuts

## Coding Guidelines

- Gesture engine is **pure Dart** — no platform imports; deterministic `List<PointerSample> → List<InputEvent>`
- All transports implement `InputSink` and declare `capabilities`; UI adapts, never branches on transport type
- Always send release-all HID reports on disconnect/pause (stuck-key prevention)
- Unit tests required for: gesture engine, HID report byte encoding, protocol encode/decode round-trips
- HID report payloads exclude the report ID byte (Android's `sendReport` prepends it)

## Architecture Overview

Four layers: Flutter UI → Gesture Engine (pure Dart) → `InputSink` interface → transports. v0.1 ships `HidTransport` (Kotlin, phone emulates a combo HID mouse+keyboard; gestures fire as shortcut key reports). v2 adds `BleTransport` (phone = GATT server) plus a Flutter desktop helper that injects input natively. See `docs/architecture.md`, `docs/hid-descriptor.md`, `docs/protocol.md`.

## Bootstrap (repo not yet scaffolded)

Flutter SDK is not on PATH on this machine. First implementation session:

```bash
cd app && flutter create --org dev.taira --project-name helm --platforms android .
```

<!-- 設計検討の経緯・思考プロセス: Obsidian Vault の Projects/Helm/ を参照 -->
