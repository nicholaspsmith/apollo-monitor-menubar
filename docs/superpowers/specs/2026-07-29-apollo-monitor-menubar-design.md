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

### 2. Nothing needs to accumulate, so the snap cannot cause drift

An earlier revision carried a canonical step index `0...20` to stop repeated
`set(read() + delta)` from compounding the snap error. That machinery is gone: the
volume keys compute an absolute dB from the current level, and the slider computes
an absolute position from the mouse. Neither adds to a value it read back, so there
is nothing to drift.

The snap still matters for *display*: a write of 26% comes back as 14/54, and the
slider shows the returned value rather than the requested one, so it always agrees
with Console.

## Scope

- Menu-bar icon showing monitor level, greyed when the Apollo is unreachable.
- Dropdown (real `NSMenu`) containing a status row, a **horizontal slider**,
  Mute, Dim, Start at Login, Quit.
- The Mac's **volume up/down keys** remapped to the monitor level, **1 dB per
  press**. (⌘⌥↑/↓ was the first attempt; it collided with Rectangle, and the volume
  keys are the better gesture anyway since macOS can only offer a greyed-out slider
  for a device with no Core Audio volume.)
- A **volume overlay** replacing the system HUD the swallowed key suppresses.
- The slider shows the **continuously reported** knob position and writes whole
  percents, mirroring Console's knob; the keys are the fine control.
- 0% = −96 dB (silence), 100% = 0 dB (unity) — the slider mirrors Console's knob
  position exactly, so the two can never disagree.

Out of scope: multiple Apollo devices (device 0 only), surround, cue outputs,
preamp control, a preferences window, rebindable hotkeys.

### 3. dB is the fine control; tapered is only a coarse report

`CRMonitorLevel` accepts and stores arbitrary values, while
`CRMonitorLevelTapered` stays pinned to its 1/54 grid across the same span:

| set dB | read dB | read tapered | ×54 |
|---|---|---|---|
| −30.00 | −30.00 | 0.259259 | 14.00 |
| −29.50 | −29.50 | 0.259259 | 14.00 |
| −29.10 | −29.10 | 0.259259 | 14.00 |
| −28.00 | −28.00 | 0.259259 | 14.00 |
| −27.25 | −27.25 | 0.277778 | 15.00 |

**Therefore:** stepping happens in dB, not through the tapered ladder. One grid
step is ~2 dB at normal listening levels, so a 1 dB step is ~0.9% of knob travel —
finer than a whole percentage point, which 55 hardware positions cannot express.
The tapered value is still read, for the slider's position.

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

**`LevelDb.swift`** — the fine unit: clamping to −96…0 and whole-dB stepping that
floors before stepping up (and ceils before stepping down), so a fractional level
left by the hardware knob lands on the integer ladder rather than carrying its
fraction forever. Non-finite input falls to −96, never 0 — defaulting the wrong way
would mean a stray value slamming the monitors to unity.

**`KnobPosition.swift`** — knob travel as a percentage, plus the drag geometry:

```
percent(tapered:)   = clamp(round(tapered * 100), 0, 100)   // display
tapered(percent:)   = percent / 100                         // writes, rounded to 1%
percent(atX:trackMinX:trackWidth:knobInset:)                // mouse → percent
```

The track is inset by half a knob width at each end so the knob's centre can reach
both extremes; without it the last half-knob of travel is unreachable and 100%
cannot be selected by mouse.

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
The position → percent mapping lives in `KnobPosition.percent(atX:…)` so it can be
unit-tested without a mouse, and the slider's action is wired too, which covers
VoiceOver increment/decrement. Emits only on whole-percent *change*, so a full drag
sends at most 101 writes. External updates are ignored while tracking: the engine
echoes a snapped value within milliseconds of each write, and applying it under the
cursor would pull the knob out from under the user.

Driving the value by hand also snaps it to the 21 positions without `NSSlider`'s
tick marks, which would otherwise be drawn as 21 visible notches.

**Headless mode** — `ApolloMonitor --step up|down` adjusts the level once and
exits. It uses no event tap and so needs no Accessibility permission, which makes
it both an escape hatch for binding the keys from Shortcuts or Karabiner and the
way the write path gets exercised without a UI.

