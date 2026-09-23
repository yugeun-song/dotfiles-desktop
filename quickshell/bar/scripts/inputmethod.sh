#!/usr/bin/env bash
# Prints input method state on change: <state>\t<im name>, or `-` when
# fcitx5 did not answer. fcitx5-hangul keeps the name "hangul" while toggling
# conversion, so the state (2 = converting) is what tells Hangul from latin.
# With no focused input context fcitx5 reports state 0 and an empty name; that
# is a valid reading. Only a failed fcitx5-remote call is a no-reading.
set -u

# Loadable sleep builtin: avoids a /bin/sleep fork per pass.
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

    # Re-read the name on a state change and every tenth pass (~3 s), so an
    # engine switch with no state change is still caught.
    if [[ "$state" != "$last_state" || $(( n % 10 )) -eq 0 ]]; then
        fresh=$(fcitx5-remote -n 2>/dev/null) || fresh=""
        # Keep the last non-empty name: the engine cannot change while no
        # input context is focused.
        [[ -n "$fresh" ]] && name="$fresh"
    fi
    last_state="$state"
    n=$(( n + 1 ))

    # Only an unreadable state is a no-reading; never substitute a fake name.
    if [[ -z "$state" ]]; then
        line="-"
    else
        line="${state}"$'\t'"${name}"
    fi

    if [[ "$line" != "$last" ]]; then
        printf '%s\n' "$line"
        last="$line"
    fi
    sleep "$interval"
done
