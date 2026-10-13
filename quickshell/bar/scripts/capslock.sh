#!/usr/bin/env bash
# Prints Caps Lock state on change only: 0, 1, or `-` when no LED node is
# readable (e.g. mid-replug; not the same as off). LED node names change on
# replug, so the glob is re-evaluated every pass.
set -u

# Loadable sleep builtin: avoids forking /bin/sleep five times a second.
# Arch and Debian (bash-builtins) keep it in /usr/lib/bash, Fedora and
# openSUSE in /usr/lib64/bash; without one the external sleep runs.
for _dir in /usr/lib/bash /usr/lib64/bash /usr/local/lib/bash; do
    enable -f "$_dir/sleep" sleep 2>/dev/null && break
done
unset _dir

interval="${CAPSLOCK_POLL_INTERVAL:-0.2}"
last=""

while :; do
    state=0
    found=0
    for led in /sys/class/leds/*::capslock/brightness; do
        [[ -r "$led" ]] || continue
        read -r value < "$led" || continue
        found=1
        if [[ "$value" != "0" ]]; then
            state=1
            break
        fi
    done
    (( found )) || state="-"

    if [[ "$state" != "$last" ]]; then
        printf '%s\n' "$state"
        last="$state"
    fi

    sleep "$interval"
done
