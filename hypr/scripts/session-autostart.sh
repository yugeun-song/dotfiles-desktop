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

# The portal's idea of the theme, which is what GTK applications ask. Not a
# program to supervise, so it runs to completion here rather than going
# through start().
"$SCRIPTS/gsettings-apply.sh" || log "gsettings-apply failed"

# Outputs first, so the first frame lands on the right screen.
start argv "auto_monitors_watcher" "$SCRIPTS/auto_monitors_watcher.sh"

# The status bar, under bin/bar rather than started directly. quickshell does
# crash, and an unsupervised bar stays gone until the next login; bar brings it
# back and gives up only if it is crashing in a loop. bar takes an exclusive
# lock on its pidfile, so a second one started by anything is a no-op.
#
# Started bare rather than via PATH: this runs from the compositor, not from a
# login shell, and ~/.local/bin is not reliably there.
BAR=""
# One candidate now. The second used to be "$REPO/bin/bar", where REPO was the
# working tree reached by resolving this script's own symlink; the scripts are
# real files today, so that path resolved to ~/.config and could never exist.
for candidate in "$HOME/.local/bin/bar"; do
    [[ -x "$candidate" ]] && { BAR="$candidate"; break; }
done

if [[ -n "$BAR" ]]; then
    start argv "quickshell/bar" "$BAR"
else
    # No supervisor installed. -n makes quickshell refuse a second copy, which
    # is the same guarantee without the restarts.
    QS="$(command -v quickshell || command -v qs || true)"
    if [[ -n "$QS" ]]; then
        start argv "quickshell/bar" "$QS" -n -p "$CONFIG/quickshell/bar"
    else
        log "quickshell is not installed, no status bar"
    fi
fi

# Wallpaper. A separate program rather than something drawn by the shell: when
# the shell is restarted the desktop should still look like a desktop.
start comm "hyprpaper" hyprpaper

# hyprpaper comes up with no wallpaper: its configuration cannot name the file,
# for the reason written in hypr/hyprpaper.conf. This is what puts the image on
# the screen, and it waits because IPC is refused until hyprpaper is listening.
if command -v hyprpaper >/dev/null 2>&1; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        hyprctl hyprpaper listactive >/dev/null 2>&1 && break
        sleep 0.2
    done
    "$SCRIPTS/wallpaper.sh" --reload || log "wallpaper could not be set"
fi

# Input method. Started without -r on purpose; -r replaces a running fcitx5,
# and this only runs when there is none to replace.
start comm "fcitx5" fcitx5 -d

# hypridle runs under the unit its own package ships, not from here.
#
# Every way of locking this machine is `loginctl lock-session`, which asks
# logind to emit a signal and returns. The only thing that answers that signal
# is hypridle's lock_cmd. Started from this script it had nothing watching it,
# so if it ever died the lock key, the power menu's Lock and the pre-suspend
# lock would all go on returning success while the screen stayed unlocked.
#
# The packaged unit has Restart=on-failure and WantedBy=graphical-session.target,
# which is the supervision and the ordering both. Enabled once:
#   systemctl --user enable hypridle.service
# Enable it here rather than only start it. The gate used to be is-enabled, and
# nothing in either repository ever enabled it, so on a machine that had not had
# it turned on by hand the screen simply never locked and the log line explaining
# that was the only sign. Enabling is idempotent and takes effect immediately.
if ! systemctl --user is-enabled hypridle.service >/dev/null 2>&1; then
    systemctl --user enable hypridle.service >/dev/null 2>&1 \
        || log "could not enable hypridle.service; the screen will not lock"
fi

if systemctl --user is-enabled hypridle.service >/dev/null 2>&1; then
    systemctl --user start hypridle.service 2>/dev/null \
        || log "could not start hypridle.service; the screen will not lock"
else
    log "hypridle.service is not enabled; run: systemctl --user enable --now hypridle.service"
    log "  until then nothing answers loginctl lock-session and the screen will not lock"
fi


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
