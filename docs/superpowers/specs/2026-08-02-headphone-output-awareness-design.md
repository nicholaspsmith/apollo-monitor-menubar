# Headphone-output awareness

**Date:** 2026-08-02
**Status:** designed

## Problem

Apollo Monitor drives the MONITOR output. When the Apollo's front panel is
switched to headphones, the app carries on as though nothing changed:

- The volume keys still write `CRMonitorLevel`, moving the **speakers** — which
  you cannot hear while wearing headphones. The change is discovered later, by
  taking the headphones off.
- The mute key still mutes MONITOR, an inaudible no-op.
- The menu-bar arc still reports the monitor level, which is no longer the level
  you are listening to.

The ask was a toggle between adjusting the monitor output and the headphone
output. The first half of that turns out to be impossible, which reshapes the
feature into the second half: making the app aware of which output is selected,
and honest about what it can and cannot move.

## Finding: the headphone level does not exist in the protocol

Established by direct probing of UA Mixer Engine on this rig
(Apollo Twin MkII, UAD Console 3):

1. **A full walk of the StateTree — 687 nodes under `/devices/0` — contains
   exactly one control-room level**: `CRMonitorLevel` / `CRMonitorLevelTapered`
   on output 4 (`MONITOR`). No output carries a headphone or cue level.
2. **Turning the knob with HP selected produces no StateTree traffic**, while
   the same turn with MONITOR selected produces a dense stream of
   `CRMonitorLevel` pushes. The headphone level is hardware-side only.
3. **`/outputroutes` has no level either** — `HP L` / `HP R` are routes, not
   controls.
4. **A second port, TCP 4720**, served by a separate UA Mixer process, exposes
   Console's session tree (`MAIN` plus `CUE 1`–`CUE 4`, each with a `Volume`
   gain in dB). This is the programmatic form of the documented cue-send
   workaround. It is **not** in this rig's headphone path: the HP cue output
   has `MixInSource='mon'`, so the headphone feed follows the monitor mix and
   bypasses the cue bus gains. Pulsing `CUE 1` and `CUE 2` by −20 dB produced no
   reported change.

This matches the wider evidence. UA documents line outputs 3–4 as
software-controlled and headphone volume as the exception, adjustable only by
the Level knob with PHONES selected. No public reverse-engineering project
controls it either — `UA-Midi-Control` (input faders, preamp gain),
`ua-commander` (`CRMonitorLevelTapered`, `Mute`, `DimOn`), `ApolloBot`,
`uad2midi`, and `open-apollo` (a clean-room Linux driver cataloguing 11,244
StateTree controls) all stop at monitor level and headphone *routing*.

**Consequence:** no design can adjust the headphone level. The feature is
awareness, not control.

## Finding: `SelectedOnFront` is the front-panel selector

| Output | Name | IOType | Has `SelectedOnFront` |
|---|---|---|---|
| 0 | `HP` | `Cue` | yes |
| 1 | `LINE 3/4` | `Cue` | yes |
| 2 | `CUE 3` | `Cue` | yes |
| 3 | `CUE 4` | `Cue` | yes |
| 4 | `MONITOR` | `Monitor` | yes |
| 5 | `HP` | `Headphone` | no |
| 6 | `LINE 3/4` | `Headphone` | no |

Verified behaviour:

- Pressing the hardware button flips the pair atomically:
  `outputs/0/SelectedOnFront → false` and `outputs/4/SelectedOnFront → true`,
  pushed within 10 ms of each other.
- `subscribe` pushes these changes, so the app follows the hardware with no
  polling.
- **`Active` is not the selector.** It never moved across a front-panel switch
  (`MONITOR` stayed `Active=false` while selected and being turned up).
  `SelectedOnFront` is the only signal.
- The property **is writable**: `set …/SelectedOnFront/value true` is accepted
  and echoed.
- **A software write is not mutually exclusive.** Writing `true` to MONITOR left
  HP `true` as well — both outputs reported selected at once, a state the
  hardware button never produces. The app must therefore write the pair itself.

### Unverified: whether a software write re-targets the knob

The engine accepts and echoes the write, but four separate test windows (40 s,
40 s, 45 s, 180 s) recorded **zero** knob-driven level changes while MONITOR was
software-selected, and in none of them was it confirmed that the knob was
actually turned. So the null result is unexplained rather than negative.

The distinction matters only for the optional toggle below. Everything else in
this design depends on *reading* `SelectedOnFront`, which is fully confirmed.

## Design

### `FrontPanelTarget` (ApolloMonitorCore)

A pure value type resolved from the outputs that carry `SelectedOnFront`:

```swift
public enum FrontPanelTarget: Equatable {
    case monitor
    case headphones
    case other(String)   // LINE 3/4, CUE 3, CUE 4
    case unknown         // not yet discovered, or none selected
}
```

Resolution, given `(name, ioType, selectedOnFront)` per output:

- exactly one selected, `ioType == "Monitor"` → `.monitor`
- exactly one selected, `name == "HP"` → `.headphones`
- exactly one selected, otherwise → `.other(name)`
- none selected, or more than one → `.unknown`

The multiple-selected case is real, not defensive: it is what a partial pair
write leaves behind. Treating it as `.unknown` degrades to today's behaviour
rather than guessing wrong.

Resolution is a pure function of the output table, so it is unit-tested with no
socket, alongside `KnobPosition` and `WatchdogStatus`.

