# Headphone control — findings and routes not taken

**Date:** 2026-08-02
**Status:** not implemented — reference only

Apollo Monitor controls the MONITOR output and nothing else. That is deliberate
and unchanged. This document records what was learned while investigating
headphone control, so the question does not have to be re-researched from
scratch if it comes up again.

**Summary:** the Apollo's headphone level cannot be set programmatically. It
does not exist in any protocol UA exposes. Three workarounds were identified;
all were rejected, and the reasons are below.

## The core finding

Established by direct probing of UA Mixer Engine (Apollo Twin MkII, UAD
Console 3):

1. **A full walk of the StateTree — 687 nodes under `/devices/0` — contains
   exactly one control-room level**: `CRMonitorLevel` / `CRMonitorLevelTapered`
   on output 4 (`MONITOR`). No output carries a headphone or cue level.
2. **Turning the knob with HP selected produces no StateTree traffic at all**,
   while the same turn with MONITOR selected produces a dense stream of
   `CRMonitorLevel` pushes. The headphone level is hardware-side only.
3. **`/outputroutes` has no level either** — `HP L` / `HP R` are routes, not
   controls.

This matches every external source. UA documents line outputs 3–4 as
software-controlled and headphone volume as the exception, adjustable only by
the Level knob with PHONES selected. No public project controls it either:
`UA-Midi-Control` (input faders, preamp gain), `ua-commander`
(`CRMonitorLevelTapered`, `Mute`, `DimOn`), `ApolloBot`, `uad2midi`, and
`open-apollo` — a clean-room Linux driver cataloguing 11,244 StateTree controls
— all stop at monitor level and headphone *routing*.

## Reference: the output table

| Output | Name | IOType | Notable properties |
|---|---|---|---|
| 0 | `HP` | `Cue` | `SelectedOnFront`, `MixInSource='mon'` |
| 1 | `LINE 3/4` | `Cue` | `SelectedOnFront`, `MixInSource='mon'` |
| 2 | `CUE 3` | `Cue` | `SelectedOnFront` |
| 3 | `CUE 4` | `Cue` | `SelectedOnFront` |
| 4 | `MONITOR` | `Monitor` | `CRMonitorLevel`, `CRMonitorLevelTapered`, `Mute`, `DimOn`, `SelectedOnFront` |
| 5 | `HP` | `Headphone` | `MixInSource='cue1'` |
| 6 | `LINE 3/4` | `Headphone` | `AltMonEnabled`, `AltMonTrim` (−30…+30 dB), `Pad`, `MixInSource='cue2'` |

Device-level: `AltMonSelection` (int 0–2, currently 0), `MaxAltMons` (readonly,
1), `DimAttenuation` (17), `CueBusCount` (2).

Core Audio reports 10 output channels; `/outputroutes` names them MON L/R
(ch 1–2), LINE 3/4 (ch 3–4), VIRTUAL 1–4, HP L/R. Odd channels are left.

## Route A — front-panel awareness (`SelectedOnFront`)

Does not control the headphone level; makes the app *honest* about not
controlling it.

**Confirmed working.** `SelectedOnFront` is present on outputs 0–4, reports
which output the front panel is on, and pushes on `subscribe` the instant the
hardware button is pressed. `Active` is **not** the selector — it never moved
across a front-panel switch.

The value this would deliver: today, pressing volume-up while on headphones
silently moves the **speakers**, which you cannot hear. Awareness would swallow
the key, show "Headphones — use the Apollo's knob" in the overlay, and mark the
menu-bar icon.

**Writable, with a caveat.** `set …/SelectedOnFront/value true` is accepted and
echoed, but a software write is **not mutually exclusive** — writing `true` to
MONITOR left HP `true` as well, a state the hardware button never produces. Any
implementation must write the pair itself.

**Unverified:** whether a software write actually re-targets the hardware knob.
Four test windows (40 s, 40 s, 45 s, 180 s) recorded zero knob-driven level
changes while MONITOR was software-selected, but it was never confirmed that the
knob was turned during one. The null result is unexplained, not negative.

## Route B — ALT monitor via LINE 3/4 (the most promising)

The only route that would give real headphone volume control from the keyboard.

**Mechanism.** ALT switches the main monitor mix to an alternate output pair —
LINE 3/4 on this model. The alternate output is driven by the *same*
`CRMonitorLevel` this app already reads, writes, and steps. So headphones on
LINE 3/4 would be controlled by the existing volume keys with **no new
level-control code**, and the MONITOR ⇄ headphones toggle would be
`AltMonSelection` 0 ⇄ 1 — documented and software-settable, unlike Route A.

**Wiring.** LINE 3 is left, LINE 4 is right. A stereo headphone plug will not
work in either jack alone: a balanced line output carries one channel, hot on
tip and cold on ring, so headphones in LINE 3 would give the left channel in one
ear and an out-of-phase copy in the other. Needs a Y-cable, two 1/4" **TS**
plugs → one stereo female. TS, not TRS: a TS plug leaves the cold leg
unconnected, which is the correct unbalanced tap off a balanced output.

**Why it was rejected:**

- **LINE 3/4 is a line output, not a headphone amp.** +4 dBu balanced with no
  headphone driver. ~32 Ω headphones will sound thin and under-damped; 250 Ω+
  will likely be too quiet to use. A small headphone amp on those jacks solves
  it completely, and would be the normal way to do this.
- **LINE 3/4 becomes unavailable for everything else.** With ALT COUNT non-zero,
  UA documents those outputs as no longer routable from the DAW or usable as a
  cue send.
- **It is not the built-in headphone jack.** The Apollo's real HP output stays
  knob-only regardless, and the front-panel PHONES button stops being the way to
  switch.
- **It persists** as hardware/session state, visible in Console.

**Untested.** `AltMonSelection = 1` is inferred from the 0–2 range with
`MaxAltMons = 1`, and `AltMonEnabled` on output 6 (currently `false`) may be a
prerequisite or the same switch under another name. Whether `CRMonitorLevel`
drives the ALT output is near-certain from UA's documentation but unproven here.
Testing costs two writes and is fully reversible.

## Route C — cue-bus gain on TCP 4720 (rejected)

A **second port, 4720**, served by a separate UA Mixer process, exposes
Console's session tree: `MAIN` plus `CUE 1`–`CUE 4`, each with a control named
`Volume` in dB (`…/buses/<uid>/outputs/main/controls/gain/value`), alongside
`mute`, `pan_left`, `pan_right`, `gain_trim`. Verbs match StateTree (`get`,
`set`, `subscribe`), replies are NUL-terminated JSON. This is the programmatic
form of the cue-send workaround the forums recommend.

Rejected because it is a **mix gain, not an output level**: it edits the saved
Console session, stacks with the hardware knob rather than replacing it, and is
not in this rig's headphone path anyway — the HP cue output has
`MixInSource='mon'`, so the headphone feed follows the monitor mix and bypasses
the cue buses. Pulsing `CUE 1` and `CUE 2` by −20 dB produced no reported change.

Worth revisiting only if the HP cue is ever switched off `mon`.

## If this is picked up again

Route B is the one worth pursuing, and the cheapest next step is a hardware
test rather than any code: set `AltMonEnabled = true` on output 6 and
`AltMonSelection = 1`, plug anything into LINE 3, and confirm the app's existing
volume keys move that output. If they do, the feature is mostly a menu toggle
over `AltMonSelection` plus an `AltMonTrim` offset — the level path already
works.

Route A remains worth doing on its own merits even without any headphone
control, because the silent-speaker-movement problem is real and the read side
is fully confirmed.
