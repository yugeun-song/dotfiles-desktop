#!/usr/bin/env bash
# Joins the compositor to hyprland-session.target: push the compositor's
# environment into the user manager (synchronously, before any unit starts),
# then start the target. Idempotent. Called from config/execs.lua (start and
# reload handlers) and Ctrl+Super+R.
#
# A compositor relaunched by start-hyprland has a new signature while the
# target may still be active for the old one. The signature the target was
# started for is recorded in $STARTED_FOR; a mismatch restarts the target.
# flock: the start and reload handlers can fire together.

set -uo pipefail

SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET=hyprland-session.target
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STARTED_FOR="$RT/hyprland-session.started-for"
failed=0

log() { printf 'session-start: %s\n' "$*" >&2; }
fail() { log "$*"; failed=1; }

if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl is not available; nothing starts"
    exit 1
fi

exec {lockfd}>"$RT/hyprland-session-start.lock"
if ! flock -n "$lockfd"; then
    log "another session-start is running; leaving it to that one"
    exit 0
fi

current="${HYPRLAND_INSTANCE_SIGNATURE:-}"
previous=""
[[ -r "$STARTED_FOR" ]] && read -r previous < "$STARTED_FOR"

# The signature must name a live session compositor, or a stale environment
# (old terminal, tmux) would restart the session against a dead display:
# - hyprland.start fires before the lock file exists; a listening IPC socket
#   means "starting", so wait for the lock briefly.
# - A crash leaves the lock behind, so its pid must be alive and be Hyprland.
# - A nested or second-VT Hyprland has WAYLAND_DISPLAY in its environment; the
#   DRM session compositor does not. Leave the session alone for those.
listening() { grep -qsF -- "/hypr/$1/.socket.sock" /proc/net/unix; }
lock_pid() { local p; read -r p < "$1" 2>/dev/null; [[ "$p" =~ ^[0-9]+$ ]] && printf '%s' "$p"; }
alive() {
    local pid; pid=$(lock_pid "$1") || return 1
    [[ -n "$pid" && -r "/proc/$pid/comm" && "$(cat "/proc/$pid/comm" 2>/dev/null)" == "Hyprland" ]]
}
is_nested() {
    local pid; pid=$(lock_pid "$1") || return 1
    [[ -n "$pid" ]] && tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q '^WAYLAND_DISPLAY='
}
if [[ -n "$current" ]]; then
    lock="$RT/hypr/$current/hyprland.lock"
    waited=0
    while [[ ! -e "$lock" ]]; do
        if ! listening "$current"; then
            log "HYPRLAND_INSTANCE_SIGNATURE names no running compositor; run this from the session, or press Ctrl+Super+R"
            exit 1
        fi
        if (( waited >= 100 )); then
            log "the compositor is listening but has not written its lock file after 10 s; giving up"
            exit 1
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    (( waited )) && log "waited $((waited * 100)) ms for the compositor's lock file"
    if ! alive "$lock"; then
        log "HYPRLAND_INSTANCE_SIGNATURE names no running compositor (stale lock); run this from the session, or press Ctrl+Super+R"
        exit 1
    fi
    if is_nested "$lock"; then
        log "this is a nested compositor, not the session; leaving the running session alone"
        exit 0
    fi
fi

# --all: units need everything config/env.lua sets, not just WAYLAND_DISPLAY.
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd --all \
        || fail "could not push the environment into the user manager; units may start blind"
else
    systemctl --user import-environment \
        || fail "could not push the environment into the user manager; units may start blind"
fi

# Units that crashed with the previous compositor may have hit their start
# limit; reset-failed lets a fresh login start them.
read -r -a units <<<"$(systemctl --user show "$TARGET" -p Wants --value 2>/dev/null)"
(( ${#units[@]} )) && systemctl --user reset-failed "${units[@]}" 2>/dev/null

if [[ -n "$current" && -n "$previous" && "$previous" != "$current" ]] \
    && systemctl --user is-active --quiet "$TARGET"; then
    log "the compositor was replaced ($previous -> $current); restarting $TARGET"
    systemctl --user restart "$TARGET" || fail "could not restart $TARGET"
else
    systemctl --user start "$TARGET" || fail "could not start $TARGET"
fi
[[ -n "$current" ]] && printf '%s\n' "$current" > "$STARTED_FOR"

# Ended compositors leave their runtime dir and log on tmpfs. Keep only the
# newest (the previous session's log).
if [[ -n "$current" ]]; then
    newest=""
    for d in "$RT"/hypr/*/; do
        [[ -d "$d" && ! -e "$d/hyprland.lock" ]] || continue
        [[ -z "$newest" || "$d" -nt "$newest" ]] && newest="$d"
    done
    for d in "$RT"/hypr/*/; do
        [[ -d "$d" && ! -e "$d/hyprland.lock" && "$d" != "$newest" ]] || continue
        rm -rf -- "$d"
    done
fi

# power-profiles-daemon allows this for the active session without a prompt.
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance 2>/dev/null || fail "could not set the performance profile"
fi

"$SCRIPTS/gsettings-apply.sh" || fail "gsettings-apply failed"

# Lets Ctrl+Super+R pick up a keep-internal marker changed by hand.
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl eval 'MONITORS.evaluate("session-start", false)' >/dev/null 2>&1 \
        || fail "the compositor did not take the monitor re-evaluation"
fi

(( failed )) || log "$TARGET is up for ${current:-an unknown compositor}"
exit "$failed"
