#!/bin/bash

set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly STATE_DIR="/Volumes/Storage/TelegramContextUpdater"
readonly LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.sakenugod.telegram-context-updater.plist"
readonly LABEL="com.sakenugod.telegram-context-updater"
readonly DOMAIN="gui/$(id -u)"

if [[ ! -d /Volumes/Storage ]]; then
    echo "The Storage volume is not mounted." >&2
    exit 1
fi

mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"
install -m 755 "$REPOSITORY_ROOT/scripts/build_and_publish_update.sh" "$STATE_DIR/build_and_publish_update.sh"
install -m 644 "$REPOSITORY_ROOT/automation/com.sakenugod.telegram-context-updater.plist" "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT"

launchctl bootout "$DOMAIN" "$LAUNCH_AGENT" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$LAUNCH_AGENT"
launchctl enable "$DOMAIN/$LABEL"

echo "Installed $LABEL"
