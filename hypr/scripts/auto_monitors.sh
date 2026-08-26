#!/usr/bin/env bash
# ============================================================================
# auto_monitors.sh
#
# Arranges whatever outputs Hyprland currently sees. The rule does not depend
# on any particular monitor being present:
#
#   any external connected  -> the externals become the desktop and the
#                              internal panel is turned off
#   internal only           -> the internal panel is the desktop
#
# Nothing about the current hardware is assumed. The internal panel is
# recognised by the connector type the kernel assigns (eDP, LVDS, DSI), which
# is what makes a panel internal. Everything else is external, however many
# there are.
#
# Mode selection follows one rule: the highest refresh rate the output can do,
# and then the largest resolution available at that refresh rate. Refresh wins
# over pixels.
#
# None of Hyprland's shorthands express that. On the external panel here:
#
#   availableModes[0]  2560x1440@60    the list is not sorted usefully
#   highres            3840x2160@60    a real mode, but it costs 84Hz
#   the rule           2560x1440@144
#
# So the mode is computed rather than named. Position is still left to
# Hyprland via `auto`, which places each monitor right of the previous one and
# needs no arithmetic over scale factors.
#
# Scale is the one thing this script cannot compute, so it is the only value
# read from a file. Presets live in ~/.config/hypr/monitors.preset and are matched against
# what a display reports about itself, so a preset written for one machine is
# inert on any other. An output that matches nothing gets scale 1.
#
# Hyprland notes, still true on 0.56:
#   - hl.monitor({output=X, disabled=true}) is the only per-monitor off switch
#     that works under the Lua config, and it is asymmetric: disabled=false
#     does nothing. Re-enabling means letting `hyprctl reload` re-evaluate the
#     catch-all hl.monitor call in config/general.lua.
#   - Park before disabling. The layout validator looks at the coordinates of
#     disabled monitors and complains if one sits at 0x0 beside an active one.
#   - The watcher does not re-spawn on reload, so calling reload here is safe.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f "$0")")" && pwd)"
# Beside the installed scripts, not derived from where this file happens to be.
# The path used to come from $SCRIPT_DIR, which is readlink -f'd, so while
# ~/.config/hypr/scripts was a symlink it landed in the working tree and found a
# preset that install.sh never copied anywhere. That worked by accident and
# stopped being true the moment the scripts became real files.
PRESET_FILE="${HYPR_MONITOR_PRESET:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/monitors.preset}"
LOCAL_FILE="${HYPR_LOCAL_MONITORS:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/local.monitors}"

# make|model|scale. Make and model contain spaces, so only the ends of a line
# are trimmed; squeezing all whitespace out would make every entry unmatchable.
SCALES=()
read_scales() {
    local file="$1" line
    # A missing preset is normal: a machine with no entry wants the default of
    # 1. A preset that exists and cannot be read is not normal, and the only
    # symptom would be a wrong scale factor, so it says so.
    if [[ ! -r "$file" ]]; then
        [[ -e "$file" ]] && printf 'auto_monitors: %s exists but cannot be read; using scale 1\n' "$file" >&2
        return 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] || continue
        local rest="${line#*|}"
        if [[ "$line" != *"|"*"|"* || "${rest#*|}" == *"|"* ]]; then
            printf 'auto_monitors: %s: ignoring "%s", expected make|model|scale\n' \
                "$file" "$line" >&2
            continue
        fi
        SCALES+=("$line")
    done < "$file"
}

# Local first, so a machine that disagrees with the repository wins without
# having to edit it.
read_scales "$LOCAL_FILE"
read_scales "$PRESET_FILE"

PARK_X=20000   # far enough right that a disabled panel never overlaps

is_internal() {
    case "$1" in
        eDP-*|eDP|LVDS-*|LVDS|DSI-*|DSI) return 0 ;;
        *) return 1 ;;
    esac
}

scale_for() {
    local name="$1" make model entry rest
    make=$(printf '%s' "$mons" | jq -r --arg n "$name" '.[] | select(.name == $n) | .make // ""')
    model=$(printf '%s' "$mons" | jq -r --arg n "$name" '.[] | select(.name == $n) | .model // ""')
    for entry in ${SCALES[@]+"${SCALES[@]}"}; do
        [[ "${entry%%|*}" == "$make" ]] || continue
        rest="${entry#*|}"
        [[ "${rest%%|*}" == "$model" ]] || continue
        printf '%s' "${rest#*|}"
        return 0
    done
    printf '1'
}

