#!/bin/bash
# Assemble the standard macOS .app bundle with two read-only sensor helpers.
# Local test builds use an ad-hoc signature. Public builds MUST use Developer ID.
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MacPanel can only be built on macOS using Xcode." >&2
  exit 1
fi
for tool in swift clang codesign sips iconutil; do
  if ! command -v "$tool" >/dev/null 2>&1 && ! xcrun --find "$tool" >/dev/null 2>&1; then
    echo "Missing developer tool: $tool. Install/activate Xcode." >&2
    exit 1
  fi
done

ARCH="${MACPANEL_ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
SIGN_IDENTITY="${MACPANEL_SIGN_IDENTITY:--}"
APP="$PWD/dist/MacPanel.app"

printf 'Building MacPanel for %s...\n' "$ARCH"
swift build -c release --arch "$ARCH" --product MacPanel
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacPanel" "$APP/Contents/MacOS/MacPanel"
xcrun clang -arch "$ARCH" -fobjc-arc -O2 -framework Foundation -framework IOKit \
  "$PWD/Resources/MacPanelSensor.m" -o "$APP/Contents/MacOS/MacPanelSensor"
xcrun clang -arch "$ARCH" -fobjc-arc -O2 -framework Foundation -framework IOKit \
  "$PWD/Resources/MacPanelHardware.m" -o "$APP/Contents/MacOS/MacPanelHardware"
cp "Resources/MacPanel.icns" "$APP/Contents/Resources/MacPanel.icns" 2>/dev/null || true
if [[ ! -f "$APP/Contents/Resources/MacPanel.icns" ]]; then
  icon_tmp="$(mktemp -d)"
  trap 'rm -rf "$icon_tmp"' EXIT
  mkdir -p "$icon_tmp/MacPanel.iconset"
  for n in 16 32 128 256 512; do
    sips -z "$n" "$n" "Resources/MacPanelIcon.png" --out "$icon_tmp/MacPanel.iconset/icon_${n}x${n}.png" >/dev/null
    n2=$((n * 2))
    sips -z "$n2" "$n2" "Resources/MacPanelIcon.png" --out "$icon_tmp/MacPanel.iconset/icon_${n}x${n}@2x.png" >/dev/null
  done
  iconutil -c icns "$icon_tmp/MacPanel.iconset" -o "$APP/Contents/Resources/MacPanel.icns"
fi
cp ThirdParty/*-LICENSE.txt "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${MACPANEL_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $MACPANEL_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
chmod +x "$APP/Contents/MacOS/"*

# Sign nested executables before sealing the enclosing .app.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  for name in MacPanelSensor MacPanelHardware; do
    codesign --force --sign - "$APP/Contents/MacOS/$name"
  done
  codesign --force --sign - "$APP"
  echo 'Local test build: ad-hoc signed (NOT a public, notarized release).'
else
  for name in MacPanelSensor MacPanelHardware; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$name"
  done
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  echo 'Developer ID signed build: notarization is still required before distribution.'
fi
codesign --verify --deep --strict --verbose=2 "$APP"
printf '\nApp: %s\n' "$APP"
echo 'Run once to show the menu bar icon; auto-start registration is attempted on first run from Applications.'
