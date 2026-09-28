#!/usr/bin/env bash
# Shuts down or restarts by ending the Hyprland session first:
#
#   session-power.sh poweroff|reboot [--dry-run]
#
# Why not plain `systemctl poweroff`: with the external monitor attached, a
# shutdown started from inside the session has left this machine (Lunar Lake,
# xe) dark and deaf after userspace had finished, and only holding the power
# button down ended it. Signing out first and powering off from the greeter
# never did that. The journal shows the direct path completing every unit
# within one second, so the difference is what the compositor and the GPU
# clients are doing when the kernel shuts the device down: in the direct path
# they die in that same second, after a sign-out they are long gone. This
# script reproduces the sign-out order without the trip to the greeter.
#
# How the order is enforced: the action is requested under a logind delay
# inhibitor. logind accepts it at once but holds the shutdown transaction
# until the lock is released, for at most InhibitDelayMaxSec (5 s by default),
# which also bounds the damage should anything here hang. Inside that window
# the compositor is asked to exit and waited for; only then does the lock go.
# A failed request leaves the session untouched.
#
# Where it runs: in a transient user unit in app.slice, not in the caller's
# cgroup. bar.service and everything it spawns die with hyprland-session.target
# the moment the compositor's lock file goes, and a keybind's child sits in the
# session scope; neither reliably still holds the inhibitor while the
# compositor finishes releasing the GPU. The user manager itself stops when
# the last session ends, so both the inhibitor and the inner copy ignore
# SIGTERM, and TimeoutStopSec keeps that from holding the manager's stop for
# the default 90 s.
#
# Stages, carried in SESSION_POWER_STAGE: none (relocate into the unit), unit
# (take the inhibitor), inhibited (do the work). Each step is logged with a
# "session-power:" prefix; read it with journalctl --user -u session-power-*.

set -uo pipefail

SELF="$(readlink -f -- "${BASH_SOURCE[0]}")"
ACTION="${1:-}"
DRY_RUN=0
case "${2:-}" in
    --dry-run) DRY_RUN=1 ;;
    "") ;;
    *) echo "usage: ${0##*/} poweroff|reboot [--dry-run]" >&2; exit 2 ;;
esac
case "$ACTION" in
    poweroff|reboot) ;;
    *) echo "usage: ${0##*/} poweroff|reboot [--dry-run]" >&2; exit 2 ;;
esac

log() { printf 'session-power: %s\n' "$*" >&2; }

# Detached and time-limited: notify-send blocks forever without a server.
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    ( timeout 2 notify-send -u critical "$@" >/dev/null 2>&1 & ) 2>/dev/null
    return 0
}

STAGE="${SESSION_POWER_STAGE:-}"
UNIT="session-power-$ACTION"
(( DRY_RUN )) && UNIT="$UNIT-dryrun"

# ---------------------------------------------------------------------------
# Stage 1: move into a transient user unit that outlives the session target.
# ---------------------------------------------------------------------------
if [[ -z "$STAGE" ]]; then
    if command -v systemd-run >/dev/null 2>&1; then
        # --collect: a failed run is garbage-collected so the name is free
        # for the next attempt. A live unit of this name means an attempt is
        # already in progress; that is not an error.
        if systemctl --user is-active --quiet "$UNIT.service" 2>/dev/null; then
            log "$UNIT is already running; leaving it to that one"
            exit 0
        fi
        if systemd-run --user --collect --quiet --unit="$UNIT" \
               --property=Slice=app.slice --property=TimeoutStopSec=8s \
               --setenv=SESSION_POWER_STAGE=unit \
               --setenv=HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-}" \
               -- "$SELF" "$@"; then
            exit 0
        fi
        log "systemd-run refused; running here instead"
    fi
    # No user manager: the caller's cgroup will have to do.
    SESSION_POWER_STAGE=unit setsid -f "$SELF" "$@"
    exit 0
fi

# ---------------------------------------------------------------------------
# Stage 2: take the delay inhibitor, then run stage 3 under it.
# ---------------------------------------------------------------------------
if [[ "$STAGE" == "unit" ]]; then
    trap '' TERM
    if ! command -v systemd-inhibit >/dev/null 2>&1; then
        log "systemd-inhibit is not available; no ordering is possible, requesting $ACTION directly"
        exec systemctl "$ACTION"
    fi
    exec systemd-inhibit --what=shutdown --mode=delay --who="Hyprland session" \
        --why="ending the session before the $ACTION" \
        -- env SESSION_POWER_STAGE=inhibited "$SELF" "$@"
fi

# ---------------------------------------------------------------------------
# Stage 3, under the lock: request, then end the compositor, then release.
# ---------------------------------------------------------------------------
# Again here: systemd-inhibit resets signal dispositions in its child, so the
# ignore from stage 2 protects only systemd-inhibit itself. Everything below is
# bounded (each wait has a limit), so ignoring the manager's SIGTERM costs a
# few seconds at most, and TimeoutStopSec still ends it.
trap '' TERM

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
LOCK=""
PID=""
if [[ -n "$SIG" && -r "$RT/hypr/$SIG/hyprland.lock" ]]; then
    LOCK="$RT/hypr/$SIG/hyprland.lock"
    read -r PID < "$LOCK" 2>/dev/null
    [[ "$PID" =~ ^[0-9]+$ ]] || PID=""
fi

if (( DRY_RUN )); then
    log "dry run: would request systemctl $ACTION under the delay inhibitor"
else
    if ! systemctl "$ACTION"; then
        log "systemctl $ACTION was refused; the session stays as it is"
        notify "Could not $ACTION" "systemctl $ACTION was refused; see journalctl --user -u $UNIT"
        exit 1
    fi
    log "$ACTION accepted; ending the compositor first"
fi

if [[ -z "$PID" ]]; then
    log "no running compositor found for '${SIG:-no signature}'; the $ACTION proceeds without waiting"
    exit 0
fi
if ! command -v hyprctl >/dev/null 2>&1; then
    log "hyprctl is not installed; the $ACTION proceeds without waiting"
    exit 0
fi

# Lua syntax: hyprctl wraps its argument as hl.dispatch(<arg>), so a bare
# "exit" is nil and silently refused. Everything from here shares one
# deadline of 4.5 s after the request, inside the 5 s delay logind grants:
# the dispatch, the wait for the process (not only the lock file, which goes
# before the DRM device is released) and the settle.
if (( DRY_RUN )); then
    log "dry run: compositor pid $PID at $LOCK; would dispatch hl.dsp.exit() and wait for it"
    exit 0
fi
deadline=$(( $(date +%s%N) / 1000000 + 4500 ))
remaining() { echo $(( deadline - $(date +%s%N) / 1000000 )); }
if ! timeout 2 hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1; then
    log "the compositor did not take the exit request; the $ACTION proceeds without waiting"
    exit 0
fi

started=$(date +%s%N)
while [[ -d "/proc/$PID" ]] && (( $(remaining) > 300 )); do
    sleep 0.1
done
if [[ -d "/proc/$PID" ]]; then
    log "the compositor (pid $PID) is still running at the deadline; letting the $ACTION proceed"
    exit 0
fi
log "the compositor exited after $(( ($(date +%s%N) - started) / 1000000 )) ms; releasing the lock"
# A moment for the driver to settle on the console, within what is left.
left=$(remaining)
if (( left > 0 )); then
    sleep "$(printf '0.%03d' "$(( left > 500 ? 500 : left ))")" 2>/dev/null || true
fi
exit 0
