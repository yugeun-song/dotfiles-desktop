#!/usr/bin/env bash
# ============================================================================
# auto_monitors_watcher.sh
# Single entry point for the auto monitor switcher.
#
#   1. Apply auto_monitors.sh once at boot (so the first frame is correct).
#   2. Tail Hyprland's IPC socket2 forever and re-apply on every monitor
#      add/remove event (USB-C dock plug, HDMI hot-plug, lid open/close, ...).
#
# Launched by:  exec-once = ~/.config/hypr/custom/scripts/auto_monitors_watcher.sh
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

# Initial application.
"$APPLY" || true

# Stream events; only react to monitor add/remove. Filter early to keep
# the script idle most of the time.
exec socat -U - "UNIX-CONNECT:${SOCKET}" 2>/dev/null | while IFS= read -r line; do
    case "$line" in
        monitoradded*|monitorremoved*|monitoraddedv2*|monitorremovedv2*)
            "$APPLY" || true
            ;;
    esac
done
