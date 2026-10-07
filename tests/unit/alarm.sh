#!/usr/bin/env bash
# Tests quickshell/bar/scripts/alarm.sh against a temporary XDG_STATE_HOME:
# adding, listing, removing, the bar's reap, and that a failed edit never
# replaces the state file with nothing.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO/quickshell/bar/scripts/alarm.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP  alarm: jq is not installed"; exit 0; }
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
export XDG_STATE_HOME="$WORK/state"
STATE="$WORK/state/quickshell-bar/alarms.json"

failed=0
passed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  alarm: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}
run() { "$SCRIPT" "$@" 2>/dev/null; }

ok "an empty list" "$(run list)" "no alarms"
run in 30m tea >/dev/null; ok "in" "$?" 0
ok "in: one alarm" "$(jq -r '.[0].label + " " + (.[0].daily | tostring)' "$STATE")" "tea false"
left=$(( $(jq '.[0].epoch' "$STATE") - $(date +%s) ))
ok "in: thirty minutes ahead" "$(( left > 1790 && left <= 1800 ))" 1
run add 07:30 --daily wake up >/dev/null; ok "add" "$?" 0
ok "add: daily with its label" "$(jq -r '.[1].label + " " + (.[1].daily | tostring)' "$STATE")" "wake up true"
ok "add: next 07:30" "$(date -d "@$(jq '.[1].epoch' "$STATE")" +%H:%M)" "07:30"
run add 25:00 x; ok "add: a time that is no time" "$?" 2
run in soon x; ok "in: a span that is no span" "$?" 2
ok "list: two" "$(run list | wc -l)" 2

# remove takes a prefix of the id and refuses an ambiguous one.
printf '[{"id":"1111aaaa","at":"07:00","label":"a","epoch":4102444800,"daily":false,"fired":false},
         {"id":"1111bbbb","at":"08:00","label":"b","epoch":4102448400,"daily":false,"fired":false}]\n' > "$STATE"
run remove 1111; ok "remove: an ambiguous prefix" "$?" 1
ok "remove: nothing went" "$(jq length "$STATE")" 2
run remove 1111b >/dev/null; ok "remove: a unique prefix" "$?" 0
ok "remove: the other stays" "$(jq -r '.[0].label' "$STATE")" "a"
run remove 9999; ok "remove: no match" "$?" 1

# reap: a daily alarm rolls past now, a one-off that just rang goes, an old
# one-off that never rang is kept and marked, a future one is left alone.
now=$(date +%s)
printf '[{"id":"d","at":"x","label":"daily","epoch":%s,"daily":true,"fired":true},
         {"id":"r","at":"x","label":"rang","epoch":%s,"daily":false,"fired":false},
         {"id":"m","at":"x","label":"missed","epoch":%s,"daily":false,"fired":false},
         {"id":"f","at":"x","label":"future","epoch":%s,"daily":false,"fired":false}]\n' \
    $((now - 2 * 86400 - 60)) $((now - 100)) $((now - 1000)) $((now + 600)) > "$STATE"
run reap; ok "reap" "$?" 0
ok "reap: what is left" "$(jq -r '[.[].label] | join(" ")' "$STATE")" "daily missed future"
daily=$(jq '.[0].epoch' "$STATE")
ok "reap: the daily one is ahead, within a day" "$(( daily > now && daily <= now + 86400 ))" 1
ok "reap: the daily one is not fired" "$(jq '.[0].fired' "$STATE")" false
ok "reap: the missed one is marked" "$(jq '.[1].fired' "$STATE")" true

# A state file jq cannot read stays as it is.
printf 'not json\n' > "$STATE"
run in 5m x; ok "a broken file: the edit fails" "$?" 1
ok "a broken file: it is left alone" "$(cat "$STATE")" "not json"

run clear >/dev/null; ok "clear" "$(cat "$STATE")" "[]"

if (( failed == 0 )); then
    echo "PASS  alarm: $passed checks"
    exit 0
fi
exit 1
