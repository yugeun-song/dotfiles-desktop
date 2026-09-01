#!/usr/bin/env bash
#
# Reports the input method state on stdout, one line per change.
# Format:  <state>\t<input method name>, or `-` when fcitx5 did not answer.
#
# fcitx5 keeps two things that both matter here: which input method is
# selected, and whether it is currently converting. With fcitx5-hangul the
# name stays "hangul" while the Hangul key toggles conversion on and off, so
# the name alone cannot tell 한 from EN.
#
# Both halves are read every pass. Reading the name only on a state change was
# half the work and wrong: switching engine without changing state, hangul to
# mozc with both idle, left the old name on the line for as long as the session
# lasted, and the pill decides latin from that name.
#
set -u

# Same reason as capslock.sh: without the loadable, every pass forks
# /bin/sleep on top of the queries below.
enable -f /usr/lib/bash/sleep sleep 2>/dev/null || true

interval="${INPUTMETHOD_POLL_INTERVAL:-0.3}"
last=""
last_state=""
name=""
n=0

command -v fcitx5-remote >/dev/null 2>&1 || {
    echo "inputmethod.sh: fcitx5-remote not found on PATH; IME indicator disabled" >&2
    exit 1
}

while :; do
    state=$(fcitx5-remote 2>/dev/null) || state=""

    # The name is the expensive half and the half that rarely moves.
    # It is re-read when the state changes, which is where an engine
    # switch shows up, and once every ten passes so that a switch made
    # with both engines idle is still noticed within three seconds.
    if [[ "$state" != "$last_state" || $(( n % 10 )) -eq 0 ]]; then
        name=$(fcitx5-remote -n 2>/dev/null) || name=""
    fi
    last_state="$state"
    n=$(( n + 1 ))

    # A line goes out only when both halves are real. Substituting "none" and
    # "unknown" for a failed query printed a well-formed line describing
    # nothing, and the literal word "unknown" reached the bar as an engine
    # name. "-" is the no-reading token, the same one capslock.sh uses.
    if [[ -z "$state" || -z "$name" ]]; then
        line="-"
    else
        line="${state}"$'\t'"${name}"
    fi

    # Still deduplicated, so the reader is woken on a change and not on a tick.
    if [[ "$line" != "$last" ]]; then
        printf '%s\n' "$line"
        last="$line"
    fi
    sleep "$interval"
done
