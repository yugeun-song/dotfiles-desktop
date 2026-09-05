#!/usr/bin/env bash
#
# Brings the session's services up, and back up.
#
# Everything with a process behind it is a systemd user unit wanted by
# hyprland-session.target (see systemd/user/). This script is the join between
# the compositor and that target. It runs from config/execs.lua when the
# compositor has started, again after a reload that finds the target down,
# and from Ctrl+Super+R; it does the same thing every time: hand the
# compositor's environment to the user manager, then make sure the target and
# everything it wants is running. Nothing here checks /proc for an existing
# copy of anything; a unit that is already active is a no-op to start, and a
# unit that died is started again.
#
# Order matters in exactly one place. The environment has to reach the user
# manager before any unit starts, because WAYLAND_DISPLAY and the instance
# signature are how those units find the compositor. This used to be two
# separate hl.exec_cmd calls, one pushing the environment and one starting the
# target, and a spawn is asynchronous: nothing ordered them. Here the push is
# a synchronous command and the start follows it.
#
# A compositor replaced underneath the session -- start-hyprland relaunches
# one that crashed -- has a new signature, and if the target is still active
# from the old one, starting it again does nothing and the bar keeps talking
# to a dead instance. The compositor itself pushes its signature into the
# manager before it is even ready, so the manager's copy cannot tell old from
# new; this script keeps its own record of which compositor it last started
# the target for, and a mismatch against an active target is a restart, which
# restarts every unit that is PartOf it.
#
# Two of these can run at once -- the reload handler and the start handler
# land together on a normal launch -- and the second one has nothing to add,
# so it leaves.

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

# The environment this runs with is the environment the units get. Run by
# hand from a terminal that was opened under a compositor that has since been
# replaced, it would push that dead compositor's variables and restart the
# target against them. The signature has to name a compositor that is alive.
#
# Alive is not yet ready. hyprland.start fires before the compositor writes
# its lock file -- 27 ms before, on the login where this was found -- and a
# script that took the missing lock for a dead compositor left that login
# with no bar, no wallpaper and no input method. What tells the two apart is
# the IPC socket: a compositor that is coming up is already listening on it,
# and one that has gone took the listener with it, whatever files remain. So
# a missing lock with a listener is waited for, briefly, and a missing lock
# without one is the refusal.
#
# And a lock that is PRESENT is not proof of life either. Hyprland unlinks the
# lock only on the clean exit path (Compositor.cpp cleanup); a crash aborts
# and leaves the file behind. A signature whose compositor crashed -- or one
# a shell inherited and outlived (a tmux server, a value exported by hand from
# a console) -- would otherwise pass on the strength of a stale file, and the
# script would push a dead display's environment and restart the whole session
# against it. So the pid named in the lock has to be alive and has to be
# Hyprland.
#
# A nested Hyprland, or a second login on another VT, is a live compositor
# that is not this session's. It is itself a Wayland client, so its exec-time
# environment carries WAYLAND_DISPLAY; the session compositor drives DRM
# directly and its own never does. Started for one of those, the script leaves
# the running session alone rather than restarting it into the nest.
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

# --all rather than a list of names: the cursor theme, the input method
# variables and the toolkit backends set in config/env.lua are wanted by the
# bar and the input method as much as WAYLAND_DISPLAY is, and a list has to be
# kept in step with that file. What the compositor has is what the session is.
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd --all \
        || fail "could not push the environment into the user manager; units may start blind"
else
    systemctl --user import-environment \
        || fail "could not push the environment into the user manager; units may start blind"
fi

# The units are whatever the target wants; the list lives in the target file
# and nowhere else. A unit that crashed while the previous compositor went
# down has used up its start limit, and a start request against it is refused
# until the interval passes. Clearing that is what lets a fresh login start it.
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

# Runtime directories of compositors that have ended.
#
# Hyprland removes hyprland.lock when it exits and leaves the directory and
# its log, on tmpfs, so they accumulate one per logout and one per run of the
# monitor self-test. The log of the session that just ended is the one worth
# keeping, so the newest leftover stays.
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

# power-profiles-daemon ships allow_active=yes for set-active-profile, so the
# active session sets this without sudo and without a prompt.
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set performance 2>/dev/null || fail "could not set the performance profile"
fi

# The portal's idea of the theme, which is what GTK applications ask.
"$SCRIPTS/gsettings-apply.sh" || fail "gsettings-apply failed"

# The output policy runs inside the compositor and re-evaluates itself on
# every hotplug. Asked once more here so that Ctrl+Super+R also applies a
# keep-internal marker that was added or removed by hand.
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl eval 'MONITORS.evaluate("session-start", false)' >/dev/null 2>&1 \
        || fail "the compositor did not take the monitor re-evaluation"
fi

(( failed )) || log "$TARGET is up for ${current:-an unknown compositor}"
exit "$failed"
