#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
support="$HOME/Library/Application Support/Moonlight4K"
launch="$HOME/Library/LaunchAgents/de.mlemors.MoonlightMouseBridge.plist"
mkdir -p "$support" "$HOME/Library/LaunchAgents"
# Keep the legacy service name/path so an existing installation is updated,
# rather than starting two competing Logitech lifecycle helpers.
/bin/launchctl bootout "gui/$(id -u)" "$launch" >/dev/null 2>&1 || true
cp "$root/scripts/mouse-bridge.zsh" "$support/mouse-bridge.zsh"
chmod 755 "$support/mouse-bridge.zsh"
cat > "$launch" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>de.mlemors.MoonlightMouseBridge</string>
<key>ProgramArguments</key><array><string>/bin/zsh</string><string>$support/mouse-bridge.zsh</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>5</integer><key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
plutil -lint "$launch"
/bin/launchctl bootstrap "gui/$(id -u)" "$launch"
echo 'Installed optional Logitech and SaneSideButtons lifecycle helper.'
