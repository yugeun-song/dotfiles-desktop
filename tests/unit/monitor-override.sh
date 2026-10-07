#!/usr/bin/env bash
# Tests hypr/scripts/monitor-override.sh: what it accepts, and set, try, keep,
# trial, revert and clear. Its state goes to a temporary XDG_STATE_HOME and
# hyprctl is a stub that records the reload, so no compositor is touched.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO/hypr/scripts/monitor-override.sh"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/hyprctl" <<'EOF'
#!/bin/sh
echo "$*" >> "$HYPRCTL_LOG"
[ -n "$HYPRCTL_FAIL" ] && { echo "error: stub refused"; exit 1; }
echo ok
EOF
chmod +x "$WORK/bin/hyprctl"
export PATH="$WORK/bin:$PATH" XDG_STATE_HOME="$WORK/state" HYPRCTL_LOG="$WORK/hyprctl.log" HYPRCTL_FAIL=""
FILE="$WORK/state/hypr/monitor-overrides"

failed=0
passed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  monitor-override: %s: got [%s], want [%s]\n' "$1" "$2" "$3"
    fi
}
run() { "$SCRIPT" "$@" 2>/dev/null; }
put() { printf '%b' "$1" | run "${@:2}"; }

# What it accepts.
put 'name:HDMI-A-1\tscale\t1.25\n' set; ok "a valid line" "$?" 0
put 'name:HDMI-A-1\tscale\t3.5\n' set; ok "scale above 3" "$?" 2
put 'name:HDMI-A-1\tscale\t0.4\n' set; ok "scale below 0.5" "$?" 2
put 'name:HDMI-A-1\tmode\t2560x1440@144\n' set; ok "a mode without decimals" "$?" 0
put 'name:HDMI-A-1\tmode\t2560x1440\n' set; ok "a mode without a rate" "$?" 2
put 'name:HDMI-A-1\ttransform\t8\n' set; ok "transform 8" "$?" 2
put 'name:Bad Name\tscale\t1\n' set; ok "a connector name with a space" "$?" 2
put 'name:HDMI-A-1\tworkspaces\tblocks\n' set; ok "workspaces on an output" "$?" 2
put '*\tworkspaces\tblocks\n' set; ok "workspaces on *" "$?" 0
put '*\tscale\t1\n' set; ok "another field on *" "$?" 2
put 'name:HDMI-A-1\tcolour\tred\n' set; ok "an unknown field" "$?" 2
put 'name:HDMI-A-1\tscale\t1\r\n' set; ok "a carriage return" "$?" 2
put '# a comment\n\nname:HDMI-A-1\tenabled\tfalse\n' set; ok "comments and blank lines" "$?" 0
ok "refused lines leave the file" "$(cat "$FILE")" $'# a comment\n\nname:HDMI-A-1\tenabled\tfalse'

# set, then a trial that is kept.
put 'name:eDP-1\tscale\t1.5\n' set
ok "set leaves no trial" "$(run trial)" ""
put 'name:eDP-1\tscale\t2\n' try 30; ok "try" "$?" 0
left=$(run trial)
ok "try leaves a deadline" "$(( left >= 29 && left <= 30 ))" 1
ok "try writes the lines" "$(cat "$FILE")" $'name:eDP-1\tscale\t2'
run keep; ok "keep" "$?" 0
ok "keep ends the trial" "$(run trial)" ""
ok "keep keeps the lines" "$(cat "$FILE")" $'name:eDP-1\tscale\t2'

# A trial that runs out, then the revert a starting bar makes.
put 'name:eDP-1\tscale\t1.25\n' try 1
sleep 1.2
left=$(run trial)
ok "an expired trial is due" "$(( left <= 0 ))" 1
run revert; ok "revert" "$?" 0
ok "revert restores the state before the trial" "$(cat "$FILE")" $'name:eDP-1\tscale\t2'
ok "revert ends the trial" "$(run trial)" ""
run revert
ok "a second revert undoes the first" "$(cat "$FILE")" $'name:eDP-1\tscale\t1.25'

# A failed reload still leaves a trial: the file was written.
HYPRCTL_FAIL=1 put 'name:eDP-1\tscale\t1\n' try 30; ok "a refused reload" "$?" 1
ok "a refused reload keeps the trial" "$(( $(run trial) > 0 ))" 1
ok "a refused reload keeps the lines" "$(cat "$FILE")" $'name:eDP-1\tscale\t1'

# A trial that cannot be written is no trial.
put 'name:eDP-1\tscale\t2\n' try 0; ok "try 0" "$?" 2
put 'name:eDP-1\tscale\t2\n' try 10000; ok "try past the limit" "$?" 2
put 'bad\n' try 30; ok "try with a bad line" "$?" 2

# clear ends a trial too, and every write asked the compositor to re-read.
put 'name:eDP-1\tscale\t2\n' try 30
run clear; ok "clear" "$?" 0
ok "clear removes the file" "$([[ -e "$FILE" ]] && echo present || echo absent)" absent
ok "clear ends the trial" "$(run trial)" ""
ok "every reload is the policy's" "$(sort -u "$HYPRCTL_LOG")" "eval MONITORS.reload_overrides(\"override\")"

if (( failed == 0 )); then
    echo "PASS  monitor-override: $passed checks"
    exit 0
fi
exit 1
