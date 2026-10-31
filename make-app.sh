#!/bin/sh
# Builds EdgePin.app. LSUIElement keeps it out of the Dock and the app switcher.
set -e

cd "$(dirname "$0")"
APP=EdgePin.app
ID=com.magicilabs.edgepin

swift build -c release
BIN="$(swift build -c release --show-bin-path)/EdgePin"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EdgePin"

# Finder shows Contents/Resources/AppIcon.icns, built from icon/icon.png at
# every size macOS asks for.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for n in 16 32 128 256 512; do
	sips -z $n $n icon/icon.png --out "$ICONSET/icon_${n}x${n}.png" >/dev/null
	sips -z $((n * 2)) $((n * 2)) icon/icon.png --out "$ICONSET/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>EdgePin</string>
	<key>CFBundleDisplayName</key><string>EdgePin</string>
	<key>CFBundleIdentifier</key><string>$ID</string>
	<key>CFBundleExecutable</key><string>EdgePin</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
	<key>CFBundleVersion</key><string>${VERSION:-0.1.0}</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# macOS ties the Accessibility permission to the app's signature. An ad-hoc
# signature changes with every build, which would mean granting access again
# each time, so sign with a real certificate when there is one: SIGN_IDENTITY
# if set, else the first Apple Development certificate in the keychain. Set
# SIGN_IDENTITY to a Developer ID Application certificate for releases.
if [ -z "$SIGN_IDENTITY" ]; then
	SIGN_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
fi
TIMESTAMP=
[ "${SIGN_IDENTITY:--}" = - ] || TIMESTAMP=--timestamp
codesign --force --options runtime $TIMESTAMP -s "${SIGN_IDENTITY:--}" -i "$ID" "$APP"

echo "built $(pwd)/$APP (signed with ${SIGN_IDENTITY:-ad-hoc})"
