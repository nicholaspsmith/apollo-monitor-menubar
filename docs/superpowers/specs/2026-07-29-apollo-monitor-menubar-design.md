# Apollo Monitor — menu-bar volume control for UAD Console

**Date:** 2026-07-29
**Status:** implemented

## Problem

The Apollo Twin MkII's monitor level can only be changed by opening UAD Console
or reaching for the hardware knob. There is no keyboard control and no menu-bar
control, because **the Apollo exposes no volume control to Core Audio at all**:

- `kAudioDevicePropertyVolumeScalar` — absent on every output element
- `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` — absent
- `osascript -e 'get volume settings'` → `output volume: missing value`

So macOS volume keys, `set volume`, and hardware-volume utilities cannot touch
it even though the Apollo is the default output device. UAD Console 3
(`com.uaudio.console3`) ships no AppleScript dictionary, and its binary contains
no volume-up/down key commands.

## The control surface we do have

`UA Mixer Engine.app` starts at login and listens on **TCP `127.0.0.1:4710`**,
speaking an undocumented path-based "StateTree" protocol. It is the same channel
UAD Console itself uses, and it listens whether or not the Console window is
open.

- Messages are `<verb> <path> [value]` terminated by a **NUL byte** (`0x00`).
  A newline terminator is silently ignored, which makes the socket look dead.
- Verbs: `get`, `set`, `subscribe`, `unsubscribe`.
- Replies are JSON: `{"path": …, "data": …}` or `{"path": …, "error": …}`.
- Round-trip latency measured at ~3 ms.

Verified paths on this rig (Apollo Twin MkII, single device):

| Path | Type | Notes |
|---|---|---|
| `/devices/0/DeviceName/value` | string | `"Apollo Twin MkII"` |
| `/devices/0/DeviceOnline/value` | bool | connected / disconnected |
| `/devices/0/outputs/4/CRMonitorLevelTapered/value` | float 0.0–1.0 | knob position |
| `/devices/0/outputs/4/CRMonitorLevel/value` | float −96.0–0.0 | dB |
| `/devices/0/outputs/4/Mute/value` | bool | |
| `/devices/0/outputs/4/DimOn/value` | bool | |

Output `4` is the one whose `Name` is `MONITOR`; it is resolved by name at
runtime, never hardcoded.

`subscribe` returns the current value immediately **and pushes on every
subsequent change** — verified by watching one socket while writing from another.
That means no polling: turning the physical knob or moving Console's fader
updates the app in real time.

## Two findings that shape the design

### 1. The engine snaps tapered values to a 1/54 grid

Setting `CRMonitorLevelTapered` to a requested value reads back as the nearest
multiple of 1/54 (≈0.018518):

| requested | read back | as fraction | dB |
|---|---|---|---|
| 0.05 | 0.055556 | 3/54 | −60.0 |
| 0.10 | 0.092593 | 5/54 | −52.0 |
| 0.15 | 0.148148 | 8/54 | −43.0 |
| 0.20 | 0.203704 | 11/54 | −35.5 |
| 0.25 | 0.259259 | 14/54 | −28.0 |
| 0.30 | 0.296296 | 16/54 | −24.0 |

So `set(read() + 0.05)` would compound the snap error on every keypress and the
20 increments would not be even.

**Therefore:** a canonical step index `0...20` is the source of truth. The app
always sends `index / 20` and never accumulates from a read-back value.

### 2. The index round-trips through the grid losslessly

For every `i` in `0...20`, `round(snap(i / 20) × 20) == i` where
`snap(x) = round(x × 54) / 54`. Checked for all 21 steps.

**Therefore:** external changes resync with `index = round(tapered × 20)`, and
the engine's snapped echo of our own writes maps back to the index we sent — no
drift, no need to distinguish our writes from someone else's. The property holds
for any grid finer than 1/40, so it does not depend on 54 being exact; 54 is what
this device reports.

## Scope

