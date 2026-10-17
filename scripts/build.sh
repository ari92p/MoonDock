#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d /private/tmp/moondock-build.XXXXXX)"
app="$stage/MoonDock.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$root/build"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
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
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" \
  --identifier de.mlemors.Moonlight4K "$app"
codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --norsrc --keepParent "$app" "$root/build/MoonDock.zip"
printf '%s\n' "$app" > "$root/build/app-path.txt"
printf 'Built %s\nArchive: %s\n' "$app" "$root/build/MoonDock.zip"
