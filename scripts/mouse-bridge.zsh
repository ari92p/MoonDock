#!/bin/zsh
# Only service lifecycle is inspected. No mouse or keyboard input is captured.
domain="gui/$(/usr/bin/id -u)"
agent="/Library/LaunchAgents/com.logi.optionsplus.plist"
marker="$HOME/Library/Application Support/Moonlight4K/logitech-paused"
restore_logitech() {
    if [[ -f "$marker" ]]; then
        if /bin/launchctl print "$domain/com.logi.cp-dev-mgr" >/dev/null 2>&1 || /bin/launchctl bootstrap "$domain" "$agent" >/dev/null 2>&1; then
            /bin/rm -f "$marker"
        fi
    fi
}
trap 'restore_logitech; exit 0' TERM INT HUP
while true; do
    if /usr/bin/pgrep -x Moonlight >/dev/null 2>&1; then
        if [[ ! -f "$marker" ]] && /bin/launchctl print "$domain/com.logi.cp-dev-mgr" >/dev/null 2>&1; then
            /usr/bin/touch "$marker"
            if ! /bin/launchctl bootout "$domain" "$agent" >/dev/null 2>&1; then
                /bin/rm -f "$marker"
            fi
        fi
    else
        restore_logitech
    fi
    /bin/sleep 2
done