- Menu-bar icon showing monitor level, greyed when the Apollo is unreachable.
- Dropdown (real `NSMenu`) containing a status row, a **horizontal slider**,
  Mute, Dim, Start at Login, Quit.
- Global hotkeys **⌘⌥↑ / ⌘⌥↓**, 20 even increments across 0–100%.
- 0% = −96 dB (silence), 100% = 0 dB (unity) — the slider mirrors Console's knob
  position exactly, so the two can never disagree.

Out of scope: multiple Apollo devices (device 0 only), surround, cue outputs,
preamp control, a preferences window, rebindable hotkeys.

## Architecture

`~/code/apollo-monitor-menubar`, an SPM package with two targets, matching the
convention in `keylight-menubar`:

```
ApolloMonitorCore   library, no AppKit, no sockets — all logic that can be wrong
ApolloMonitor       executable, AppKit — StatusItemKit + HotkeyKit + Core
```

Dependencies are sibling checkouts (`../StatusItemKit`, `../HotkeyKit`);
HotkeyKit has no version tags, so paths rather than pinned URLs.

### ApolloMonitorCore

**`StateTree.swift`** — the wire codec.
`StateTreeCodec.get/set/subscribe` build NUL-terminated frames.
`FrameParser.append(_:) -> [StateTreeMessage]` accumulates bytes and splits on
`0x00`, decoding each complete frame. It must survive a frame split across TCP
reads and several frames arriving in one read; that is the likeliest bug in the
app, and here it is testable without a socket.

**`Paths.swift`** — path construction and the well-known property names.

**`VolumeStep.swift`** — the invariant:

```
stepCount        = 20                       index ∈ 0...20
tapered(index)   = Double(index) / 20
percent(index)   = index * 5
index(tapered:)  = clamp(round(tapered * 20), 0, 20)
next(index, dir) = clamp(index ± 1, 0, 20)
```

### ApolloMonitor

**`EngineClient`** — one long-lived `NWConnection` to `127.0.0.1:4710`.
On `.ready`: enumerate `/devices`, resolve the `MONITOR` output by name, then
`subscribe` to level, `DeviceOnline`, and `Mute`, and `get` the device name.
Sends `set /Sleep false` every 3 s as keepalive. Reconnects with 0.5 → 5 s
backoff on failure or close. Publishes `MonitorState` on the main queue.

**`VolumeSliderView`** — an `NSView` with explicit frames (`NSMenu` reads the
frame at insertion time, before any auto-layout pass — see `MenuBuilder`), a
drawn `NSSlider`, and a percent label. `mouseDown` runs its own local
event-tracking loop, because `NSMenu` tracking does not reliably deliver
continuous drags to embedded views. `hitTest` returns the container, so the click
is not swallowed by the `NSSlider` subview under the cursor first — without that
the slider's own (menu-suppressed) tracking takes the event and dragging is dead.
The position → index mapping lives in `VolumeStep.index(atX:…)` so it can be
unit-tested without a mouse, and the slider's action is wired too, which covers
VoiceOver increment/decrement. Emits only on index *change*, so a full drag sends
at most 21 writes.

Driving the value by hand also snaps it to the 21 positions without `NSSlider`'s
tick marks, which would otherwise be drawn as 21 visible notches.

**Headless mode** — `ApolloMonitor --step up|down` adjusts the level once and
exits. It uses no event tap and so needs no Accessibility permission, which makes
it both an escape hatch for binding the keys from Shortcuts or Karabiner and the
way the write path gets exercised without a UI.

**Diagnostics** — a menu-bar app has nowhere to print, so socket state, the
resolved MONITOR output, device online/offline, and every level change go to the
unified log under subsystem `com.nicholaspsmith.ApolloMonitor`.

**`main.swift`** — `StatusItemController` for icon and menu, `HotkeyTap` bound to
`.key(126, [.command, .option])` → `monitor.up` and `.key(125, …)` →
`monitor.down`, `repeatsOnHold: true`, `onMatch` returning `true` to swallow.
Reuses keylight's trust gating, `trustTimer`, and `reassertTap` tap-leapfrog
workaround.

