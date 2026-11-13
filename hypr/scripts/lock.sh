#!/usr/bin/env bash
# Locks the session: with the Quickshell lock screen (quickshell/bar/lock.qml,
# the user's, 2026-11-05: it shakes at a wrong password and counts a lockout
# down), and with hyprlock when that does not hold the session within a few
# seconds; both draw hyprlock.conf's design, fitted per screen (lock-fit.sh)
# and handed to the first as JSON (lock-spec.py). The input method goes to
# latin first: hyprlock binds no text-input protocol, so with fcitx5 in Hangul
# its field stays empty, PAM gets nothing, and pam_faillock counts each try.
# The Quickshell lock takes keys without an input method at all.
#
# Lock paths reach this via `loginctl lock-session` -> hypridle lock_cmd; the
# power menu's suspend and the restart key (Ctrl+Alt+Shift+U) run it
# directly. It does nothing while a lock screen it started is running. Never
# call a locker directly.
#
# --glass: the see-through lock (the user, 2026-11-12), the same lock with
# the screen left showing what it shows, live: the compositor draws the
# desktop under it (session_lock_xray, on for this lock alone) and the
# Quickshell lock draws only a prompt (LockGlass.qml). Run straight from its
# key and the bar's rows: loginctl carries no choice of lock. Should the
# Quickshell lock not hold, hyprlock locks with the lock screen, the desktop
# out of sight, as for any lock.
# Recovery: faillock --user "$USER" --reset   (no root needed)

set -uo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
QS_LOCK="$CONFIG/quickshell/bar/lock.qml"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

glass=0
if [[ "${1:-}" == --glass ]]; then
    glass=1
    shift
fi

# One lock screen at a time: the first run holds this file locked for as long
# as it waits on its locker, and a run meanwhile leaves at once. Only this
# script holds it: nothing it starts gets the descriptor (9>&-), so a child
# left behind by a locker that died cannot keep the next lock from starting. Not a search for lockers by name: a lock screen in
# a nested compositor (the tests', a preview) is no lock of this session, and
# one such kept the lock key from locking anything (2026-11-05). A crashed
# locker lets go as it ends, so the restart key starts another, which takes
# the still locked session over (allow_session_lock_restore). Should the file
# not open, the lock goes on unguarded: locking matters more.
if { exec 9>"$RT/lock.sh.lock"; } 2>/dev/null; then
    flock -n 9 || exit 0
fi

# fcitx5-remote: 0 not running, 1 inactive, 2 active. Only 2 is restored.
state() { fcitx5-remote 2>/dev/null || echo 0; }

was=$(state)

if [[ "$was" == "2" ]]; then
    fcitx5-remote -c >/dev/null 2>&1 || true

    # -c is asynchronous; wait up to 0.5 s, then lock regardless.
    for _ in $(seq 10); do
        [[ "$(state)" != "2" ]] && break
        sleep 0.05
    done

    if [[ "$(state)" == "2" ]]; then
        printf 'lock: the input method is still active; the password field may not receive keys.\n' >&2
        printf 'lock: if the unlock fails, switch to latin with the input-method key and retry.\n' >&2
    fi
fi

# The island's parts as the bar wrote them during an earlier lock
# (LockIsland.qml): gone, so this lock starts on the plain lock glyph.
island_files=("$RT/hyprlock-island-lead" "$RT/hyprlock-island-trail" "$RT/hyprlock-island-mark" "$RT/lock-island.json")
rm -f -- "${island_files[@]}"

# The lock's card samples the cover it shows for the notch's bars here
# (LockCard.qml); private, and gone with the lock.
mkdir -m 700 -- "$RT/quickshell-lock" 2>/dev/null

# Sizes and colours per screen: see lock-fit.sh. Without its copy hyprlock
# reads hyprlock.conf, which draws the design's sizes and the beige on every
# screen, and the Quickshell lock has nothing to draw by, so hyprlock locks.
HERE=$(dirname -- "${BASH_SOURCE[0]}")
fitted=()
spec=""
if conf=$("$HERE/lock-fit.sh"); then
    fitted=(-c "$conf")
    if python3 -I "$HERE/lock-spec.py" "$conf" >"$RT/lock-spec.json.part" 2>/dev/null \
        && mv -f "$RT/lock-spec.json.part" "$RT/lock-spec.json"; then
        spec="$RT/lock-spec.json"
    fi
    rm -f -- "$RT/lock-spec.json.part"
fi

# Whether the compositor draws the desktop under the lock: only under the
# see-through lock, set before it locks and put back once it ends, so that
# the lock screen and hyprlock never have the live desktop under them, even
# after a see-through lock that was killed before it could put it back.
# Without it the see-through lock would show black, so this lock becomes the
# lock screen instead.
xray() {
    [[ "$(hyprctl eval "hl.config({ misc = { session_lock_xray = $1 } })" 2>/dev/null)" == ok* ]]
}
if (( glass )); then
    xray true || glass=0
