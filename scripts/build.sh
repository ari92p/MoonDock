#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d /private/tmp/moondock-build.XXXXXX)"
app="$stage/MoonDock.app"
mkdir -p "$app/Contents/MacOS" "$root/build"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
xcrun swiftc "$root/Sources/MoonDock.swift" \
  -module-cache-path "$stage/swift-cache" \
  -o "$app/Contents/MacOS/MoonDock" \
  -framework AppKit -framework CoreGraphics -framework Carbon -framework ApplicationServices
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" \
  --identifier de.mlemors.Moonlight4K "$app"
codesign --verify --deep --strict "$app"
/usr/bin/ditto -c -k --norsrc --keepParent "$app" "$root/build/MoonDock.zip"
printf '%s\n' "$app" > "$root/build/app-path.txt"
printf 'Built %s\nArchive: %s\n' "$app" "$root/build/MoonDock.zip"
