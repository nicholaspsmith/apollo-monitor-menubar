#!/usr/bin/env bash
# Install the ua-watchdog LaunchAgent — the background job that Apollo Monitor's
# "UA Watchdog" submenu reports on and toggles. Without this the submenu is inert.
#
# Everything lands in the user's own domain, so no sudo: the script goes to
# ~/.local/bin, the plist to ~/Library/LaunchAgents, and it is bootstrapped into
# gui/<uid>. Re-running is safe — it refreshes the script and plist in place.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.nicholassmith.ua-watchdog"
SCRIPT_DEST="$HOME/.local/bin/ua-watchdog.sh"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"

mkdir -p "$HOME/.local/bin" "$HOME/.local/state" "$HOME/Library/LaunchAgents"

install -m 755 "$SRC_DIR/ua-watchdog.sh" "$SCRIPT_DEST"

# launchd will not expand a placeholder, so bake the real $HOME into the plist.
sed "s|__HOME__|$HOME|g" "$SRC_DIR/$LABEL.plist.template" > "$PLIST_DEST"

# A watchdog turned off from the menu is a deliberate choice; re-running the
# installer refreshes it in place but must not quietly switch it back on.
# (`=> disabled` on current macOS, `=> true` on older — match both, as the app's
# LaunchctlParser does.)
if launchctl print-disabled "$DOMAIN" 2>/dev/null | grep -Eq "\"$LABEL\" => (disabled|true)"; then
    echo "UA Watchdog: script and plist updated, left disabled (you turned it off)."
    echo "  Re-enable from the menu: Apollo Monitor ▸ UA Watchdog ▸ Enable watchdog"
    exit 0
fi

# Reload so an already-running agent picks up the refreshed plist.
launchctl bootout "$SERVICE" 2>/dev/null || true   # "not loaded" on first install — fine
launchctl enable "$SERVICE"
launchctl bootstrap "$DOMAIN" "$PLIST_DEST"

# Bootstrap can fail for reasons launchctl reports only via exit status, and a
# silently absent watchdog is the exact bug this installer exists to prevent.
if ! launchctl print "$SERVICE" >/dev/null 2>&1; then
    echo "UA Watchdog: bootstrap failed — $SERVICE is not loaded." >&2
    echo "  Check the plist at $PLIST_DEST" >&2
    exit 1
fi

echo "UA Watchdog installed and running (checks every 60s)."
echo "  script: $SCRIPT_DEST"
echo "  log:    $HOME/.local/state/ua-watchdog.log"
