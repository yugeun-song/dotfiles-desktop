#!/usr/bin/env bash
# Stops hyprland-session.target when the compositor's hyprland.lock is deleted
# (run by hyprland-session-watch.service). Watches delete/move only: hyprctl and
# bin/unlock open that directory, so open/close events would end a live session.
# A crash can leave the lock behind; then session-start.sh sees a new signature
# after relaunch and restarts the target, and this watch with it.
# Never stop the target while the compositor lives: a failed inotify setup
# falls back to slow polling, not to stopping.

set -uo pipefail

log() { printf 'session-watch: %s\n' "$*" >&2; }

rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
lock=""

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -e "$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.lock" ]]; then
    lock="$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.lock"
else
    # Newest live instance, the same guess bin/unlock makes.
    newest=""
    for d in "$rt"/hypr/*/; do
        [[ -e "$d/hyprland.lock" ]] || continue
        [[ -z "$newest" || "$d" -nt "$newest" ]] && newest="$d"
    done
    [[ -n "$newest" ]] && lock="$newest/hyprland.lock"
fi

if [[ -z "$lock" ]]; then
    # Stay up: exiting would claim the compositor is gone, which is unknown.
    log "no running compositor found; the session target will not stop on its own"
    exec sleep infinity
fi

poll() {
    while [[ -e "$lock" ]]; do
        sleep 5
    done
}

if command -v inotifywait >/dev/null 2>&1; then
    if ! inotifywait -qq -e delete_self -e move_self "$lock"; then
        if [[ -e "$lock" ]]; then
            log "inotify watch on $lock failed; polling it every 5s instead"
            poll
        fi
    fi
else
    log "inotifywait is not installed; polling the lock every 5s instead"
    poll
fi

log "the compositor has exited; stopping hyprland-session.target"
# --no-block: this unit is PartOf the target and would wait on its own stop.
exec systemctl --user --no-block stop hyprland-session.target
