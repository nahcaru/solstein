# Helm Wire Protocol v1 (BLE GATT — v2 feature)

Phone = GATT **server** (peripheral); helper = **central**. Desktop initiates reconnects; one phone can serve multiple desktops later.

## Service layout

| Item | UUID | Properties |
|---|---|---|
| Helm Service | `bc238100-4863-464c-8835-090cf15967a6` | — |
| Input | `bc238101-…` (same base) | Notify (phone → helper), binary packets |
| Control | `bc238102-…` (same base) | Write (helper → phone): target OS, capability negotiation, haptic cues |
| Info | `bc238103-…` (same base) | Read: protocol version, device name |

Base UUID `bc2381xx-4863-464c-8835-090cf15967a6`; byte 3 (`xx`) indexes the attribute (00 = service).

## Packet format

Binary, little-endian, ≤ 20 B (BLE 4.2 floor; negotiate larger MTU when available).

```
byte 0: type   1=PointerMove 2=Button 3=Scroll 4=Key 5=GesturePhase
               8=PointerAbsolute
byte 1: seq    wrap-around counter (loss detection only; no retransmit)
payload:
  PointerMove:  int16 dx, int16 dy
  Button:       u8 button, u8 down
  Scroll:       int16 dx, int16 dy
  Key:          u8 usage, u8 modifiers, u8 down
  GesturePhase: u8 kind, u8 phase(0 began,1 changed,2 ended,3 cancelled),
                u16 progress (0–65535 ≙ 0.0–1.0), int16 velocity
  PointerAbsolute: u16 x, u16 y  (0–65535 ≙ 0.0–1.0 of the host's desktop)
```

Type 8 is reserved for absolute pointing by a v2 helper (presenter mode's spotlight, ADR-007/008); 6 and 7 are held for the v1 keyboard work (`MediaTap`, `Text`).

**Invariant: `PointerAbsolute` stays normalized on the wire.** The HID transport quantizes to its descriptor's 0…32767 grid; a helper injecting natively multiplies by its own screen size. Neither resolution belongs in the packet. A helper that cannot position absolutely must drop the packet, never synthesize a relative delta from it (see ADR-007).

**Invariant: `GesturePhase` stays in the protocol even while helpers only consume it discretely.** Tier 3 (interactive scrubbing) must be deployable as a helper-only upgrade.

## QoS

- Coalesce pointer/scroll/phase to ≤ ~90 Hz, latest-wins under congestion.
- Coalesce `PointerAbsolute` latest-wins and **never accumulate**: summing positions is meaningless, and under congestion the newest position is the only correct one.
- Never drop Button/Key packets.
- Request 7.5–15 ms connection interval.

## Security

- BLE bonding required (numeric comparison preferred, Just Works minimum).
- App-layer session token exchanged via Control characteristic on first pairing; helper rejects un-approved phones. An input device is a keystroke injector — treat pairing as a security boundary.
