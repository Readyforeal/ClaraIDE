#!/bin/zsh
# Signed distribution by default; --development explicitly makes a local test DMG.
set -euo pipefail
cd "${0:A:h:h}"
DEVELOPMENT=0
if [[ "${1:-}" == --development ]]; then DEVELOPMENT=1; elif [[ $# != 0 ]]; then echo "Usage: $0 [--development]" >&2; exit 1; fi
VERSION=$(<VERSION)
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Invalid VERSION" >&2; exit 1; }
if [[ "$DEVELOPMENT" == 0 ]]; then
  : "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application certificate name}"
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
  [[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]] || { echo "A Developer ID Application certificate is required" >&2; exit 1; }
fi
./scripts/build-app.sh
[[ $(lipo -archs build/Clara.app/Contents/MacOS/Clara) == arm64 ]] || { echo "This release format requires an arm64 build" >&2; exit 1; }
mkdir -p dist
STAGING=$(mktemp -d "$PWD/.build/release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto build/Clara.app "$STAGING/Clara.app"
SUFFIX=""
if [[ "$DEVELOPMENT" == 0 ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$STAGING/Clara.app"
  codesign --verify --deep --strict "$STAGING/Clara.app"
  ditto -c -k --keepParent "$STAGING/Clara.app" "$STAGING/notarize.zip"
  xcrun notarytool submit "$STAGING/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$STAGING/Clara.app"
  xcrun stapler validate "$STAGING/Clara.app"
  spctl --assess --type execute --verbose=2 "$STAGING/Clara.app"
  rm "$STAGING/notarize.zip"
else
  SUFFIX="-development"
  printf 'DEVELOPMENT BUILD — NOT NOTARIZED\nFor local testing only. Requires Apple silicon and macOS 27+.\n' > "$STAGING/DEVELOPMENT.txt"
fi
ln -s /Applications "$STAGING/Applications"
DMG="$PWD/dist/Clara-$VERSION-arm64$SUFFIX.dmg"
hdiutil create -volname "Clara $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$DMG"
if [[ "$DEVELOPMENT" == 0 ]]; then
  codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
(
  cd dist
  shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256"
)
echo "Created $DMG"
