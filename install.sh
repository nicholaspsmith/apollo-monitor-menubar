#!/usr/bin/env bash
# Build Apollo Monitor.app and symlink it into ~/Applications (rebuilds
# propagate; SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Apollo Monitor.app"

"$SRC_DIR/scripts/build-app.sh"

# The app ships a "UA Watchdog" submenu that reports on and toggles this agent,
# so install the agent too — otherwise that menu controls nothing.
"$SRC_DIR/watchdog/install-watchdog.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# Register Start at Login. Without this the app only runs until the next reboot,
# and a menu-bar app that quietly fails to come back is easy to miss for weeks.
# SMAppService can only register the calling process's own bundle, so this has
# to run the installed binary rather than call launchctl.
if "$HOME/Applications/$APP_NAME/Contents/MacOS/ApolloMonitor" --login on >/dev/null; then
    echo "Start at Login: on"
else
    echo "Start at Login: could not register (turn it on from the menu)" >&2
fi

open "$HOME/Applications/$APP_NAME"

cat <<'EOF'

Apollo Monitor is now running in the menu bar.

First-run setup
  1. Grant Accessibility when prompted (System Settings ▸ Privacy & Security ▸
     Accessibility). This is required to take over the volume keys — the menu and
     slider work without it. Until granted, the menu shows
     "⚠ Grant Accessibility…"; the keys start working the moment you allow it.
     If "Apollo Monitor" is ALREADY listed there from an earlier build, remove it
     with − and re-add it: an ad-hoc rebuild changes the code hash the grant is
     keyed to, and a stale entry looks enabled while doing nothing.
  2. Optional: menu ▸ Start at Login.

The UA Watchdog LaunchAgent was installed alongside the app. It checks every 60s
for runaway Universal Audio processes, kills them, and restarts the mixer engine
so audio comes back. Turn it off any time: menu ▸ UA Watchdog ▸ Disable watchdog
(that choice survives reboots and re-running this installer).

Recommended, once: ../StatusItemKit/scripts/setup-signing.sh
Without a stable signing identity this bundle is ad-hoc signed, so every rebuild
changes its code hash and macOS makes you re-grant Accessibility.

Test: click the menu-bar icon and drag the slider, or press the volume keys.
The level should also follow the knob on the Apollo itself and the fader in UAD
Console, live.
EOF
