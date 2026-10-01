#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Build Apollo Monitor.app and symlink it into ~/Applications (rebuilds
# propagate; SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

# Menumon release rule — every push is a release. Arm the pre-push hook in
# every Menumon repo cloned beside this one (local git config, so a fresh
# clone has none until this runs). StatusItemKit README, "Releases".
RELEASE_KIT="$(cd "$(dirname "$0")/.." && pwd)/StatusItemKit/scripts/release/adopt.sh"
if [ -x "$RELEASE_KIT" ]; then
    "$RELEASE_KIT" --hooks-only || echo "Release hook: adopt.sh failed" >&2
else
    echo "Release hook: StatusItemKit not found beside this repo — clone it and re-run" >&2
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Apollo Monitor.app"

"$SRC_DIR/scripts/build-app.sh"

# The app ships a "UA Watchdog" submenu that reports on and toggles this agent,
# so install the agent too — otherwise that menu controls nothing.
"$SRC_DIR/watchdog/install-watchdog.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

# Ask to turn on Start at Login. SMAppService can only register the calling
# process's own bundle, so this runs the installed binary's headless --login.
APP="$HOME/Applications/$APP_NAME"
BIN="$APP/Contents/MacOS/ApolloMonitor"
PROC="${APP##*/}/Contents/MacOS/ApolloMonitor"   # matches the symlink-resolved path too
if [ "$("$BIN" --login status 2>/dev/null)" = "on" ]; then
    echo "Start at Login: already on"
elif [ -t 0 ]; then
    read -r -p "Start Apollo Monitor at login? [Y/n] " answer
    case "$answer" in
        [nN]*) echo "Start at Login: left off (turn it on from the menu)" ;;
        *) if "$BIN" --login on >/dev/null; then
               echo "Start at Login: on"
           else
               echo "Start at Login: could not register (turn it on from the menu)" >&2
           fi ;;
    esac
else
    echo "Start at Login: off (not asked: no terminal). Turn it on from the menu, or run"
    echo "    \"$BIN\" --login on"
fi

# `open` on a running app only activates it, so quit the old build first or the
# new one never launches. Wait for it to go so both don't briefly sit in the bar.
if pgrep -f "$PROC" >/dev/null; then
    osascript -e "tell application id \"$(defaults read "$APP/Contents/Info" CFBundleIdentifier)\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$PROC" >/dev/null || break; sleep 0.5; done
    pkill -f "$PROC" 2>/dev/null || true
    sleep 1
fi
/usr/bin/open "$APP"

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
