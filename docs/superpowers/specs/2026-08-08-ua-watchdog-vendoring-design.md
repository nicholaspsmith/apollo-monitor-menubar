# Vendoring the UA Watchdog LaunchAgent

**Date:** 2026-08-08
**Status:** implemented
**Issue:** [#1](https://github.com/nicholaspsmith/apollo-monitor-menubar/issues/1)
— "UA Watchdog submenu controls a LaunchAgent the repo never installs"

## The problem

`15db688` added the whole reading-and-toggling half of the UA Watchdog surface —
`WatchdogController`, `WatchdogStatus`, `WatchdogPaths`, `WatchdogIcon`,
`LogParser`, and the submenu — but not the agent it reads. The watchdog existed
only as an uncommitted personal script on one machine. On any other machine the
submenu was inert, and worse, it was inert in a way that lied:

`launchctl print` exits non-zero when the service is unknown, so
`WatchdogStatusBuilder` read `isBootstrapped: false` and reported `.disabled` —
identical to a watchdog the user had deliberately turned off. Clicking **Enable
watchdog** then bootstrapped a plist that did not exist, and `setEnabled`
discarded both exit statuses, so the failure was invisible.

## Decision

Vendor the watchdog rather than hide the submenu. The issue offered both; the
menu surface is genuinely useful and already built, so shipping the missing half
beats deleting the half that works.

`install.sh` installs the agent unconditionally, as part of installing the app.

## What was added

```
watchdog/
  ua-watchdog.sh                                 # the script, verbatim from the live install
  com.nicholassmith.ua-watchdog.plist.template   # __HOME__ placeholder
  install-watchdog.sh                            # copy + substitute + bootstrap + verify
```

Three choices worth recording:

**The label stays `com.nicholassmith.ua-watchdog`.** It is already hardcoded in
`WatchdogPaths`, and renaming it would orphan the agent already running on the
author's machine — a watchdog nobody can see is exactly the failure mode being
fixed.

**The plist points at `$HOME/.local/bin/ua-watchdog.sh`, not into the checkout.**
The installer copies the script there. Pointing launchd at the working copy would
make edits live instantly, but a background job that runs `kill -9` should not
stop existing because a directory moved. Re-running the installer re-syncs the
copy.

**Re-running the installer respects a deliberate disable.** If
`launchctl print-disabled` reports the label as off, the installer refreshes the
script and plist but does not re-enable. The submenu's toggle is documented as
persistent; an installer that silently undid it would make that a lie.

## App-side changes

`WatchdogState` gains a fourth case, `notInstalled`, selected on the existence of
the plist and checked *before* every other signal — launchd can still report a
service whose plist was deleted, and absence has to win:

```swift
if !isInstalled                       { .notInstalled }
else if isDisabled || !isBootstrapped { .disabled }
```

It surfaces as a gray `xmark.shield` (distinct from `disabled`'s `shield.slash`),
the header `○ UA Watchdog not installed — run ./install.sh`, and a greyed-out
toggle (`isToggleable`) — no button that cannot work.

`setEnabled` now returns the name of the `launchctl` step that failed, or nil.
`toggleWatchdog` raises an `NSAlert` naming that step.

**Deviation from the issue's suggestion.** Issue #1 proposed reporting a
`.problem` state on bootstrap failure. That would not work: the menu re-reads
`status()` on every open, so a failure recorded in the model is overwritten
before it can be read. The alert is what actually reaches the user.

## Testing

`WatchdogStatusTests` covers the new case: a missing plist is `.notInstalled` and
not `.disabled`, is not `isEnabled`, and beats a stale heartbeat, a non-zero exit
code, and an explicit disable flag.

The installer was verified against the live agent: the generated plist is
byte-identical to the one already installed (`plutil -convert xml1` diff, empty),
a fresh tick ran after reinstall (heartbeat advanced, `last exit code = 0`), and
the disabled path was exercised end-to-end — disable, reinstall, confirm still
booted out, re-enable.

## Also removed

`WatchdogStatus.summaryLine` is gone. It formatted a one-line status string for
the standalone watchdog app's `--status` flag; that app was folded into Apollo
Monitor on 2026-08-01 and the flag came with it, leaving a public property no
production code called and only tests exercised. Its doc comment still advertised
the missing CLI. If a `--status` flag is ever wanted, it belongs with the flag.

## Not done

The watchdog is Universal-Audio-specific and lives in an Apollo repo, so it is
not being generalised into a configurable process supervisor. The thresholds stay
env-overridable at the top of the script, which is as much configuration as this
needs.
