# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push without one is refused.
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

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
