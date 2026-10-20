#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"; fi
APP="Grab.app"

echo "==> Building (release)"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Creating bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Grab" "$APP/Contents/MacOS/Grab"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Installing"
pkill -x Grab || true
for _ in $(seq 1 50); do
    pgrep -x Grab >/dev/null || break
    sleep 0.1
done
rm -rf "/Applications/$APP"
ditto "$APP" "/Applications/$APP"

echo "==> Launching"
open "/Applications/$APP" || { sleep 1; open "/Applications/$APP"; }
echo "Done."
