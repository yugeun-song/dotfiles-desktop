#!/usr/bin/env bash
#
# Waits for the compositor to exit, then takes the session target down.
#
# Run by systemd/user/hyprland-session-watch.service. Hyprland holds
# $XDG_RUNTIME_DIR/hypr/<signature>/hyprland.lock for as long as it runs and
# unlinks it on the way out, clean exit or crash handler alike, so the file is
# watched with inotify, which costs nothing until the event arrives. The watch
# is on the file's own deletion, never on it being opened or closed: hyprctl
# and bin/unlock read that directory, and a close event would have ended the
# session under a running compositor.
#
# What this covers: every exit that unlinks the lock. What it does not cover:
# a compositor killed hard enough to leave the lock behind, which the launcher
# relaunches; session-start.sh then sees a compositor it has not started the
# target for and restarts it, which restarts this watch against the new lock.
# A compositor that hangs keeps its lock, and then the session is indeed
# still there.
#
# The one thing this must never do is stop the target while the compositor
# is alive: that ends the bar, the input method and the lock screen under the
# user. So only a watch that reports the deletion counts. A watch that fails
# to be set up -- inotify instances exhausted, the file gone between the test
# and the call -- says nothing about the compositor, and falls back to
# polling the lock. Slowly, because this is the fallback, and the only cost of
# a slow answer is a service that outlives the compositor by a few seconds.

set -uo pipefail

log() { printf 'session-watch: %s\n' "$*" >&2; }

rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
lock=""

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -e "$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.lock" ]]; then
    lock="$rt/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/hyprland.lock"
else
    # No usable signature in the environment. The newest live instance is
    # the one this session belongs to, which is what bin/unlock assumes too.
    newest=""
    for d in "$rt"/hypr/*/; do
        [[ -e "$d/hyprland.lock" ]] || continue
        [[ -z "$newest" || "$d" -nt "$newest" ]] && newest="$d"
    done
    [[ -n "$newest" ]] && lock="$newest/hyprland.lock"
fi

if [[ -z "$lock" ]]; then
    # Nothing to watch means nothing to end. Staying up rather than exiting,
    # because exiting would read as "the compositor is gone" to anyone
    # watching this unit, and that is the one thing not known here.
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
# --no-block: this unit is PartOf the target it is stopping, so waiting for
# the job would mean waiting for our own termination.
exec systemctl --user --no-block stop hyprland-session.target
