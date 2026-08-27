#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 /path/to/Telegram.app [codesign identity]" >&2
    exit 64
fi

readonly APP="$1"
readonly SIGN_IDENTITY="${2:-${TELEGRAM_CONTEXT_SIGN_IDENTITY:-Supervisor Local Dev}}"

if [[ ! -d "$APP" ]] || [[ "${APP##*.}" != "app" ]]; then
    echo "Not an app bundle: $APP" >&2
    exit 66
fi
security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""

# Personal Apple teams cannot provision Telegram's App Group together with
# its existing capabilities. The main app uses a private Application Support
# fallback; the system Share extension cannot use that directory, so omit it.
disabled_dir=$(mktemp -d "${TMPDIR:-/tmp}/telegram-context-sign.XXXXXX")
trap 'rm -rf "$disabled_dir"' EXIT
if [[ -d "$APP/Contents/PlugIns/TelegramShare.appex" ]]; then
    mv "$APP/Contents/PlugIns/TelegramShare.appex" "$disabled_dir/TelegramShare.appex"
fi

codesign --force --deep --options runtime --timestamp=none \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
while IFS= read -r -d '' library; do
    codesign --force --options runtime --timestamp=none \
        --sign "$SIGN_IDENTITY" "$library"
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -type f -name '*.dylib' -print0)
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
