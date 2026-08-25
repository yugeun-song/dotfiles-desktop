#!/usr/bin/env bash
#
# Lid handling. Only the display: input devices are untouched, so the laptop
# keyboard keeps working with the lid shut.
#
# What to do depends on what else is plugged in, and it is not the same answer
# in both cases:
#
#   an external is connected   auto_monitors.sh has already disabled the
#                              internal panel, so there is nothing left to
#                              switch off here. Acting anyway would reach the
#                              external screen, which is the one being watched.
#
#   internal only              the panel is the only enabled output, so
#                              switching DPMS off reaches exactly it. That
#                              matters because hl.dsp.dpms takes an action and
#                              nothing else: there is no monitor to name, and
#                              an unqualified call is every output.
#
# DPMS rather than disabling the output. Disabling the only enabled monitor
# leaves the session with no output at all, and bringing it back is a modeset,
# which is the path this GPU hangs on. DPMS changes no mode.
#
# Usage: lid.sh close|open

set -uo pipefail

action="${1-}"

# Anything not eDP/LVDS/DSI is external. The connector type is what makes a
# panel internal, so this needs no list of this machine's monitors.
externals_enabled() {
    hyprctl -j monitors 2>/dev/null \
        | jq -e '[.[] | select(.name | test("^(eDP|LVDS|DSI)") | not)] | length > 0' >/dev/null
}

case "$action" in
    close)
        if externals_enabled; then
            # The internal panel is already off in this arrangement.
            exit 0
        fi
        hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null
        ;;
    open)
        # Unconditional. Waking an output that is already awake costs nothing,
        # and the one case that must never happen is a lid opened onto a screen
        # that stays dark.
        hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null
        ;;
    *)
        printf 'lid: usage: %s close|open\n' "${0##*/}" >&2
        exit 2
        ;;
esac
