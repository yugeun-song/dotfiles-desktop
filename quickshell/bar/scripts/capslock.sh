#!/usr/bin/env bash
#
# Reports Caps Lock state on stdout, one line per change, and nothing while
# the state holds. The status bar starts this once and reads the stream.
#
# The line is 0, 1, or `-` when no LED node could be read. That last case is
# not the same as off: a keyboard being replugged has no node for a moment,
# and reporting 0 there would flip the bar to a state the user never set.
#
# The kernel exposes one LED per keyboard and the node names carry an input
# index that changes when a device is replugged, so the glob is re-evaluated
# every pass rather than resolved once.
#
set -u

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
