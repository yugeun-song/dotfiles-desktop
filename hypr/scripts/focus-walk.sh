#!/usr/bin/env bash
#
# Move focus in a direction, and stop at the edge.
#
# Hyprland's own movefocus wraps: from the leftmost window, left lands on the
# rightmost one. That is not a step, it is a jump across the whole workspace,
# and it happens at the moment the intent was to find out there is nothing
# further left. binds:window_direction_monitor_fallback does not govern it;
# turning that off changes nothing here.
#
# So the question is asked first: is there a window that way at all? If not,
# nothing happens. If there is, Hyprland decides which one, because the layout
# knows things about adjacency that comparing centres does not.
#
# Moving a window is the same question with the same answer: at the edge there
# is nothing to swap with, so nothing should move.
#
# Usage: focus-walk.sh focus|move <l|r|u|d>

set -euo pipefail

mode="${1-}"
dir="${2-}"
case "$mode" in
    focus|move) ;;
    *) printf 'focus-walk: usage: %s focus|move <l|r|u|d>\n' "${0##*/}" >&2; exit 2 ;;
esac
case "$dir" in
    l|r|u|d) ;;
    *) printf 'focus-walk: direction must be l, r, u or d, got %s\n' "${dir:-<empty>}" >&2; exit 2 ;;
esac

active=$(hyprctl -j activewindow 2>/dev/null) || {
    printf 'focus-walk: hyprctl is not answering\n' >&2; exit 1; }

# No focused window is not a failure. There is simply nowhere to step from.
[[ "$(jq -r '.address // "null"' <<<"$active")" == "null" ]] && exit 0

read -r ws cx cy < <(jq -r '"\(.workspace.id) \(.at[0] + .size[0] / 2) \(.at[1] + .size[1] / 2)"' <<<"$active")

# Only what is on this workspace and actually on screen. A hidden or unmapped
# window is not somewhere focus can go.
case "$dir" in
    l) test='.cx < $cx' ;;
    r) test='.cx > $cx' ;;
    u) test='.cy < $cy' ;;
    d) test='.cy > $cy' ;;
esac

count=$(hyprctl -j clients 2>/dev/null | jq --argjson ws "$ws" --argjson cx "$cx" --argjson cy "$cy" "
    [ .[]
      | select(.workspace.id == \$ws and .mapped and (.hidden | not))
      | { cx: (.at[0] + .size[0] / 2), cy: (.at[1] + .size[1] / 2) }
      | select($test)
    ] | length")

(( count > 0 )) || exit 0

if [[ "$mode" == "focus" ]]; then
    hyprctl dispatch "hl.dsp.focus({ direction = \"$dir\" })" >/dev/null
else
    hyprctl dispatch "hl.dsp.window.move({ direction = \"$dir\" })" >/dev/null
fi