# Highest refresh rate, then the largest resolution offered at it.
# Falls back to Hyprland's own "preferred" if the output reports no usable
# mode list, which happens with some virtual and remote outputs.
mode_for() {
    local name="$1" mode
    mode=$(printf '%s' "$mons" | jq -r --arg n "$name" '
        .[] | select(.name == $n) | .availableModes // []
        | map(capture("(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)Hz"))
        | map({w: (.w|tonumber), h: (.h|tonumber), r: (.r|tonumber)})
        | select(length > 0)
        | (map(.r) | max) as $top
        | map(select(.r >= $top - 0.5))
        | max_by(.w * .h)
        | "\(.w)x\(.h)@\(.r)"
    ' 2>/dev/null)
    printf '%s' "${mode:-preferred}"
}

# Two failure shapes arrive on stdout: a Lua error exits non-zero, while a
# request hyprctl never routed exits 0 and prints something other than "ok".
apply() {
    local out rc=0
    out=$(hyprctl eval "hl.monitor($1)") || rc=$?
    if (( rc != 0 )) || [[ "$out" != "ok" ]]; then
        printf 'auto_monitors: hl.monitor(%s) failed (%d): %s\n' "$1" "$rc" "$out" >&2
        return 1
    fi
}

# Applying a monitor that is already exactly where it belongs still costs a
# modeset, and a modeset is the one operation this GPU is not trusted with.
# `hyprctl reload` re-evaluates the catch-all monitor rule and the watcher
# answers that by running this script, so without this check every save of a
# configuration file paid for two of them.
#
# Only an enabled output is compared. A disabled one reports whatever it had
# before it was switched off, which is not what it would come back as.
already_placed() {
    local name="$1" position="$2" mode="$3" scale="$4"
    [[ "$mode" == "preferred" ]] && return 1
    printf '%s' "$mons" | jq -e \
        --arg n "$name" --arg pos "$position" --arg mode "$mode" --arg scale "$scale" '
        def near($a; $b): (($a - $b) | if . < 0 then -. else . end) < 0.5;
        ($mode | capture("(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)")) as $m
        | .[]
        | select(.name == $n)
        | select((.disabled // false) | not)
        | select(.width == ($m.w | tonumber) and .height == ($m.h | tonumber))
        | select(near(.refreshRate; ($m.r | tonumber)))
        | select((((.scale - ($scale | tonumber)) | if . < 0 then -. else . end) < 0.001))
        | select($pos == "auto" or ("\(.x)x\(.y)" == $pos))
    ' >/dev/null 2>&1
}

place() {
    local name="$1" position="$2"
    local mode scale
    mode=$(mode_for "$name")
    scale=$(scale_for "$name")
    if already_placed "$name" "$position" "$mode" "$scale"; then
        return 0
    fi
    apply "{output=\"$name\", mode=\"$mode\", position=\"$position\", scale=\"$scale\"}"
}

mons=$(hyprctl monitors all -j) || {
    echo "auto_monitors: hyprctl is not answering; is Hyprland running?" >&2
    exit 1
}

# A request the running compositor rejects still exits 0 and prints a plain
# text complaint, so the payload has to be checked and not just the status.
jq -e 'type == "array"' <<<"$mons" >/dev/null 2>&1 || {
    echo "auto_monitors: hyprctl returned no usable monitor JSON: ${mons:0:120}" >&2
    exit 1
}

internal=()
external=()
while IFS=$'\t' read -r name disabled; do
    [[ -n "$name" ]] || continue
    if is_internal "$name"; then
        internal+=("$name|$disabled")
    else
        external+=("$name|$disabled")
    fi
done < <(printf '%s' "$mons" | jq -r '.[] | [.name, (.disabled // false)] | @tsv')

# The jq above runs in a process substitution, whose failure the shell never
# sees; an empty result is the only symptom, and it is not a layout there is
# any correct action for.
(( ${#internal[@]} + ${#external[@]} > 0 )) || {
    echo "auto_monitors: no monitors parsed" >&2
    exit 1
}

# Sort external outputs so repeated runs produce the same arrangement.
if (( ${#external[@]} > 1 )); then
    readarray -t external < <(printf '%s\n' "${external[@]}" | sort)
fi

if (( ${#external[@]} > 0 )); then
    # The externals go up first. Switching the internal panel off before the
    # screen meant to replace it is actually working leaves a window, and on a
    # failure a whole session, with no enabled output at all. There is no way
    # back from that with a keyboard nobody can see.
    placed=0
    first=1
    for row in "${external[@]}"; do
        name="${row%%|*}"
        if (( first )); then
            if place "$name" "0x0"; then
                placed=1
                first=0
            fi
        else
            place "$name" "auto" || true
        fi
    done

    # Every external refused. The panel is still the only screen there is, so
    # it stays on: a listed output is not the same thing as a working one.
    if (( ! placed )); then
        echo "auto_monitors: no external output could be configured, keeping the internal panel" >&2
        for row in "${internal[@]}"; do
            place "${row%%|*}" "0x0" || true
        done
        exit 1
    fi

    for row in "${internal[@]}"; do
        name="${row%%|*}"
        # Already off. Parking and disabling it again is two commits for no
        # change, and every commit is a modeset.
        [[ "${row#*|}" == "true" ]] && continue
        place "$name" "${PARK_X}x0" || true
        # Parked but still enabled is the worst of both: a live output at
        # 20000x0 that windows and workspaces can be sent to and nobody sees.
        # Put it back on screen before giving up.
        apply "{output=\"$name\", disabled=true}" || {
            place "$name" "0x0" || true
            exit 1
        }
    done
    exit 0
fi

# No external output. Re-enable the panel if a previous run turned it off.
#
# The reload is allowed to fail. Under set -e a non-zero exit here would end
# the script before the place loop below, which is the only thing that puts the
# panel back on screen, and the result of that is a laptop with its lid open
# and nothing on it.
for row in "${internal[@]}"; do
    if [[ "${row#*|}" == "true" ]]; then
        hyprctl reload >/dev/null || \
            echo "auto_monitors: hyprctl reload failed, the panel may still be disabled" >&2
        break
    fi
done
for row in "${internal[@]}"; do
    place "${row%%|*}" "0x0" || true
done
