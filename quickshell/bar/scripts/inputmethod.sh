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
# An empty name is an answer, not a failure. Instance::currentInputMethod()
# returns "" and Instance::state() returns 0 when no input context is focused,
# which is every window that takes no text: a video, a viewer, the browser
# before the caret is in a field. fcitx5 is running and correct there. Only a
# failed call -- fcitx5-remote exits 1 and prints nothing -- is a no-reading.
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
        fresh=$(fcitx5-remote -n 2>/dev/null) || fresh=""
        # Kept only when there is something to keep. The engine cannot be
        # switched while no input context is focused, so the last one read is
        # still the one that will be used the moment a field takes focus.
        [[ -n "$fresh" ]] && name="$fresh"
    fi
    last_state="$state"
    n=$(( n + 1 ))

    # Only a state that could not be read at all is a no-reading. The name is
    # sent as it is, empty included: that is what "no input context" looks
    # like, and the bar says so rather than showing the failure glyph over a
    # working input method. Substituting a word for it printed a well-formed
    # line describing nothing, and "unknown" reached the bar as an engine name.
    if [[ -z "$state" ]]; then
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
