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
    # A jq that fails upstream sends nothing down the pipe, and an empty file
    # moved into place would erase every alarm without a word.
    jq -e . "$tmp" > /dev/null 2>&1 || { rm -f "$tmp"; return 1; }
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
    local words=() word
    for word in "$@"; do
        case "$word" in
            --daily) daily=true ;;
            --*)     echo "usage: alarm.sh add HH:MM [--daily] [label]" >&2; return 2 ;;
            *)       words+=("$word") ;;
        esac
    done
    local label="${words[*]:-alarm}"

    [[ -n "$at" ]] || { echo "usage: alarm.sh add HH:MM [--daily] [label]" >&2; return 2; }

    local epoch
    epoch=$(next_epoch_for "$at") || { echo "could not parse time: $at" >&2; return 2; }

    jq --arg id "$(date +%s%N)" --arg at "$at" --arg label "$label" \
       --argjson epoch "$epoch" --argjson daily "$daily" \
       '. + [{id: $id, at: $at, label: $label, epoch: $epoch, daily: $daily, fired: false}]' \
       "$STATE_FILE" | write || { echo "could not save alarm" >&2; return 1; }
    # Day before month, the order every human-readable date in this repository
    # uses. File names keep the sortable one; this is not a file name.
    echo "added $at ($(date -d "@$epoch" '+%-d %b %Y %H:%M')) $label"
}

cmd_in() {
    local spec="${1:-}"; shift || true
    local label="${*:-timer}"
    [[ "$spec" =~ ^[0-9]+[smh]?$ ]] || { echo "usage: alarm.sh in <30m|2h|90s> [label]" >&2; return 2; }

    # 10# so a leading zero is not taken for octal.
    local seconds
    case "$spec" in
        *s) seconds=$(( 10#${spec%s} )) ;;
        *m) seconds=$(( 10#${spec%m} * 60 )) ;;
        *h) seconds=$(( 10#${spec%h} * 3600 )) ;;
        *)  seconds=$(( 10#$spec * 60 )) ;;
    esac

    local epoch=$(( $(date +%s) + seconds ))
    jq --arg id "$(date +%s%N)" --arg at "$(date -d "@$epoch" +%H:%M)" --arg label "$label" \
       --argjson epoch "$epoch" \
       '. + [{id: $id, at: $at, label: $label, epoch: $epoch, daily: false, fired: false}]' \
       "$STATE_FILE" | write || { echo "could not save alarm" >&2; return 1; }
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

    # The id is matched by prefix, so a short one can cover the whole list.
    # Refuse anything but a single hit rather than deleting more than asked.
    local matches
    matches=$(jq --arg id "$id" '[.[] | select(.id | startswith($id))] | length' "$STATE_FILE") || return 1
    if [[ "$matches" == 0 ]]; then
        echo "no alarm matches $id" >&2
        return 1
    elif [[ "$matches" != 1 ]]; then
        echo "$id matches $matches alarms:" >&2
        jq -r --arg id "$id" '.[] | select(.id | startswith($id)) | "  \(.id)  \(.at)  \(.label)"' "$STATE_FILE" >&2
        return 1
    fi

    jq --arg id "$id" '[.[] | select((.id | startswith($id)) | not)]' "$STATE_FILE" | write \
        || { echo "could not save alarms" >&2; return 1; }
    echo "removed $id"
}

# Called by the bar after an alarm rings: repeating alarms roll forward, one-off
# alarms are dropped. A daily alarm missed while the machine was off is days
# behind, so it has to be stepped until it lands ahead of now, not by one day.
# Only a one-off inside the bar's 300s ring window is dropped: one that went
# past while the bar was down never rang, and deleting it here would lose it
# with nothing shown to the user.
cmd_reap() {
    local now
    now=$(date +%s)
    jq --argjson now "$now" '
        [ .[]
          | if .epoch <= $now then
                if .daily then (.epoch |= until(. > $now; . + 86400)) | .fired = false
                elif $now - .epoch < 300 then empty
                else . end
            else . end
        ]
    ' "$STATE_FILE" | write
}

cmd_clear() {
    printf '[]\n' | write || { echo "could not clear alarms" >&2; return 1; }
    echo "cleared"
}

case "${1:-list}" in
    add)    shift; cmd_add "$@" ;;
    in)     shift; cmd_in "$@" ;;
    list)   cmd_list ;;
    remove) shift; cmd_remove "$@" ;;
    reap)   cmd_reap ;;
    clear)  cmd_clear ;;
    *)      sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; exit 2 ;;
esac
