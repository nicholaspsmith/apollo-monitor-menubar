# Apollo Monitor

A macOS menu-bar control for the **monitor output level of a Universal Audio
Apollo**: a horizontal slider, connection status, and the Mac's **volume keys**
remapped to drive it.

Built on [StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit) and
[HotkeyKit](https://github.com/nicholaspsmith/HotkeyKit).

```
┌────────────────────────────────┐
│  Apollo Twin MkII · Connected  │
│  ──────●──────────────    30%  │
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

### The one non-obvious part

The engine **snaps** `CRMonitorLevelTapered` to a coarse internal grid — 1/54 on
an Apollo Twin MkII, so a requested `0.05` reads back as `0.055556`. Stepping by
`set(read() + 0.05)` would therefore compound that error and the increments would
not stay even.

So a step index `0...20` is canonical: the app always writes `index / 20` and
never adds to a value it read back. Coming the other way,
`round(tapered × 20)` recovers the index — including from the engine's snapped
echo of the app's own writes, which is why they need no special handling. The
round-trip is exact for all 21 steps on any grid finer than 1/40, and
[is unit-tested](Tests/ApolloMonitorCoreTests/VolumeStepTests.swift).

0% is −96 dB (silence), 100% is 0 dB (unity), and the slider position mirrors
Console's knob exactly.

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
| **Volume up / down keys** | Monitor level up / down, 5% per press, held keys ramp |
| Click the icon | Menu with the slider, Mute, Dim |
| `ApolloMonitor --step up\|down` | Adjust once and exit — needs no Accessibility |

### The volume keys

The Mac's own volume keys are taken over rather than some chord. On an Apollo they
otherwise do nothing useful: because the device has no Core Audio volume, pressing
them just raises the system HUD with a **greyed-out slider you cannot move**.
Swallowing the key suppresses that HUD too, so the only feedback is the menu-bar
gauge (which is live).

They are only intercepted while the Apollo is **the current default output
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
