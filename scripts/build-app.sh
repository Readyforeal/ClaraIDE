#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --cache-path "$PWD/.build/cache" --disable-sandbox
APP="$PWD/build/Clara.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Prefer Apple's layered icon compiler without changing the machine's selected toolchain.
ICON_DEVELOPER_DIR="${CLARA_DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -x "$ICON_DEVELOPER_DIR/usr/bin/actool" ]]; then
  for candidate in /Applications/Xcode*.app/Contents/Developer(N); do
    if [[ -x "$candidate/usr/bin/actool" ]]; then
      ICON_DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi
NATIVE_ICON=0
if [[ -x "$ICON_DEVELOPER_DIR/usr/bin/actool" ]]; then
  ICON_OUTPUT=$(mktemp -d "$PWD/.build/clara-icon.XXXXXX")
  trap 'rm -rf "$ICON_OUTPUT"' EXIT
  DEVELOPER_DIR="$ICON_DEVELOPER_DIR" "$ICON_DEVELOPER_DIR/usr/bin/actool" \
    Assets/Clara.icon --compile "$ICON_OUTPUT" \
    --platform macosx --minimum-deployment-target 27.0 --target-device mac \
    --app-icon Clara --output-partial-info-plist "$PWD/.build/clara-icon-info.plist" \
    --output-format human-readable-text --notices --warnings
  [[ -s "$ICON_OUTPUT/Assets.car" ]]
  cp -R "$ICON_OUTPUT/" "$APP/Contents/Resources/"
  NATIVE_ICON=1
elif [[ -x "/Applications/Icon Composer.app/Contents/Executables/ictool" ]]; then
  echo "Rendering with Apple Icon Composer; Xcode is still required for adaptive layered output."
  "/Applications/Icon Composer.app/Contents/Executables/ictool" "$PWD/Assets/Clara.icon" \
    --export-image --output-file "$PWD/.build/clara-composer.png" \
    --platform macOS --rendition Default --width 512 --height 512 --scale 2 --design-generation 27
  swift scripts/build-icon.swift .build/clara-composer.png .build/Clara.iconset --rendered
  iconutil -c icns .build/Clara.iconset -o "$APP/Contents/Resources/Clara.icns"
else
  echo "Apple actool unavailable; using static icon. Install Xcode for the layered icon."
  swift scripts/build-icon.swift "Assets/Clara.icon/Assets/clara 2.png" .build/Clara.iconset
  iconutil -c icns .build/Clara.iconset -o "$APP/Contents/Resources/Clara.icns"
fi
cp .build/release/Clara "$APP/Contents/MacOS/Clara.new"
mv -f "$APP/Contents/MacOS/Clara.new" "$APP/Contents/MacOS/Clara"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Clara</string>
<key>CFBundleIdentifier</key><string>com.local.clara</string>
<key>CFBundleName</key><string>Clara</string>
<key>CFBundleDisplayName</key><string>Clara</string>
<key>CFBundleIconFile</key><string>Clara.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict>
<key>NSAllowsArbitraryLoadsInWebContent</key><true/>
<key>NSAllowsLocalNetworking</key><true/>
</dict>
</dict></plist>
PLIST
python3 - "$APP/Contents/Info.plist" <<'PYVERSION'
import pathlib, plistlib, re, sys
version = pathlib.Path("VERSION").read_text().strip()
build = pathlib.Path("BUILD_NUMBER").read_text().strip()
repository = pathlib.Path("UPDATE_REPOSITORY").read_text().strip()
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
assert build.isdigit()
assert re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository)
with open(sys.argv[1], "rb") as f: info = plistlib.load(f)
info.update(CFBundleShortVersionString=version, CFBundleVersion=build, ClaraUpdateRepository=repository)
with open(sys.argv[1], "wb") as f: plistlib.dump(info, f)
PYVERSION
if [[ "$NATIVE_ICON" == 1 ]]; then
  python3 - "$APP/Contents/Info.plist" "$PWD/.build/clara-icon-info.plist" <<'PYICON'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
with open(sys.argv[2], "rb") as source:
    compiled = plistlib.load(source)
info.pop("CFBundleIconFile", None)
info.update(compiled)
info["CFBundleIconName"] = "Clara"
with open(sys.argv[1], "wb") as destination:
    plistlib.dump(info, destination)
PYICON
fi
codesign --force --deep --sign - "$APP"
echo "Built $APP"
