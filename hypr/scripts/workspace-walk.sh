#!/usr/bin/env bash
#
# Step to the next workspace by number, and stop at the ends.
#
# Hyprland's own relative forms wrap: left from the first workspace lands on
# the last one. That is a jump across the whole set dressed up as a step, and
# it happens exactly when the intent was to find out there is nothing further
# left.
#
# Walking by number rather than over the workspaces that happen to exist,
# because an empty workspace to the right is somewhere to go: Hyprland creates
# it on arrival. Walking only the existing ones would mean the key does nothing
# at all until a second workspace has been made some other way.
#
# Usage: workspace-walk.sh focus|move <signed step>

set -euo pipefail

MIN_WORKSPACE=1
MAX_WORKSPACE="${HYPR_MAX_WORKSPACE:-100}"

mode="${1-}"
step="${2-}"

case "$mode" in
    focus|move) ;;
    *) printf 'workspace-walk: usage: %s focus|move <signed step>\n' "${0##*/}" >&2; exit 2 ;;
esac
[[ "$step" =~ ^[+-]?[0-9]+$ ]] || {
    printf 'workspace-walk: step must be a signed integer, got %s\n' "${step:-<empty>}" >&2
    exit 2
}

current=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id') || {
    printf 'workspace-walk: hyprctl is not answering\n' >&2; exit 1; }
[[ "$current" =~ ^-?[0-9]+$ ]] || {
    printf 'workspace-walk: no active workspace id\n' >&2; exit 1; }

# A special workspace is showing. Stepping from it would land on whatever
# number happens to be next, which is not a step from anywhere the user is.
(( current < MIN_WORKSPACE )) && exit 0

target=$(( current + step ))
(( target < MIN_WORKSPACE )) && target=$MIN_WORKSPACE
(( target > MAX_WORKSPACE )) && target=$MAX_WORKSPACE
(( target == current )) && exit 0

# Lua syntax, not the plain dispatcher names. Under a Lua configuration
# hyprctl wraps the argument as hl.dispatch(<argument>) and evaluates it, so
# `hyprctl dispatch workspace 3` is a parse error: it answers ok and moves
# nothing, which is indistinguishable from a key that is not bound.
if [[ "$mode" == "focus" ]]; then
    hyprctl dispatch "hl.dsp.focus({ workspace = $target })" >/dev/null
else
    hyprctl dispatch "hl.dsp.window.move({ workspace = $target })" >/dev/null
fi