Icon: `MeterIcon.gauge(fraction:)`, template black when live, `.systemGray` when
the Apollo is offline or the socket is down.

## Data flow

```
⌘⌥↑ → HotkeyTap.onMatch("monitor.up")
     → VolumeStep.next(state.index, .up)          // 6 → 7
     → set …/CRMonitorLevelTapered/value 0.35
     → engine snaps to 19/54 and PUSHES 0.351852
     → FrameParser → VolumeStep.index(tapered:) = 7
     → state.index = 7 → icon + slider refresh
```

External knob and Console fader moves enter at the push step and follow the
identical path, so there is exactly one source of truth.

## Error handling

| Condition | Behaviour |
|---|---|
| UA Mixer Engine not running | Grey icon; row "UA Mixer Engine not running"; slider disabled; backoff retry |
| Apollo unplugged | `DeviceOnline` → false; row "Disconnected"; slider disabled; grey icon |
| `/devices/0` missing | Treated as offline (an unplug could not be tested directly) |
| No output named `MONITOR` | Row explains; no crash |
| Accessibility not granted | Hotkeys inert; "⚠ Grant Accessibility…" row; slider still works |
| Malformed or `error` payload | Logged and ignored |

## Testing

Unit tests on Core (29 tests):

- `VolumeStep`: the 21-step round-trip against a model of the 1/54 snap grid, and
  against every other plausible grid; clamping at both ends; percent mapping;
  `next` in both directions; 20 presses crossing the full range.
- `SliderGeometry`: both track extremes reachable, centre is 50%, out-of-track
  positions clamp, a left-to-right sweep is monotonic and visits all 21 steps,
  and a degenerate zero-width track does not divide by zero.
- `StateTree`: encode appends NUL and formats floats without exponent or locale;
  parse of a frame split at *every* byte offset; several frames in one read; an
  incomplete tail held back; `error` payloads; bool not decoding as 1; the real
  `/devices/0/outputs` and output-node replies.

`EngineClient`, the slider view, and the tap are OS glue. Verified by running the
app against the live engine:

- discovery walk reaching `MONITOR resolved to output 4 on device 0` and
  `level 30% (index 6)`, matching the hardware's −22.0 dB
- the menu's items and states read back over the accessibility API, including the
  view-based slider row reporting `AXSlider(6.0)` and `AXStaticText(30%)`
- `--step down/up` moving 30 → 25 → 20 → 25 → 30% with the engine landing on
  16/54 (−24.0 dB), index 6's grid point
- the long-running instance picking up level changes written by a *separate*
  process ~40 ms later, which is the same path the hardware knob takes
- slider changes reaching the hardware: index 6 → 8 put the engine at 22/54
  (−16.0 dB)

Not verified here: a real mouse drag (the geometry is unit-tested; the event loop
is not), the reconnect path (would mean killing the engine mid-session), a
physical unplug, and the ⌘⌥↑/↓ tap itself, which cannot fire until Accessibility
is granted.

## Signing

`Resources/Info.plist` sets `LSUIElement` and `com.nicholaspsmith.ApolloMonitor`.
`scripts/build-app.sh` delegates to `../StatusItemKit/scripts/make-app.sh`.

Run `../StatusItemKit/scripts/setup-signing.sh` **once**: ad-hoc signatures get a
new code hash on every rebuild and macOS keys the Accessibility grant to that
hash, so without a stable identity the app must be re-approved after every
build.

## Notes

- `ApolloMonitor --step up|down` needs no Accessibility; the tap-based hotkeys do.
- ⌘⌥↑/↓ are swallowed globally and will shadow any app-specific binding on those
  keys.
- `~/.local/bin/ua-monitor` (Python CLI, same protocol) stays for scripting. The
  app does not call it.
- The protocol is undocumented and unsupported; a UA update could change it.
