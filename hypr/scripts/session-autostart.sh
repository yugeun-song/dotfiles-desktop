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

# The instance every check below is measured against.
#
# When it is empty this script is not running under a compositor -- a bare
# console, a --verify-config run -- and there is nothing to compare against. The
# guards then fall back to matching on the name alone, which is what they always
# did; starting a second copy of something is a smaller fault than refusing to
# start the first.
THIS_SESSION="${HYPRLAND_INSTANCE_SIGNATURE:-}"
SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

log() { printf 'session-autostart: %s\n' "$*" >&2; }

# /proc/PID/comm is capped at 15 characters, so the needle is capped too.
# Comparing the full argv instead would match this script's own command line.
# Whether a process belongs to the session running now.
#
# This is the question the two checks below used to skip, and skipping it is
# what breaks a machine that has logged out and back in without rebooting.
# Anything that survives a logout is reparented to `systemd --user` and keeps
# running with the dead session's WAYLAND_DISPLAY. At the next login the guards
# saw a process of the right name, reported "already running", and started
# nothing -- so the input method was bound to a compositor that no longer
# existed and the monitor watcher was listening to a socket nobody was writing
# to. Observed on 2026-08-28: fcitx5 with no signature at all, and
# auto_monitors_watcher still carrying a pid from the first boot of the day,
# which is why the external panel stayed at 60 Hz and the internal one never
# took its 1.5 scale.
#
# Every process this script starts inherits HYPRLAND_INSTANCE_SIGNATURE, so a
# mismatch or an absence means it is not ours.
same_session() {
    local pid="$1" sig
    [[ -n "$THIS_SESSION" ]] || return 0

    # Unreadable counts as ours, and the opposite choice is made in
    # reap_previous_session on purpose.
    #
    # /proc/<pid>/environ is not always readable even for a process of your own
    # -- the polkit agent is one. Called from the guards, an unreadable answer
    # meaning "not ours" makes this script start a second copy of something that
    # is already there, and it did: one run left two authentication agents. Read
    # the other way it might skip a start that was needed, which the next
    # Ctrl+Super+R fixes. A duplicate does not fix itself.
    [[ -r "/proc/$pid/environ" ]] || return 0

    sig=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
            | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')
    [[ -n "$sig" && "$sig" == "$THIS_SESSION" ]]
}

comm_running() {
    local want="${1:0:15}" f pid
    for f in /proc/[0-9]*/comm; do
        [[ -r "$f" ]] || continue
        [[ "$(< "$f")" == "$want" ]] || continue
        pid="${f#/proc/}"; pid="${pid%/comm}"
        same_session "$pid" && return 0
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
        [[ "$cl" == *"$needle"* ]] || continue
        same_session "$pid" && return 0
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
    setsid -f "$@" >/dev/null 2>&1

    # The `|| log` that used to be on that line never fired. setsid -f forks and
    # returns before the child has execed, so its exit status reports on setsid
    # and says nothing about the program: starting a binary that does not exist
    # still gave rc=0. Every failed autostart was silent. Ask /proc instead.
    #
    # Checked before the first sleep, so a program already up costs nothing. The
    # bar takes about a second to bring its own child up, which is why the
    # budget is three seconds rather than two.
    local i
    for i in $(seq 15); do
        if [[ "$how" == "comm" ]]; then
            comm_running "$needle" && return 0
        else
            argv_running "$needle" && return 0
        fi
        sleep 0.2
    done
    log "$1 did not appear after starting it"
}

