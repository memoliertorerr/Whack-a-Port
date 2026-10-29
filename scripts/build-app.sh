#!/usr/bin/env bash
# Builds build/Whack-a-Port.app from the Swift package.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications and relaunches it)

set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Whack-a-Port.app"
INSTALL_PATH="/Applications/Whack-a-Port.app"

swift build -c release --product WhackAPort
BIN="$(swift build -c release --show-bin-path)/WhackAPort"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WhackAPort"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: enough to run locally and register as a login item.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x WhackAPort 2>/dev/null || true
  rm -rf "$INSTALL_PATH"
  cp -R "$APP" "$INSTALL_PATH"
  open "$INSTALL_PATH"
  echo "Installed and launched $INSTALL_PATH"
fi
