# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.7.0] - 2026-10-08

- No user-visible changes.

## [1.6.0] - 2026-10-07

- Dimmed, the ticks ease between 75% and full green over a fraction of a second instead of snapping, and pulse 12.5% slower (0.5625 s each way)

## [1.5.0] - 2026-10-07

- The Apollo icon in the menu bar can now display muted or dimmed states directly within its arc using a customizable tick color.

## [1.4.4] - 2026-10-07

- Dimmed, the ticks now pulse between 75% and full green instead of nearly fading out

## [1.4.3] - 2026-10-07

- Muted, the arc's lit ticks turn red instead of the whole icon going grey
- Dimmed, the lit ticks pulse: half a second dimmed green, half a second full green

## [1.4.2] - 2026-10-06

- Ticking a checkbox in the menu no longer closes it: Mute, Dim and Settings ▸ Show Volume Overlay stay open, and Mute and Dim follow the Apollo while the menu is up

## [1.4.1] - 2026-10-05

- New app icon: Apollo as he looks in the menu bar

## [1.4.0] - 2026-10-05

- New **Settings** submenu at the foot of the menu, the same one every Menumon app has: Show Volume Overlay, Icon and Start at Login now live there, with the version number at the bottom
- The menu itself now holds just the level, Mute, Dim and status rows, then Settings and Quit Apollo Monitor

## [1.3.0] - 2026-10-05

- Apollo blinks once a minute, taking his turn with the other Menumon mascots. Skipped under Reduce Motion

## [1.2.0] - 2026-10-02

- Removed: the Mixer Watchdog submenu and the `ua-watchdog` LaunchAgent it controlled — the watchdog now lives in [Mac Daddy](https://github.com/nicholaspsmith/mac-daddy-menubar), whose installer retires the old agent. `install.sh` no longer installs it, and leaves an existing agent running until Mac Daddy takes over

## [1.1.0] - 2026-09-28

- The menu-bar icon hides itself while no Universal Audio device is connected, and comes back the moment one appears

## [1.0.2] - 2026-09-28

- `install.sh` now asks whether to turn on Start at Login (skipped when it is already on, or when there is no terminal to ask in) instead of turning it on unasked, then relaunches the app, quitting any running copy first so the new build takes over

## [1.0.1] - 2026-09-23

- chore: regenerate the menu-bar icon image

## [1.0.0] - 2026-09-23

- feat: the menu shows the version it was built from
- LICENSE: name the copyright holder above the MPL text
- Use StatusItemKit's --login handling; note the MIT → MPL-2.0 change
- License: Mozilla Public License 2.0
- feat: restart a mixer engine that has lost the Apollo
- docs: Curtain is now Barn
- docs: name the vendor only in the supported-interfaces table, with an unaffiliated disclaimer
- docs: no vendor name — Apollo audio interfaces, a supported-interfaces table, Mixer Watchdog
- art: new mascot and app icon matching the menu-bar face
- feat: Apollo Twin face icon replaces the rocket (menu ▸ Icon ▸ Apollo; Arc still available)
- docs: the character menu-bar icon, rendered from code, and what its states mean
- feat: rocket icon whose flame is the level (Icon ▸ Arc restores the meter)
- feat: app icon from the Menubarn mascot
- feat: yield width while Curtain reveals its hidden block
- docs: mention the Menubarn widget library
- docs: why a standalone app beats a SwiftBar plugin
- docs: add the Menubarn mascot to the README
- Advertise the menu-bar suite, and add a menu screenshot
- Register Start at Login from install.sh (#3)
- Ship the UA Watchdog agent, not just its menu (#2)
- Record headphone-control findings; ship no headphone code
- Spec headphone-output awareness
- Add UA process monitor
- Wire the mute key to the Apollo's Mute
- Document the menu-bar icon and correct the latency figure
- Add a menu switch for the volume overlay
- Use a green level arc for the menu-bar icon
- Draw the slider so the filled side is tinted, not grey
- Grey the status line and slider only when the Apollo is unreachable
- Retire the Python CLI
- Take drawing off the keystroke path and accelerate held keys
- Rebuild the overlay panel across sleep, display changes, and long idle
- Slider follows the reported position; writes round to 1%
- Step in whole dB and show a replacement volume overlay
- Remap the Mac's volume keys instead of a chord
- Mark spec implemented
- Correct spec: slider hit-testing, headless mode, verification record
- Menu-bar monitor level control for UAD Console