# The portal's idea of the theme, which is what GTK applications ask. Not a
# program to supervise, so it runs to completion here rather than going
# through start().
# Wait until the compositor can answer, and correct the signature if it points at
# an instance that has ended.
#
# Both halves were missing and both cost a session. The bar was launched before
# the wayland socket existed and Qt ended it with "Failed to create wl_display
# (No such file or directory)" four times, then the supervisor gave up on a
# crash loop. And when the compositor restarted, everything the previous one had
# started kept the old signature: quickshell drew fine, because the wayland
# socket keeps its name, while every hyprland request came back
# ServerNotFoundError, so the workspace and window pills were dead and the
# battery and memory ones were not.
#
# The socket alone is not enough to wait on -- it exists before hyprctl answers
# -- so both are checked.
wait_for_compositor() {
    local rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local wl="${WAYLAND_DISPLAY:-wayland-1}"
    local i d live

    for ((i = 0; i < 100; i++)); do
        live=""
        for d in "$rt"/hypr/*/; do
            [[ -e "$d/hyprland.lock" ]] || continue
            live="$(basename "$d")"
            break
        done

        if [[ -n "$live" && -S "$rt/$wl" ]]; then
            if [[ "$live" != "$THIS_SESSION" ]]; then
                log "the signature in the environment is not the running compositor; using the running one"
                THIS_SESSION="$live"
                export HYPRLAND_INSTANCE_SIGNATURE="$live"
            fi
            hyprctl version >/dev/null 2>&1 && return 0
        fi
        sleep 0.2
    done

    log "the compositor did not answer in 20s; starting anyway, expect the hyprland pills to be empty"
    return 1
}
wait_for_compositor

# Anything left over from a session that has ended.
#
# The guards below now refuse to count a foreign process as "already running",
# which stops this script from skipping a start it should have made. It does not
# stop the leftover from existing, and a leftover is not harmless: a second
# fcitx5 still holds a copy of the input method's D-Bus name, a second
# auto_monitors_watcher still reacts to events, and a second bar still draws
# nowhere while eating memory.
#
# So they are ended rather than tolerated. Bound to a session and outliving it,
# there is nothing a leftover can do that is wanted.
#
# By pid, never by pattern: `pkill -f fcitx5` would match this script's own
# command line, which contains the word. And only where the signature proves
# ownership -- a process carrying a DIFFERENT instance is from a session that is
# gone, and one carrying NONE was started before this compositor existed, which
# is how fcitx5 ended up bound to a dead session on 2026-08-28.
reap_previous_session() {
    [[ -n "$THIS_SESSION" ]] || return 0
    local pid comm sig want args gone=()

    for pid in /proc/[0-9]*; do
        pid="${pid#/proc/}"
        [[ "$pid" == "$SELF" ]] || [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ "$pid" == "$SELF" ]] && continue
        # A process can exit between the glob and this read.
        comm="$(< "/proc/$pid/comm" 2>/dev/null)" || continue
        [[ -n "$comm" ]] || continue

        # Ours to end, or nobody's business.
        #
        # A dry run of this loop before it was ever armed matched polkitd, pid
        # 600, running as root: the system's privilege broker, which this script
        # has no business touching and which the `*polkit*` pattern caught by
        # accident. Ownership is checked first now, and the pattern names the
        # agents rather than anything with the word in it.
        [[ -O "/proc/$pid" ]] || continue

        want=0
        case "$comm" in
            fcitx5|hyprpaper|hypridle|hyprsunset|wl-paste|qs|quickshell) want=1 ;;
            polkit-kde-au*|hyprpolkitagen*|polkit-gnome-au*|lxqt-policykit*) want=1 ;;
        esac
        if [[ $want -eq 0 ]]; then
            # Anchored: */bin/bar* would also catch `bar --stop`.
            args="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
            case "${args% }" in
                *auto_monitors_watcher*|*quickshell/bar*|*/bin/bar) want=1 ;;
            esac
        fi
        [[ $want -eq 1 ]] || continue

        # Unreadable is not foreign.
        #
        # The same dry run marked the polkit agent of the session running right
        # then, because /proc/<pid>/environ came back Permission denied and the
        # empty answer read as "no signature, therefore old". A process whose
        # environment cannot be read has said nothing about which session it
        # belongs to, and the safe reading of nothing is to leave it alone.
        [[ -r "/proc/$pid/environ" ]] || continue

        sig=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
                | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')
        [[ "$sig" == "$THIS_SESSION" ]] && continue

        gone+=("$pid")
        log "ending $comm ($pid) from a session that has finished"
        kill -TERM "$pid" 2>/dev/null
    done

    [[ ${#gone[@]} -eq 0 ]] && return 0

    # Give them a moment, then insist. A leftover that ignores TERM is exactly
    # the one that would go on holding the name its replacement needs.
    local i left
    for i in 1 2 3 4 5; do
        left=0
        for pid in "${gone[@]}"; do [[ -d "/proc/$pid" ]] && left=1; done
        [[ $left -eq 0 ]] && break
        sleep 1
    done
    for pid in "${gone[@]}"; do
        [[ -d "/proc/$pid" ]] || continue
        log "$pid did not stop on TERM, killing it"
        kill -KILL "$pid" 2>/dev/null
    done
}

# The bar's supervisor is a bash script, so its comm is "bash" and the scan
# above never sees it. It outlives the session holding the lock, and the next
# login's own bar then defers to it -- a bar that draws and answers no hyprland
# request. Ended by pidfile, and before the scan so the parent goes first.
reap_previous_bar() {
    [[ -n "$THIS_SESSION" ]] || return 0
    local pidfile="${XDG_STATE_HOME:-$HOME/.local/state}/bar/supervisor.pid"
    local sup sig i
    [[ -s "$pidfile" ]] || return 0
    read -r sup < "$pidfile" 2>/dev/null || return 0
    [[ "$sup" =~ ^[0-9]+$ ]] || return 0
    [[ -d "/proc/$sup" && -O "/proc/$sup" ]] || return 0
    # Unreadable is not foreign.
    [[ -r "/proc/$sup/environ" ]] || return 0

    sig=$(tr '\0' '\n' < "/proc/$sup/environ" 2>/dev/null \
            | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p')
    [[ "$sig" == "$THIS_SESSION" ]] && return 0

    log "ending the bar supervisor ($sup) from a session that has finished"
    kill -TERM "$sup" 2>/dev/null
    for i in 1 2 3 4 5; do
        [[ -d "/proc/$sup" ]] || return 0
        sleep 1
    done
    log "$sup did not stop on TERM, killing it"
    kill -KILL "$sup" 2>/dev/null
}

reap_previous_bar
reap_previous_session

# Runtime directories of sessions that have ended.
#
# Hyprland removes hyprland.lock when it exits and leaves the directory and its
# log. Nothing else ever clears them, so they accumulate one per logout, and
# anything that picks an instance by listing that directory picks wrong -- see
# the comment in bin/unlock, which did exactly that. The log of the session that
# just ended is the one worth keeping, so the newest leftover stays.
if [[ -n "$THIS_SESSION" ]]; then
    _keep=1
    for _d in $(ls -1dt "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/ 2>/dev/null); do
        [[ -e "$_d/hyprland.lock" ]] && continue
        if [[ $_keep -eq 1 ]]; then _keep=0; continue; fi
        rm -rf -- "$_d" && log "removed the runtime directory of an ended session: $(basename "$_d")"
    done
    unset _keep _d
fi

"$SCRIPTS/gsettings-apply.sh" || log "gsettings-apply failed"

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
