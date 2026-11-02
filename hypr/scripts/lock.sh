#!/usr/bin/env bash
# Locks with the input method switched to latin first. hyprlock binds no
# text-input protocol, so with fcitx5 in Hangul the field stays empty, PAM gets
# nothing, and pam_faillock counts each try.
#
# Lock paths reach this via `loginctl lock-session` -> hypridle lock_cmd; the
# power menu's suspend runs it directly. Never call hyprlock directly.
# Recovery: faillock --user "$USER" --reset   (no root needed)

set -uo pipefail

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

RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# The island's labels as the bar wrote them during an earlier lock
# (LockIsland.qml): gone, so this lock starts on the plain lock glyph.
island_files=("$RT/hyprlock-island-lead" "$RT/hyprlock-island-trail" "$RT/hyprlock-island-mark")
rm -f -- "${island_files[@]}"

# Sizes and colours per screen: see lock-fit.sh. Without its copy hyprlock
# reads hyprlock.conf, which draws the design's sizes and the beige on every
# screen.
fitted=()
if conf=$("$(dirname -- "${BASH_SOURCE[0]}")/lock-fit.sh"); then
    fitted=(-c "$conf")
fi

# The bar's key overlay drops keys from here to the unlock (hypridle's
# on_unlock_cmd); hypridle's own lock notice can come late. In the
# background, so the lock never waits on the bar.
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar" ipc call keys lock >/dev/null 2>&1 &

# hyprlock starts with SIGUSR2 ignored, as a child inherits that: the bar
# sends SIGUSR2 for the island's labels (LockIsland.qml), and until hyprlock
# has set its own handler the signal's default action ends the process. One
# that came that early killed the locker as it started, and the lock key
# locked nothing (2026-11-02). Ignored, an early one is dropped; the labels
# read the bar's files when hyprlock draws them anyway.
trap '' USR2
hyprlock "${fitted[@]}" "$@"
rc=$?
trap - USR2

# The unlock told to the bar at once, for its sweep of the lock screen
# (UnlockSweep.qml), which shows the last of it until then. hypridle tells it
# as soon (both reach it some 30 ms after the unlock); this one serves a
# session without hypridle, where the bar asks only every 5 s. Not after a
# crash, which leaves the session locked.
if [[ "$(hyprctl locked 2>/dev/null)" == "false" ]]; then
    qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar" ipc call keys unlock >/dev/null 2>&1 &
fi

# The lock screen's card and the covers it fetched (lock-media.py) go with
# the lock: they name what was playing. The island's labels too.
rm -rf -- "$RT/hyprlock"
rm -f -- "${island_files[@]}"

[[ "$was" == "2" ]] && fcitx5-remote -o >/dev/null 2>&1

exit "$rc"
