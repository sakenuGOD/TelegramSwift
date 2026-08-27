#!/bin/bash

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly REPOSITORY="sakenuGOD/TelegramSwift"
readonly SOURCE_DIR="${TELEGRAM_CONTEXT_SOURCE_DIR:-/Volumes/Storage/TelegramContextBuilder}"
readonly STATE_DIR="${TELEGRAM_CONTEXT_STATE_DIR:-/Volumes/Storage/TelegramContextUpdater}"
readonly DERIVED_DATA="$SOURCE_DIR/DerivedData-Automatic"
readonly TEAM_ID="CU8UJ55239"
readonly SIGN_IDENTITY="${TELEGRAM_CONTEXT_SIGN_IDENTITY:-Supervisor Local Dev}"

if [[ ! -d /Volumes/Storage ]]; then
    exit 0
fi

mkdir -p "$STATE_DIR"
if ! mkdir "$STATE_DIR/run.lock" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$STATE_DIR/run.lock" 2>/dev/null || true' EXIT

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    git clone --recurse-submodules "https://github.com/$REPOSITORY.git" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" restore --worktree Telegram-Mac/Info.plist scripts/rebuild 2>/dev/null || true
git -C "$SOURCE_DIR" fetch origin master
git -C "$SOURCE_DIR" switch --detach origin/master
git -C "$SOURCE_DIR" submodule sync --recursive
git -C "$SOURCE_DIR" submodule update --init --recursive

# Refresh the durable LaunchAgent runner from the newly fetched last-good
# source. The current process keeps running the already-open script; the next
# scheduled run uses the refreshed copy.
runner_path="$STATE_DIR/build_and_publish_update.sh"
source_runner="$SOURCE_DIR/scripts/build_and_publish_update.sh"
if [[ -f "$source_runner" ]] && ! cmp -s "$source_runner" "$runner_path"; then
    install -m 755 "$source_runner" "$runner_path"
fi

source_commit=$(git -C "$SOURCE_DIR" rev-parse HEAD)
if [[ -f "$STATE_DIR/last-published-commit" ]] && [[ "$(<"$STATE_DIR/last-published-commit")" == "$source_commit" ]]; then
    exit 0
fi

dependency_fingerprint=$(
    {
        git -C "$SOURCE_DIR" submodule status --recursive
        git -C "$SOURCE_DIR" rev-parse HEAD:core-xprojects
        xcodebuild -version
    } | shasum -a 256 | awk '{print $1}'
)

if [[ ! -f "$STATE_DIR/dependency-fingerprint" ]] || [[ "$(<"$STATE_DIR/dependency-fingerprint")" != "$dependency_fingerprint" ]]; then
    printf 'yes\n' > "$SOURCE_DIR/scripts/rebuild"
    (
        cd "$SOURCE_DIR"
        bash scripts/configure_frameworks.sh > "$STATE_DIR/dependencies.log" 2>&1
    )
    git -C "$SOURCE_DIR" restore --worktree scripts/rebuild
    printf '%s\n' "$dependency_fingerprint" > "$STATE_DIR/dependency-fingerprint"
fi

build_number=$(date -u '+%Y%m%d%H%M')
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$SOURCE_DIR/Telegram-Mac/Info.plist"

(
    cd "$SOURCE_DIR"
    xcodebuild build \
        -workspace Telegram-Mac.xcworkspace \
        -scheme Release \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        -destination 'platform=macOS,arch=arm64' \
        ONLY_ACTIVE_ARCH=YES \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY='' \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        -skipPackageUpdates \
        > "$STATE_DIR/build.log" 2>&1
)

built_app="$DERIVED_DATA/Build/Products/Release/Telegram.app"
test -d "$built_app"
staging_dir=$(mktemp -d "$STATE_DIR/signing.XXXXXX")
trap 'rm -rf "$staging_dir"; rmdir "$STATE_DIR/run.lock" 2>/dev/null || true' EXIT
app="$staging_dir/Telegram.app"
ditto "$built_app" "$app"
"$SOURCE_DIR/scripts/sign_local_app.sh" "$app" "$SIGN_IDENTITY"

display_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="$STATE_DIR/Telegram-$build_number.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"

tag="ai-$build_number"
gh release create "$tag" "$archive" \
    --repo "$REPOSITORY" \
    --title "Telegram $display_version ($build_number)" \
    --notes "Automatic last-good build from source commit $source_commit. Includes AI context export, voice-transcript selection, shared photo captions, and long-text documents." \
    --latest

printf '%s\n' "$source_commit" > "$STATE_DIR/last-published-commit"
git -C "$SOURCE_DIR" restore --worktree Telegram-Mac/Info.plist
rm -f "$archive"
