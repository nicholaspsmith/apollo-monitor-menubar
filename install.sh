#!/usr/bin/env bash
# Build Apollo Monitor.app and symlink it into ~/Applications (rebuilds
# propagate; SMAppService accepts a symlink there for Start-at-Login).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Apollo Monitor.app"

"$SRC_DIR/scripts/build-app.sh"

mkdir -p "$HOME/Applications"
ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

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

Recommended, once: ../StatusItemKit/scripts/setup-signing.sh
Without a stable signing identity this bundle is ad-hoc signed, so every rebuild
changes its code hash and macOS makes you re-grant Accessibility.

Test: click the menu-bar icon and drag the slider, or press the volume keys.
The level should also follow the knob on the Apollo itself and the fader in UAD
Console, live.
EOF
