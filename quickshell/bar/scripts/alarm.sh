#!/usr/bin/env bash
#
# Manage the alarms the status bar shows and rings.
#
# State lives in one JSON file that the bar watches, so a change here shows up
# in the bar immediately without any IPC.
#
#   alarm.sh add 07:30 wake up          one-off at the next 07:30
#   alarm.sh add 07:30 --daily wake up  every day at 07:30
#   alarm.sh in 25m tea                 relative, from now
#   alarm.sh list
#   alarm.sh remove <id>
#   alarm.sh clear
#   alarm.sh reap                       drop or roll forward alarms that fired
#
# Requires: jq, date
#
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-bar"
STATE_FILE="$STATE_DIR/alarms.json"

mkdir -p "$STATE_DIR"
[[ -s "$STATE_FILE" ]] || printf '[]\n' > "$STATE_FILE"

write() {
    local tmp
    tmp=$(mktemp "$STATE_DIR/.alarms.XXXXXX") || return 1
    cat > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$STATE_FILE"
}

next_epoch_for() {
    # Interpret HH:MM as the next occurrence, today if it is still ahead.
    local at="$1" today epoch now
    now=$(date +%s)
    today=$(date -d "today $at" +%s 2>/dev/null) || return 1
    if (( today > now )); then
        epoch=$today
    else
        epoch=$(date -d "tomorrow $at" +%s) || return 1
    fi
    printf '%s' "$epoch"
}

cmd_add() {
    local at="${1:-}"; shift || true
    local daily=false
    if [[ "${1:-}" == "--daily" ]]; then
        daily=true
        shift
    fi
    local label="${*:-alarm}"

    [[ -n "$at" ]] || { echo "usage: alarm.sh add HH:MM [--daily] [label]" >&2; return 2; }

    local epoch
    epoch=$(next_epoch_for "$at") || { echo "could not parse time: $at" >&2; return 2; }

    jq --arg id "$(date +%s%N)" --arg at "$at" --arg label "$label" \
       --argjson epoch "$epoch" --argjson daily "$daily" \
       '. + [{id: $id, at: $at, label: $label, epoch: $epoch, daily: $daily, fired: false}]' \
       "$STATE_FILE" | write
    echo "added $at ($(date -d "@$epoch" '+%Y-%m-%d %H:%M')) $label"
}

cmd_in() {
    local spec="${1:-}"; shift || true
    local label="${*:-timer}"
    [[ -n "$spec" ]] || { echo "usage: alarm.sh in <30m|2h|90s> [label]" >&2; return 2; }

    local seconds
    case "$spec" in
        *s) seconds=${spec%s} ;;
        *m) seconds=$(( ${spec%m} * 60 )) ;;
        *h) seconds=$(( ${spec%h} * 3600 )) ;;
        *)  seconds=$(( spec * 60 )) ;;
    esac

    local epoch=$(( $(date +%s) + seconds ))
    jq --arg id "$(date +%s%N)" --arg at "$(date -d "@$epoch" +%H:%M)" --arg label "$label" \
       --argjson epoch "$epoch" \
       '. + [{id: $id, at: $at, label: $label, epoch: $epoch, daily: false, fired: false}]' \
       "$STATE_FILE" | write
    echo "added $(date -d "@$epoch" '+%H:%M') $label"
}

cmd_list() {
    jq -r '
        if length == 0 then "no alarms"
        else
            sort_by(.epoch)[] |
            "\(.id[0:10])  \(.at)  \(if .daily then "daily " else "once  " end)\(.label)"
        end
    ' "$STATE_FILE"
}

cmd_remove() {
    local id="${1:-}"
    [[ -n "$id" ]] || { echo "usage: alarm.sh remove <id>" >&2; return 2; }
    jq --arg id "$id" '[.[] | select((.id | startswith($id)) | not)]' "$STATE_FILE" | write
    echo "removed $id"
}

# Called by the bar after an alarm rings: repeating alarms roll to the next
# day, one-off alarms are dropped.
cmd_reap() {
    local now
    now=$(date +%s)
    jq --argjson now "$now" '
        [ .[]
          | if .epoch <= $now then
                if .daily then .epoch = (.epoch + 86400) | .fired = false
                else empty end
            else . end
        ]
    ' "$STATE_FILE" | write
}

cmd_clear() {
    printf '[]\n' | write
    echo "cleared"
}

case "${1:-list}" in
    add)    shift; cmd_add "$@" ;;
    in)     shift; cmd_in "$@" ;;
    list)   cmd_list ;;
    remove) shift; cmd_remove "$@" ;;
    reap)   cmd_reap ;;
    clear)  cmd_clear ;;
    *)      sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//' ;;
esac
