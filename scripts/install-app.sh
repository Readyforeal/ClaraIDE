#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
SOURCE="$PWD/build/Clara.app"
DESTINATION="/Applications/Clara.app"
codesign --verify --deep --strict "$SOURCE"
if [[ -e "$DESTINATION" ]]; then
  EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
  [[ "$EXISTING_ID" == com.local.clara ]] || { echo "Another application already occupies $DESTINATION" >&2; exit 1; }
fi
ditto "$SOURCE" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
touch "$DESTINATION"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$SOURCE" || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION"
echo "Installed $DESTINATION. Relaunch Clara to use this build."
