#!/usr/bin/env bash
#
# Starts the session's background programs, exactly once each.
#
# Hyprland re-runs its exec blocks on every `hyprctl reload`, so an exec list
# written the obvious way accumulates a second clipboard watcher, a second
# idle daemon and so on every time the config is touched. Worse, restarting
# the input method costs every running client its input context: the terminal
# you already had open stops accepting Korean and cannot be talked back into
# it. So nothing here is started if it is already there.
#
# Anything missing from the system is reported and skipped rather than
# failing the rest of the list.

set -uo pipefail

SELF=$$
SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

log() { printf 'session-autostart: %s\n' "$*" >&2; }

# /proc/PID/comm is capped at 15 characters, so the needle is capped too.
# Comparing the full argv instead would match this script's own command line.
comm_running() {
    local want="${1:0:15}" f
    for f in /proc/[0-9]*/comm; do
        [[ -r "$f" ]] || continue
        [[ "$(< "$f")" == "$want" ]] && return 0
    done
    return 1
}

# For programs told apart by their arguments rather than their name, such as
# the two clipboard watchers.
argv_running() {
    local needle="$1" pid cl
    for pid in /proc/[0-9]*; do
        pid="${pid#/proc/}"
        [[ "$pid" == "$SELF" ]] && continue
        [[ -r "/proc/$pid/cmdline" ]] || continue
        cl="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" || continue
        [[ "$cl" == *"$needle"* ]] && return 0
    done
    return 1
}

# start <how> <needle> <command...>
#   how: comm | argv
start() {
    local how="$1" needle="$2"
    shift 2

    if ! command -v "$1" >/dev/null 2>&1; then
        log "$1 is not installed, skipping"
        return 0
    fi

    if [[ "$how" == "comm" ]]; then
        if comm_running "$needle"; then
            log "$needle already running"
            return 0
        fi
    elif argv_running "$needle"; then
        log "$needle already running"
        return 0
    fi

    log "starting $*"
    setsid -f "$@" >/dev/null 2>&1 || log "failed to start $1"
}

# Outputs first, so the first frame lands on the right screen.
start argv "auto_monitors_watcher" "$SCRIPTS/auto_monitors_watcher.sh"

# The status bar. -n makes quickshell refuse to start a second copy, which is
# a second line of defence behind the check above.
QS="$(command -v quickshell || command -v qs || true)"
if [[ -n "$QS" ]]; then
    start argv "quickshell/bar" "$QS" -n -p "$CONFIG/quickshell/bar"
else
    log "quickshell is not installed, no status bar"
fi

# Wallpaper. A separate program rather than something drawn by the shell: when
# the shell is restarted the desktop should still look like a desktop.
start comm "hyprpaper" hyprpaper

# Input method. Started without -r on purpose; -r replaces a running fcitx5,
# and this only runs when there is none to replace.
start comm "fcitx5" fcitx5 -d

# Idle and lock.
start comm "hypridle" hypridle

# Clipboard history, kept out of the shell so it survives a shell restart.
start argv "wl-paste --type text"  wl-paste --type text  --watch cliphist store
start argv "wl-paste --type image" wl-paste --type image --watch cliphist store

# Somewhere for anything asking for privileges to ask. Which agent is present
# depends on what the machine has; any of them answers the same interface, and
# a session with none of them simply cannot authenticate.
polkit_agent() {
    local candidate
    for candidate in \
        /usr/lib/hyprpolkitagent/hyprpolkitagent \
        /usr/lib/polkit-kde-authentication-agent-1 \
        /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
        /usr/bin/lxqt-policykit-agent
    do
        if [[ -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

if agent="$(polkit_agent)"; then
    start comm "$(basename "$agent")" "$agent"
else
    log "no polkit agent found, privileged prompts will not appear"
fi

# Night colour. Runs as a daemon and is driven later by hyprctl.
start comm "hyprsunset" hyprsunset
