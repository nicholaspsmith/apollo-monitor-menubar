# Apollo Monitor

A macOS menu-bar control for the **monitor output level of a Universal Audio
Apollo**: a horizontal slider, connection status, the Mac's **volume keys**
remapped to drive it in 1 dB steps, and a volume overlay to replace the one macOS
cannot make work.

Built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) and
[HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit).

```
┌────────────────────────────────┐
│  Apollo Twin MkII · Connected  │
│  ───●───────────  13% · -47 dB │
├────────────────────────────────┤
│  Mute                          │
│  Dim                           │
│  Start at Login              ✓ │
│  Quit Apollo Monitor        ⌘Q │
└────────────────────────────────┘
```

## Why this exists

The Apollo exposes **no volume control to Core Audio at all** — no
`kAudioDevicePropertyVolumeScalar`, no virtual main volume, and
`osascript -e 'get volume settings'` reports `output volume: missing value`. So
the macOS volume keys, `set volume`, and every hardware-volume utility are
useless on it, even when the Apollo is the default output device. UAD Console
also ships no AppleScript dictionary and no volume key commands.

The level can only be changed by opening Console or reaching for the knob — until
now.

## How it works

`UA Mixer Engine.app` starts at login and listens on **TCP `127.0.0.1:4710`**,
speaking an undocumented path-based "StateTree" protocol. It is the same channel
UAD Console itself uses, and it listens whether or not the Console window is
open.

- Messages are `<verb> <path> [value]` terminated by a **NUL byte** (`0x00`).
  A newline is silently ignored, which makes the socket look dead.
- Verbs: `get`, `set`, `subscribe`, `unsubscribe`.
- Replies are JSON: `{"path": …, "data": …}` or `{"path": …, "error": …}`.
- `subscribe` returns the current value **and pushes every later change**, so the
  menu bar follows the hardware knob and Console's fader live, with no polling.
- Round-trip latency is ~3 ms.

Paths used (device 0; the `MONITOR` output is resolved by name, not hardcoded):

| Path | Type |
|---|---|
| `/devices/0/DeviceName/value` | string — e.g. `"Apollo Twin MkII"` |
| `/devices/0/DeviceOnline/value` | bool |
| `…/outputs/<n>/CRMonitorLevelTapered/value` | float 0.0–1.0, knob position |
| `…/outputs/<n>/CRMonitorLevel/value` | float −96.0–0.0, dB |
| `…/outputs/<n>/Mute/value`, `…/DimOn/value` | bool |

### The two properties are not equivalent

`CRMonitorLevelTapered` **snaps to a 1/54 grid** — a requested `0.05` reads back
as `0.055556` — and holds the same value across roughly a 2 dB span. It is a
coarse *report* of the knob's position, not the control itself.

`CRMonitorLevel` (dB) is the real, fine-grained control: `-29.5`, `-29.1` and
`-27.25` all round-trip exactly while the tapered value sits unchanged at 14/54.

So the two are used for different jobs:

- **The volume keys step dB**, 1 dB at a time, snapped onto the whole-dB ladder so
  a level left on a fraction by the hardware knob lands back on integers. Around
  normal listening levels one tapered grid step is ~2 dB, which makes 1 dB about
  0.9% of knob travel — finer than a single percentage point of the 0–100% scale,
  which cannot be expressed at all in only 55 hardware positions.
- **The slider sets knob position**, mirroring Console's knob. Its knob sits at the
  position the engine reports, continuously — the display is never quantised, so it
  always agrees with Console. Dragging writes whole percents; the engine snaps those
  to its 1/54 grid and pushes back the real position, which is then what is shown.
  So a drop at 26% can settle at 14/54, and the readout tells you so.

Nothing accumulates in either path — the keys compute an absolute dB, the slider an
absolute position from the mouse — so no canonical step ladder is needed to stop
drift. Conversions and the drag geometry are
[unit-tested](Tests/ApolloMonitorCoreTests/KnobPositionTests.swift).

0% is −96 dB (silence), 100% is 0 dB (unity).

## Install

```sh
git clone https://github.com/nicholaspsmith/StatusItemKit.git
git clone https://github.com/nicholaspsmith/HotkeyKit.git
git clone https://github.com/nicholaspsmith/apollo-monitor-menubar.git
cd apollo-monitor-menubar
../StatusItemKit/scripts/setup-signing.sh   # once, see below
./install.sh
```

The three checkouts must be siblings — `Package.swift` uses local paths.

Run `../StatusItemKit/scripts/setup-signing.sh` once before installing.
Ad-hoc signatures get a new code hash on every rebuild and macOS keys the
Accessibility grant to that hash, so without a stable identity you re-approve the
app after every build.

## Usage

| | |
|---|---|
| **Volume up / down keys** | Monitor level ±1 dB per press, held keys ramp |
| Click the icon | Menu with the slider, Mute, Dim |
| `ApolloMonitor --step up\|down` | Adjust once and exit — needs no Accessibility |

### The volume keys

The Mac's own volume keys are taken over rather than some chord. On an Apollo they
otherwise do nothing useful: because the device has no Core Audio volume, pressing
them just raises the system HUD with a **greyed-out slider you cannot move**.
Swallowing the key suppresses that HUD too, so the only feedback is the menu-bar
gauge (which is live).

### The overlay

Because the key is swallowed, the system's own volume HUD never appears — which is
no loss, since for a device with no Core Audio volume it could only show a slider
greyed out. A replacement overlay appears top-right below the menu bar, in the same
place, showing the device name, a level bar, and the exact dB. It is a
non-activating borderless panel so it never steals focus, ignores mouse events, and
fades after 1.4 s.

It follows the *level*, not the keypress, so turning the knob on the Apollo itself
or moving Console's fader raises the same readout. Dragging the menu slider does
not, since that is already its own feedback.

### Pass-through

The volume keys are only intercepted while the Apollo is **the current default output
device**. Switch to the built-in speakers or a USB interface and the keys go
straight back to their normal behaviour, because those devices have their own
volume and macOS handles them properly. The menu says so when it is passing them
through. They also pass through whenever the engine is unreachable, so the keys
are never dead.

Bound to `NX_KEYTYPE_SOUND_UP` / `_DOWN` (0 and 1), with and without the `fn`
modifier, since some keyboards report the function layer on media keys.

This needs **Accessibility** permission (it is a `CGEventTap`); the menu and
slider do not. `--step` is the escape hatch if you would rather not grant it:
bind it from Shortcuts, Karabiner, or anything else that can run a command.

## Requirements

macOS 13+, an Apollo with UA's software installed. Tested against an Apollo Twin
MkII and UAD Console 3 (1.3.0) on macOS 26.

## Diagnostics

```sh
/usr/bin/log stream --predicate 'subsystem == "com.nicholaspsmith.ApolloMonitor"'
```

Logs the socket state, the resolved MONITOR output, device online/offline, and
every level change. (`log` is a zsh builtin — the absolute path matters.)

## Caveats

- The protocol is undocumented and unsupported. A UA update could change it.
- Single device only (`/devices/0`); no surround, cue outputs, or preamp control.
- The 1/54 grid is what a Twin MkII reports. Other Apollos may differ; the step
  arithmetic does not depend on the exact divisor.

## Design notes

[`docs/superpowers/specs/2026-07-29-apollo-monitor-menubar-design.md`](docs/superpowers/specs/2026-07-29-apollo-monitor-menubar-design.md)

## License

MIT
