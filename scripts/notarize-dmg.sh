#!/bin/bash
# For developers with Apple signing/notarization credentials in their keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
DMG="${1:-$PWD/dist/MacPanel.dmg}"
PROFILE="${MACPANEL_NOTARY_PROFILE:-}"
[[ -f "$DMG" ]] || { echo "Missing DMG: $DMG" >&2; exit 1; }
[[ -n "$PROFILE" ]] || { echo 'Set MACPANEL_NOTARY_PROFILE to an existing notarytool keychain profile.' >&2; exit 1; }
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo 'Signed, notarized and stapled DMG: ready for end-user testing.'
