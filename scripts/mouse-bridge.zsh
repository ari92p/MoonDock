#!/bin/zsh
# Only process/service lifecycle is inspected. No input events are captured.
domain="gui/$(/usr/bin/id -u)"
agent="/Library/LaunchAgents/com.logi.optionsplus.plist"
support="$HOME/Library/Application Support/Moonlight4K"
marker="$support/logitech-paused"
sane_marker="$support/sanesidebuttons-paused"
/bin/mkdir -p "$support"

restore_mouse_tools() {
    if [[ -f "$marker" ]]; then
        if /bin/launchctl print "$domain/com.logi.cp-dev-mgr" >/dev/null 2>&1 || /bin/launchctl bootstrap "$domain" "$agent" >/dev/null 2>&1; then
            /bin/rm -f "$marker"
        fi
    fi
    if [[ -f "$sane_marker" ]]; then
        if /usr/bin/pgrep -x SaneSideButtons >/dev/null 2>&1 || /usr/bin/open -gj -b com.janhuelsmann.SaneSideButtons >/dev/null 2>&1; then
            /bin/rm -f "$sane_marker"
        fi
    fi
}
trap 'restore_mouse_tools; exit 0' TERM INT HUP
while true; do
    if /usr/bin/pgrep -x Moonlight >/dev/null 2>&1; then
        # Recheck the real service, even if a marker already exists: the updater
        # or another launcher may have restarted Logitech during this session.
        if /bin/launchctl print "$domain/com.logi.cp-dev-mgr" >/dev/null 2>&1; then
            /usr/bin/touch "$marker"
            /bin/launchctl bootout "$domain" "$agent" >/dev/null 2>&1 || true
        fi
        if /usr/bin/pgrep -x SaneSideButtons >/dev/null 2>&1; then
            /usr/bin/touch "$sane_marker"
            /usr/bin/pkill -TERM -x SaneSideButtons >/dev/null 2>&1 || true
        fi
    else
        restore_mouse_tools
    fi
    /bin/sleep 2
done
