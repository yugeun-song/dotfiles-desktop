#!/usr/bin/env bash
#
# Reports Caps Lock state on stdout, one line per change, and nothing while
# the state holds. The status bar starts this once and reads the stream.
#
# The kernel exposes one LED per keyboard and the node names carry an input
# index that changes when a device is replugged, so the glob is re-evaluated
# every pass rather than resolved once. `read` is a shell builtin, so a pass
# costs no processes.
#
set -u

interval="${CAPSLOCK_POLL_INTERVAL:-0.2}"
last=""

while :; do
    state=0
    for led in /sys/class/leds/*::capslock/brightness; do
        [[ -r "$led" ]] || continue
        read -r value < "$led" || continue
        if [[ "$value" != "0" ]]; then
            state=1
            break
        fi
    done

    if [[ "$state" != "$last" ]]; then
        printf '%s\n' "$state"
        last="$state"
    fi

    sleep "$interval"
done
