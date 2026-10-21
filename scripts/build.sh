#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d /private/tmp/moondock-build.XXXXXX)"
app="$stage/MoonDock.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$root/build"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
for strings in "$root"/Resources/*.lproj/Localizable.strings; do
  plutil -lint -s "$strings"
  lproj="$(basename "$(dirname "$strings")")"
  mkdir -p "$app/Contents/Resources/$lproj"
  cp "$strings" "$app/Contents/Resources/$lproj/"
done
xcrun swiftc "$root/Sources/MoonDock.swift" \
  -module-cache-path "$stage/swift-cache" \
  -o "$app/Contents/MacOS/MoonDock" \
  -framework AppKit -framework CoreGraphics -framework Carbon -framework ApplicationServices
xcrun swiftc "$root/scripts/render-app-icon.swift" \
  -module-cache-path "$stage/swift-cache" \
  -o "$stage/render-app-icon" -framework AppKit
"$stage/render-app-icon" "$stage/MoonDock.iconset"
/usr/bin/iconutil -c icns -o "$app/Contents/Resources/MoonDock.icns" "$stage/MoonDock.iconset"
cp "$stage/MoonDock.iconset/icon_512x512@2x.png" "$root/build/MoonDock-icon.png"
# A stable identity keeps the Accessibility permission across updates.
# Ad-hoc signatures change with every build and need the permission re-granted.
identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" && -f "$root/signing-identity.local" ]]; then
  identity="$(head -n 1 "$root/signing-identity.local" | tr -d '[:space:]')"
fi
if [[ -z "$identity" ]]; then
  identity="-"
  echo 'No signing identity configured; signing ad-hoc (see README, "Code signing").' >&2
fi
codesign --force --timestamp=none --sign "$identity" \
  --identifier de.mlemors.Moonlight4K "$app"
codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --norsrc --keepParent "$app" "$root/build/MoonDock.zip"
printf '%s\n' "$app" > "$root/build/app-path.txt"
printf 'Built %s\nArchive: %s\n' "$app" "$root/build/MoonDock.zip"