fi
(( glass )) || xray false

# The bar's key overlay drops keys from here to the unlock (hypridle's
# on_unlock_cmd); hypridle's own lock notice can come late. In the
# background, so the lock never waits on the bar. Not for the see-through
# lock: under it the overlay would draw the password's keys in plain view,
# so the bar is told and has dropped them before the lock takes a key (2 s
# at most for a bar that does not answer). It is also told that the desktop
# stays in view (KeyFeed.qml's glass), so it keeps showing what it shows
# there.
if (( glass )); then
    timeout 2 qs -p "$CONFIG/quickshell/bar" ipc call keys glass >/dev/null 2>&1 9>&-
else
    qs -p "$CONFIG/quickshell/bar" ipc call keys lock >/dev/null 2>&1 9>&- &
fi

# The Quickshell lock, if it says within LOCK_WAIT tenths of a second that
# the compositor has the session locked by it (lock.qml writes LOCK_READY);
# else it goes and hyprlock locks, so a lock screen that fails to start never
# leaves the session open. The wait covers a cold start after boot.
LOCK_WAIT=${LOCK_WAIT:-40}
ready="$RT/lock-ready"
rm -f -- "$ready"
rc=1 held=0
if [[ -n "$spec" && -r "$QS_LOCK" ]] && command -v qs >/dev/null 2>&1; then
    # No core file and no detailed log, as bin/bar says why: this process has held
    # the password, and dropping a string does not clear its bytes. exec, so that
    # $! is the lock screen itself.
    ( ulimit -S -c 0; LOCK_SPEC="$spec" LOCK_READY="$ready" LOCK_GLASS="$glass" exec qs --no-detailed-logs -n -p "$QS_LOCK" ) >/dev/null 2>&1 9>&- &
    qpid=$!
    for _ in $(seq "$LOCK_WAIT"); do
        [[ -s "$ready" ]] && break
        kill -0 "$qpid" 2>/dev/null || break
        sleep 0.1
    done
    if [[ -s "$ready" ]] && kill -0 "$qpid" 2>/dev/null; then
        held=1
        # Until it ends. It quits a moment after the unlock; one still there
        # with the session open again is ended here, so nothing of it, its
        # memory least of all, outlives the lock (the user, 2026-11-05: what
        # it holds while locked may be large, so long as the unlock frees it).
        # The watch runs beside the wait, so a normal end is taken at once.
        (
            open=0
            while kill -0 "$qpid" 2>/dev/null; do
                if [[ "$(hyprctl locked 2>/dev/null)" == false ]]; then
                    open=$((open + 1))
                    if (( open >= 2 )); then
                        kill -TERM "$qpid" 2>/dev/null
                        sleep 1
                        kill -KILL "$qpid" 2>/dev/null
                    fi
                else
                    open=0
                fi
                sleep 2
            done
        ) 9>&- &
        watch=$!
        wait "$qpid"
        rc=$?
        kill "$watch" 2>/dev/null
        wait "$watch" 2>/dev/null
    else
        kill -KILL "$qpid" 2>/dev/null
        wait "$qpid" 2>/dev/null
        printf 'lock: the Quickshell lock screen did not lock; hyprlock locks instead.\n' >&2
    fi
fi
rm -f -- "$ready" "$RT/lock-spec.json"

# hyprlock starts with SIGUSR2 ignored, as a child inherits that: the bar
# sends SIGUSR2 for the island's labels (LockIsland.qml), and until hyprlock
# has set its own handler the signal's default action ends the process. One
# that came that early killed the locker as it started, and the lock key
# locked nothing (2026-11-02). Ignored, an early one is dropped; the labels
# read the bar's files when hyprlock draws them anyway.
if (( ! held )); then
    (( glass )) && xray false
    trap '' USR2
    ( ulimit -S -c 0; exec hyprlock "${fitted[@]}" "$@" ) 9>&-
    rc=$?
    trap - USR2
fi
(( glass )) && xray false

# The unlock told to the bar at once, for its sweep of the lock screen
# (UnlockSweep.qml), which shows the last of it until then. hypridle tells it
# as soon (both reach it some 30 ms after the unlock); this one serves a
# session without hypridle, where the bar asks only every 5 s. Not after a
# crash, which leaves the session locked.
if [[ "$(hyprctl locked 2>/dev/null)" == "false" ]]; then
    qs -p "$CONFIG/quickshell/bar" ipc call keys unlock >/dev/null 2>&1 9>&- &
fi

# The lock screen's card and the covers it fetched (lock-media.py) go with
# the lock: they name what was playing. The island's labels too.
rm -rf -- "$RT/hyprlock" "$RT/quickshell-lock"
rm -f -- "${island_files[@]}"

[[ "$was" == "2" ]] && fcitx5-remote -o >/dev/null 2>&1

exit "$rc"
