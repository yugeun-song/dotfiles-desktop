#!/usr/bin/env bash
#
# Reports the input method state on stdout, one line per change.
# Format:  <state>\t<input method name>
#
# fcitx5 keeps two things that both matter here: which input method is
# selected, and whether it is currently converting. With fcitx5-hangul the
# name stays "hangul" while the Hangul key toggles conversion on and off, so
# the name alone cannot tell 한 from EN.
#
# The name is only re-read when the state changes, because it almost never
# moves on its own and querying it every tick would double the work.
#
set -u

interval="${INPUTMETHOD_POLL_INTERVAL:-0.3}"
last=""

command -v fcitx5-remote >/dev/null 2>&1 || exit 0

while :; do
    state=$(fcitx5-remote 2>/dev/null) || state=""
    if [[ "$state" != "$last" ]]; then
        name=$(fcitx5-remote -n 2>/dev/null) || name=""
        printf '%s\t%s\n' "${state:-none}" "${name:-unknown}"
        last="$state"
    fi
    sleep "$interval"
done
