#!/usr/bin/env bash
# lock-status.sh - one line of state for the lock screen:
#
#   battery    headset battery    temperature    today's range
#
# hyprlock has no widget that reads anything; a label runs a command and draws
# what it prints. Called as cmd[update:60000], so once a minute while locked
# and never otherwise, and every reading is either sysfs or a cache the bar
# already fills.

set -uo pipefail

# Nerd Font code points as escapes, not literals: an astral-plane glyph pasted
# into a file is one re-encoding away from being a box. Only code points
# Theme.qml has already rendered and checked are used.
glyph() { local h; printf -v h '%08X' "$1"; printf "\\U$h"; }

BATTERY_FULL=0x000F0079      # md-battery, also the base of the ten-step run
BATTERY_CHARGING=0x000F0084  # md-battery-charging-100
BATTERY_EMPTY=0x000F008E     # md-battery-outline
BLUETOOTH=0x000F00AF         # md-bluetooth

parts=()

# This machine's battery, from sysfs rather than upower: the lock screen can be
# the first thing drawn after a resume, when the bus is not answering yet.
for bat in /sys/class/power_supply/BAT*; do
    [[ -r "$bat/capacity" ]] || continue
    level=$(<"$bat/capacity")
    [[ "$level" =~ ^[0-9]+$ ]] || continue
    state=$(cat "$bat/status" 2>/dev/null || echo Unknown)

    # The arithmetic Theme.batteryIcon does, and it names both ends separately
    # for the same reason: the charging run has no full glyph and the
    # discharging run has no empty one.
    step=$(( (level + 5) / 10 ))
    (( step > 10 )) && step=10
    if [[ "$state" == "Charging" ]]; then
        icon=$(glyph "$BATTERY_CHARGING")
    elif (( step >= 10 )); then
        icon=$(glyph "$BATTERY_FULL")
    elif (( step <= 0 )); then
        icon=$(glyph "$BATTERY_EMPTY")
    else
        icon=$(glyph $(( BATTERY_FULL + step )))
    fi
    parts+=("$icon $level%")
    break
done

# A connected headset, only when it reports a level. Earbuds in their case are
# not connected, and "0%" for those is worse than not mentioning them.
if command -v upower >/dev/null 2>&1; then
    for dev in $(upower -e 2>/dev/null | grep -iE 'headset|headphone'); do
        level=$(timeout 2 upower -i "$dev" 2>/dev/null | sed -n 's/.*percentage: *\([0-9]\+\)%.*/\1/p' | head -1)
        [[ "$level" =~ ^[0-9]+$ ]] || continue
        parts+=("$(glyph "$BLUETOOTH") $level%")
        break
    done
fi

# The weather, through weather.sh. Its URL is Open-Meteo, fixed in that script
# and reached over https -- a source this configuration chose, unlike the
# cover-art URL in lock-media.sh, which is chosen by whatever is playing.
#
# The TTL is raised so a lock screen almost always answers from the cache the
# bar filled, and the timeout is there because a label that stalls is a hole
# in the screen. Failing means no weather, not a delay.
SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WEATHER="$SCRIPTS/../../quickshell/bar/scripts/weather.sh"
[[ -x "$WEATHER" ]] || WEATHER="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar/scripts/weather.sh"

if [[ -x "$WEATHER" ]] && command -v jq >/dev/null 2>&1; then
    if json=$(WEATHER_CACHE_TTL=1800 timeout 4 "$WEATHER" --bar 2>/dev/null) && [[ -n "$json" ]]; then
        temp=$(jq -r '.temp // empty' <<<"$json" 2>/dev/null)
        low=$(jq -r '.today.min // empty' <<<"$json" 2>/dev/null)
        high=$(jq -r '.today.max // empty' <<<"$json" 2>/dev/null)
        [[ -n "$temp" ]] && parts+=("${temp}°C")
        [[ -n "$low" && -n "$high" ]] && parts+=("${low}° / ${high}°")
    fi
fi

# Nothing to say is said with nothing: an empty label draws no box.
(( ${#parts[@]} )) || exit 0

printf '%s' "${parts[0]}"
for (( i = 1; i < ${#parts[@]}; i++ )); do
    printf '   %s' "${parts[i]}"
done
printf '\n'
