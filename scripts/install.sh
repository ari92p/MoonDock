#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if /usr/bin/pgrep -f '^/Applications/MoonDock.app/Contents/MacOS/MoonDock' >/dev/null; then
  echo 'Quit MoonDock before installing an update.' >&2
  exit 1
fi
if [[ ! -f "$root/build/app-path.txt" ]]; then "$root/scripts/build.sh"; fi
app="$(cat "$root/build/app-path.txt")"
if [[ ! -x "$app/Contents/MacOS/MoonDock" ]]; then
  echo 'Build staging directory is missing; run scripts/build.sh again.' >&2
  exit 1
fi
old_requirement="$(codesign -d -r- /Applications/MoonDock.app 2>/dev/null | sed -n 's/^designated => //p' || true)"
/usr/bin/ditto --norsrc "$app" /Applications/MoonDock.app
codesign --verify --deep --strict /Applications/MoonDock.app
printf 'Installed /Applications/MoonDock.app\n'
new_requirement="$(codesign -d -r- /Applications/MoonDock.app 2>/dev/null | sed -n 's/^designated => //p')"
if [[ "$old_requirement" != "$new_requirement" ]] || codesign -dv /Applications/MoonDock.app 2>&1 | grep -q 'Signature=adhoc'; then
  echo 'The signature changed: turn MoonDock off and on again under' >&2
  echo 'System Settings → Privacy & Security → Accessibility for ⌥⌘Tab.' >&2
fi
