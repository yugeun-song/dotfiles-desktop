#!/usr/bin/env bash
# The volume keys:  volume.sh up|down|mute|mic-mute [step]
#
# wpctl (PipeWire, what this desktop runs) first, then pactl (PulseAudio),
# then amixer (bare ALSA), so the keys work on whatever the machine has; a
# machine with none of them gets one notification instead of dead keys. The
# step is a percentage (default 2). Only wpctl can cap at 100%: pactl and
# amixer are left uncapped, as they are on those desktops.
set -uo pipefail

action="${1:-}"
step="${2:-2}"

case "$action" in
    up|down|mute|mic-mute) ;;
    *) echo "usage: ${0##*/} up|down|mute|mic-mute [step]" >&2; exit 2 ;;
esac
[[ "$step" =~ ^[0-9]+$ ]] || { echo "volume.sh: the step must be a whole percentage" >&2; exit 2; }

if command -v wpctl >/dev/null 2>&1; then
    case "$action" in
        up)       exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "${step}%+" ;;
        down)     exec wpctl set-volume @DEFAULT_AUDIO_SINK@ "${step}%-" ;;
        mute)     exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        mic-mute) exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
    esac
fi

if command -v pactl >/dev/null 2>&1; then
    case "$action" in
        up)       exec pactl set-sink-volume @DEFAULT_SINK@ "+${step}%" ;;
        down)     exec pactl set-sink-volume @DEFAULT_SINK@ "-${step}%" ;;
        mute)     exec pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
        mic-mute) exec pactl set-source-mute @DEFAULT_SOURCE@ toggle ;;
    esac
fi

if command -v amixer >/dev/null 2>&1; then
    case "$action" in
        up)       exec amixer -q set Master "${step}%+" ;;
        down)     exec amixer -q set Master "${step}%-" ;;
        mute)     exec amixer -q set Master toggle ;;
        mic-mute) exec amixer -q set Capture toggle ;;
    esac
fi

msg="no volume control found (looked for wpctl, pactl, amixer)"
echo "volume.sh: $msg" >&2
if command -v notify-send >/dev/null 2>&1; then
    ( timeout 2 notify-send -u critical "Volume keys" "$msg" >/dev/null 2>&1 & )
fi
exit 1
