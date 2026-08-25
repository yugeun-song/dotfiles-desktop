#!/usr/bin/env bash
#
# Step through the workspaces that exist, and stop at the ends.
#
# Hyprland's own relative form, r+n and r-n, wraps: pressing left on the
# first workspace lands on the last one. That is a jump across the whole set
# dressed up as a step, and it happens exactly when the intent was to find
# out there is nothing further left. So the index is clamped here instead.
#
# Only regular workspaces are walked. Special workspaces have negative ids and
# are reached by their own binding, not by stepping into them by accident.
#
# Usage: workspace-walk.sh focus|move <signed step>

set -euo pipefail

# Nothing here creates a workspace, so this is a guard rather than a policy in
# force: it is the answer for whatever adds a create-and-go binding later.
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

# A special workspace is showing. Stepping from it would leave the caller on
# whatever regular workspace happens to sort next, which is not a step.
(( current < 1 )) && exit 0

mapfile -t ids < <(hyprctl -j workspaces 2>/dev/null \
    | jq -r --argjson max "$MAX_WORKSPACE" '.[] | select(.id > 0 and .id <= $max) | .id' | sort -n)
(( ${#ids[@]} > 0 )) || exit 0

index=-1
for i in "${!ids[@]}"; do
    [[ "${ids[$i]}" == "$current" ]] && { index=$i; break; }
done
(( index < 0 )) && exit 0

target=$(( index + step ))
(( target < 0 )) && target=0
(( target > ${#ids[@]} - 1 )) && target=$(( ${#ids[@]} - 1 ))
(( target == index )) && exit 0

# Lua syntax, not the plain dispatcher names. Under a Lua configuration
# hyprctl wraps the argument as hl.dispatch(<argument>) and evaluates it, so
# `hyprctl dispatch workspace 3` is a Lua parse error and this script would
# report success while doing nothing at all.
if [[ "$mode" == "focus" ]]; then
    hyprctl dispatch "hl.dsp.focus({ workspace = ${ids[$target]} })" >/dev/null
else
    hyprctl dispatch "hl.dsp.window.move({ workspace = ${ids[$target]} })" >/dev/null
fi
