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

# Versionsnummer (wird von GitHub Actions gesetzt; lokal 0.0.0)
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist"
echo "  Version $VERSION ($BUILD_NUMBER)"

# Rüdigers Sprite-Animationen (Einzelbilder, erzeugt mit tools/sprites/render.js)
if [[ -d Resources/Sprites ]]; then
  cp -R Resources/Sprites "$APP/Contents/Resources/Sprites"
fi

# App-Icon: aus Resources/Icon/AppIcon.png (1024 × 1024) alle Größen erzeugen
if [[ -f Resources/Icon/AppIcon.png ]]; then
  echo "▸ Erzeuge App-Icon …"
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" Resources/Icon/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" Resources/Icon/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# Feste Signatur (eigenes Zertifikat, siehe build.yml): macOS merkt sich Freigaben
# wie „Bedienungshilfen“ dann über Updates hinweg. Ohne Zertifikat: ad-hoc.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signiere mit festem Zertifikat (${SIGN_IDENTITY}) …"
  if ! codesign --force --sign "$SIGN_IDENTITY" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} "$APP"; then
    echo "::warning::Signieren mit Zertifikat fehlgeschlagen – signiere ad-hoc"
    codesign --force --sign - "$APP"
  fi
else
  echo "▸ Signiere (ad-hoc) …"
  codesign --force --sign - "$APP"
fi
codesign -d -r- "$APP" 2>&1 | sed 's/^/  /' || true

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installiere nach /Applications …"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
fi

echo "✓ Fertig: $APP"
