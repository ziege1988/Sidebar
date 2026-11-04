#!/usr/bin/env bash
# Baut Sidebar.app aus dem Swift-Package.
#   ./build.sh            → build/Sidebar.app
#   ./build.sh --install  → zusätzlich nach /Applications kopieren und starten
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Sidebar"
APP="build/$APP_NAME.app"

echo "▸ Kompiliere (Release) …"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Signiere (ad-hoc) …"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installiere nach /Applications …"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
fi

echo "✓ Fertig: $APP"