**`VolumeHUD`** — a borderless, non-activating `NSPanel` at `.statusBar` level
that ignores mouse events, joins all spaces, and sits above full-screen apps. Shows
device name, a level bar (knob travel) and the exact dB, top-right below the menu
bar where macOS puts its own, fading after 1.4 s. Driven by the *level* rather than
the keypress, so the hardware knob and Console's fader raise it too; suppressed for
~1 s after a menu-slider drag, which is already its own feedback.

**Diagnostics** — a menu-bar app has nowhere to print, so socket state, the
resolved MONITOR output, device online/offline, and every level change go to the
unified log under subsystem `com.nicholaspsmith.ApolloMonitor`.

**`main.swift`** — `StatusItemController` for icon and menu, `HotkeyTap` bound to
`.mediaKey(0, …)` → `monitor.up` and `.mediaKey(1, …)` → `monitor.down`
(`NX_KEYTYPE_SOUND_UP`/`_DOWN` from `ev_keymap.h`), each with and without `.fn`
because `Binding.matches` is exact and some keyboards report the function layer
on media keys. `repeatsOnHold: true`; `onMatch` returns `true` to swallow, which
is also what suppresses the useless system volume HUD.

**`DefaultOutputWatcher`** — whether macOS's default output is a Universal Audio
device, cached and refreshed by a Core Audio property listener (plus each poll
tick). The volume keys are swallowed **only** when it is and the engine is live;
otherwise `onMatch` returns `false` and the key behaves normally, so switching to
the built-in speakers does not leave them without volume keys. The lookup is
cached because it runs inside the tap callback, and HAL calls can block — a tap
that blocks gets disabled by the system.
Reuses keylight's trust gating, `trustTimer`, and `reassertTap` tap-leapfrog
workaround.

Icon: `MeterIcon.gauge(fraction:)`, template black when live, `.systemGray` when
the Apollo is offline or the socket is down.

## Data flow

```
volume-up key → HotkeyTap.onMatch("monitor.up")
     → LevelDb.next(state.db, .up)                // -43 → -42
     → set …/CRMonitorLevel/value -42.000000
     → engine PUSHES -42.0, and the coarser tapered value when it crosses a grid line
     → FrameParser → state.db / state.tapered → icon, slider, overlay

slider drag  → KnobPosition.percent(atX:…)        // 26%
     → set …/CRMonitorLevelTapered/value 0.260000
     → engine snaps to 14/54 and PUSHES 0.259259
     → slider settles on the position the hardware actually took
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
| Overlay window stops reaching the screen | Panel rebuilt on wake, screen-configuration change, or five minutes idle (see `OverlayRefresh`) |

## Testing

Unit tests on Core (29 tests):

- `KnobPosition`: percent ↔ tapered round-trips exactly for all 101 percents;
  values the engine actually reports (14/54 → 26%, 17/54 → 31%); clamping and NaN.
- `LevelDb`: whole-dB stepping, fractional levels snapping onto the integer ladder,
  clamping at −96/0, 96 presses spanning the range, and non-finite input falling to
  silence rather than unity.
- `SliderGeometry`: both track extremes reachable, centre is 50%, out-of-track
  positions clamp, a left-to-right sweep is monotonic and visits every one of the
  101 percents, and a degenerate zero-width track does not divide by zero.
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

Volume-key and overlay behaviour verified after the fact:

- `--step up/up/down` moving −43 → −42 → −41 → −42, confirming 1 dB granularity
- the overlay's on-screen presence read from the window server: `owner=Apollo
  Monitor`, `layer=25`, `alpha=1.00`, `bounds=(1672, 46, 232, 62)` — 16 px inside
  the right edge, just below the menu bar — absent before the level changed and
  gone again 2.5 s later
- the overlay firing once per level change, not twice, despite dB and tapered
  arriving as two separate pushes
- the slider reading 0.12962963 — exactly 7/54, labelled 13% — matching the engine
  rather than snapping to a 5% bucket
- writing 15% from the slider landing on 8/54 (−43 dB)
- an external write reaching the slider *while the menu is open*
  (19% · −38 dB → 15% · −44 dB), confirming pushes survive the menu's modal
  tracking loop

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
