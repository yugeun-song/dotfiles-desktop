#!/usr/bin/env bash
# ============================================================================
# auto_monitors_watcher.sh
# Single entry point for the auto monitor switcher.
#
#   1. Apply auto_monitors.sh once at boot (so the first frame is correct).
#   2. Tail Hyprland's IPC socket2 forever and re-apply on every monitor
#      add/remove event (USB-C dock plug, HDMI hot-plug, lid open/close, ...).
#
# Launched by:  scripts/session-autostart.sh
# Dependencies: socat, jq (already installed under end-4 dotfiles).
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
APPLY="${SCRIPT_DIR}/auto_monitors.sh"
SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# Wait briefly for Hyprland's socket to appear (we may race with init).
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -S "$SOCKET" ]] && break
    sleep 0.1
done
[[ -S "$SOCKET" ]] || {
    echo "auto_monitors_watcher: $SOCKET never appeared after 1s" >&2
    exit 1
}

# Initial application.
"$APPLY" || echo "auto_monitors_watcher: initial apply failed ($?)" >&2

# Stream events; react to monitor add/remove and to config reloads. The
# reload case is not optional: `hyprctl reload` re-evaluates the catch-all
# hl.monitor call in config/general.lua, which switches a disabled laptop
# panel back on at whatever position it was parked at. Without this line the
# desktop silently gains a second screen nobody is looking at, and focus can
# land on it.
#
# Nothing re-spawns this script once the session is up, so a socat that dies
# would take the monitor switching with it. Reconnect instead.
delay=1
while true; do
    started=$SECONDS
    socat -U - "UNIX-CONNECT:${SOCKET}" | while IFS= read -r line; do
        case "$line" in
            monitoradded*|monitorremoved*|monitoraddedv2*|monitorremovedv2*|configreloaded*)
                # A cable that is not quite seated produces a burst of add and
                # remove events, and answering each one is a modeset each time
                # on hardware that hangs on modesets. Everything already queued
                # describes the same change, so it is drained first and the one
                # apply below reads the state they all settled at.
                while IFS= read -r -t 0.4 _; do :; done
                "$APPLY" || echo "auto_monitors_watcher: apply failed ($?)" >&2
                ;;
        esac
    done || echo "auto_monitors_watcher: event stream ended ($?)" >&2

    [[ -S "$SOCKET" ]] || {
        echo "auto_monitors_watcher: $SOCKET is gone, compositor has exited" >&2
        exit 0
    }

    # A stream that ran for a while is an ordinary disconnect; only repeated
    # immediate failures are worth backing off from.
    if (( SECONDS - started >= 10 )); then
        delay=1
    elif (( delay < 30 )); then
        delay=$(( delay * 2 ))
    fi
    sleep "$delay"
done
