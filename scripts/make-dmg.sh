#!/bin/bash
# Create a standard drag-to-Applications disk image, requiring no Terminal for end users.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/MacPanel.app}"
[[ -d "$APP" ]] || { echo "Build dist/MacPanel.app first." >&2; exit 1; }
mkdir -p dist
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$APP" "$stage/MacPanel.app"
ln -s /Applications "$stage/Applications"
rm -f dist/MacPanel.dmg
hdiutil create -volname MacPanel -srcfolder "$stage" -format UDZO -ov dist/MacPanel.dmg
if [[ -n "${MACPANEL_SIGN_IDENTITY:-}" && "${MACPANEL_SIGN_IDENTITY}" != "-" ]]; then
  codesign --force --timestamp --sign "$MACPANEL_SIGN_IDENTITY" dist/MacPanel.dmg
fi
echo "DMG created at $PWD/dist/MacPanel.dmg"
echo 'Public distribution additionally requires Developer ID signing and Apple notarization.'