### `EngineClient`

Discovery already probes every output node and inspects its properties, so the
extra information is free:

- While walking outputs, record `name`, `IOType`, and whether the node has a
  `SelectedOnFront` property, into an output table.
- `subscribe` to `SelectedOnFront` on each output that has one.
- On each push, update the table and republish `MonitorState.frontPanelTarget`.

`MonitorState` gains one field. `isLive` keeps its current meaning — the monitor
level really is reachable regardless of front-panel selection — and a separate
computed `controlsWhatYouHear: Bool` (`frontPanelTarget == .monitor`) carries the
new distinction. Keeping these apart matters: the slider stays enabled in HP
mode because it still does exactly what it says.

### `App` — keys

`handle(token:)` gains one branch, before the step arithmetic:

```
guard output.isUniversalAudio, engine.state.isLive else { return false }  // unchanged
switch engine.state.frontPanelTarget {
case .headphones, .other:
    showFrontPanelNotice(engine.state.frontPanelTarget)
    return true          // swallowed: no system HUD, no level change
case .monitor, .unknown:
    break                // today's behaviour
}
```

`.unknown` deliberately falls through to the normal path: a discovery failure
must not disable the keys.

Swallowing rather than passing through is deliberate and consistent with the
existing rationale — the Apollo has no Core Audio volume, so a passed-through
key raises a HUD with a greyed-out slider. Returning `true` with no write leaves
the level untouched and the useless HUD suppressed.

Mute takes the same branch. Muting MONITOR while on headphones changes nothing
audible, and silently doing it is the same class of bug as silently moving the
speakers.

### `App` — overlay

`VolumeHUD` gains a message variant: device name plus a line of text, no level
bar and no dB. The text names the actual target, so it stays true when the front
panel is on a cue output rather than headphones:

| Target | Message |
|---|---|
| `.headphones` | Headphones — use the Apollo's knob |
| `.other(name)` | Front knob: *name* — monitor level unchanged |

It reuses the existing panel, fade, and 1.4 s dismissal. It respects the **Show
Volume Overlay** preference, and is rate-limited to once per second so holding a
key does not restart the fade on every repeat.

### `App` — icon

| Target | Icon |
|---|---|
| `.monitor`, `.unknown` | the level arc, exactly as today |
| `.headphones` | SF Symbol `headphones` glyph |
| `.other(name)` | the level arc, greyed |

The glyph is rendered as a **full-colour** image for the same reason the arc is:
template tinting keeps only alpha and inverts on menu open. Green when live,
grey when not — the existing colour language.

A cue output gets a greyed arc rather than the glyph because a headphone symbol
would be a plain lie about where the audio is going, and the app has no glyph
for LINE 3/4. Grey already means "this number is not something you can act on",
which is exactly right here.

Dropping the level readout here is the point. The arc's number stops describing
what you are hearing the moment the front panel leaves MONITOR, and a truthful
number about the wrong output is worse than no number.

### `App` — menu

- A row beneath the status line: `Front knob: HP` / `MONITOR` / `LINE 3/4`.
- The slider row keeps working and gains the label `MONITOR`, so its effect is
  unambiguous while you are on headphones.
- Mute and Dim stay enabled — they act on MONITOR and say so.

### Optional: the MONITOR ⇄ HP toggle

A menu item that writes the pair:

```
set /devices/0/outputs/<monitor>/SelectedOnFront/value true
set /devices/0/outputs/<hp>/SelectedOnFront/value false
```

Both writes always, in that order, so there is never an instant with nothing
selected. This is **gated on verifying that the write re-targets the hardware
knob**. If it proves cosmetic, the item is dropped; nothing else in this design
changes.

## Error handling

- **Engine unreachable / Apollo offline** — `frontPanelTarget` becomes
  `.unknown` alongside the existing `isLive = false`. `.unknown` behaves like
  `.monitor` for key handling, so a discovery failure degrades to today's
  behaviour rather than making the keys dead.
- **No output carries `SelectedOnFront`** — plausible on an Apollo without a
  front-panel selector. Target stays `.unknown`, the menu row is omitted, and
  the app behaves exactly as it does today.
- **Both outputs selected** — `.unknown`, as above.
- **`SelectedOnFront` write rejected** — logged; the subscription is the source
  of truth, so the menu simply does not change state.

## Testing

Unit tests in `ApolloMonitorCoreTests`, matching the existing pure-core pattern:

- `FrontPanelTarget` resolution: monitor selected, HP selected, a cue selected,
  none selected, two selected, empty table, missing `IOType`.
- Both `HP`-named outputs present (indices 0 and 5) with only one carrying
  `SelectedOnFront` — the real topology, and the case a naive name match breaks
  on.

Manual verification against the hardware:

1. Press the front-panel button; the menu row and icon follow within one push.
2. With HP selected, press volume up/down — the overlay shows the notice and
   `CRMonitorLevel` does not move (checked on a second socket).
3. With MONITOR selected, confirm stepping, acceleration, and the overlay are
   unchanged.
4. Quit the engine; confirm keys still pass through and the app degrades to
   today's behaviour.

## What this does not do

- It does not adjust the headphone level. Nothing can, over this protocol.
- It does not touch the port-4720 session tree. Editing Console's cue-bus gains
  from a volume key would persist into the session, stack with the hardware
  knob, and is not in this rig's headphone path anyway.
