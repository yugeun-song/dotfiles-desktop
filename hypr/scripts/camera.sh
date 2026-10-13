#!/usr/bin/env bash
# The camera keys:  camera.sh [toggle|on|off]
#
# Runs camera-switch (camera/camera-switch.py) and shows what it did as a
# notification: a key press gives no other sign, and a camera that is off has
# no LED to say so. The helper's first line is the headline, the rest one line
# per camera.
#
# Which copy: the root-owned one in /usr/local/bin that install.sh's sudo step
# puts there, which its polkit action lets this session run without a
# password; else the user copy in ~/.local/bin, which still works but asks
# for an administrator password each time; else neither, and the notification
# says how to install it. CAMERA_SWITCH_SYSTEM points the tests at a stand-in
# (polkit judges the path pkexec is handed, so another path gains nothing).
set -uo pipefail

SYSTEM_COPY="${CAMERA_SWITCH_SYSTEM:-/usr/local/bin/camera-switch}"
USER_COPY="$HOME/.local/bin/camera-switch"

verb="${1:-toggle}"
case "$verb" in
    toggle|on|off) ;;
    *) echo "usage: ${0##*/} [toggle|on|off]" >&2; exit 2 ;;
esac

# Time-limited, since notify-send blocks forever without a server. When it
# fails (the bar, which is the server, is down), Hyprland's own notice says
# it instead: a privacy key must never go unanswered.
notify_now() {
    local urgency=$1 title=$2 body=$3 icon=1
    if command -v notify-send >/dev/null 2>&1 \
        && timeout 2 notify-send -u "$urgency" "$title" "$body"; then
        return 0
    fi
    [[ "$urgency" == critical ]] && icon=3
    command -v hyprctl >/dev/null 2>&1 \
        && hyprctl notify "$icon" 8000 0 "$title${body:+: ${body//$'\n'/; }}"
}
notify() {
    ( notify_now "$@" >/dev/null 2>&1 & ) 2>/dev/null
}

if [[ -x "$SYSTEM_COPY" ]]; then
    helper=$SYSTEM_COPY
elif [[ -x "$USER_COPY" ]]; then
    helper=$USER_COPY
else
    msg="camera-switch is not installed; ./install.sh puts it in place"
    echo "camera.sh: $msg" >&2
    notify critical "Camera switch" "$msg"
    exit 1
fi

# stdin from /dev/null: a Hyprland exec child inherits the compositor's tty,
# where a sudo fallback would ask for a password nobody can see.
out=$("$helper" "$verb" </dev/null 2>&1)
rc=$?

# The bar's indicator reads the new state now rather than at the device
# events, which a switch with no camera to act on never sends. Detached and
# bounded: a bar that is down or older (no camera target) changes nothing.
if command -v qs >/dev/null 2>&1; then
    ( timeout 2 qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar" ipc call camera refresh \
        >/dev/null 2>&1 & ) 2>/dev/null
fi
title=${out%%$'\n'*}
body=""
[[ "$out" == *$'\n'* ]] && body=${out#*$'\n'}
if (( rc == 0 )); then
    notify normal "$title" "$body"
else
    notify critical "${title:-Camera switch failed}" "$body"
fi
exit "$rc"
