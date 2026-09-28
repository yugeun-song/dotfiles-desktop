#!/usr/bin/env bash
# Tests config/monitors.lua in a nested Hyprland without touching real outputs.
# The nested window (WAYLAND-1) plays the built-in panel and headless outputs
# play externals, so removing the last one exercises the real FALLBACK path.
# The lid is driven through MONITORS.lid_close/lid_open, the calls the lid
# binds make, and its state at load through a stand-in for /proc/acpi. The
# overrides go through scripts/monitor-override.sh against the nested
# instance's own state directory, so the real desktop's overrides are never
# touched. Run from a Hyprland session; a window shows for ~80 s with a few
# harmless notifications (no start-hyprland, transient overlap at 0x0, the
# refused mode). The window must stay visible: Hyprland applies monitor rules
# from its render pre-checks, i.e. only when some output draws a frame, and
# the nested panel draws only while the parent shows it. Parked on a hidden
# workspace, every case that has to re-light an output (the headless ones
# being off) fails, and WAYLAND-1 exhausts its three mode retries with "NO
# PREFERRED MODE". A visible, unfocused workspace is fine:
#   hyprctl dispatch "hl.dsp.exec_cmd('[workspace 1 silent] bash <this file>')"
#
# Usage: monitors-selftest.sh [config-dir]     (default: the directory above this)

set -uo pipefail

SRC="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

for tool in Hyprland hyprctl jq; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'selftest: %s is not installed\n' "$tool" >&2; exit 2; }
done
# Without a display to nest in, Hyprland would grab the real outputs via DRM.
[[ -n "${WAYLAND_DISPLAY:-}" && -S "$RT/${WAYLAND_DISPLAY}" ]] || {
    printf 'selftest: no wayland session to nest in (WAYLAND_DISPLAY is not set); run this from the desktop\n' >&2; exit 2; }
[[ -f "$SRC/hyprland.lua" && -f "$SRC/config/monitors.lua" ]] || {
    printf 'selftest: %s has no hyprland.lua and config/monitors.lua\n' "$SRC" >&2; exit 2; }

WORK=$(mktemp -d -t monitors-selftest.XXXXXX)
PID=""
# shellcheck disable=SC2329
cleanup() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
    fi
    rm -rf -- "$WORK"
}
trap cleanup EXIT

cp -a "$SRC/hyprland.lua" "$WORK/"
cp -a "$SRC/config" "$WORK/"
# No autostart: it would start a second copy of every session service.
printf -- '-- emptied by monitors-selftest.sh\n' > "$WORK/config/execs.lua"
# The real lid must not decide the test's outcome, so the policy reads its
# lid state from here instead.
mkdir -p "$WORK/acpi-lid/LID"
lid() { printf 'state:      %s\n' "$1" > "$WORK/acpi-lid/LID/state"; }
lid open
override=$(printf 'MONITOR_POLICY_OVERRIDE = { internal = { "^WAYLAND%%-", "^WL%%-" }, synthetic = { "^FALLBACK$" }, sysfs = false, auto_scale = false, workspaces = "panel-first", acpi_lid = "%s", settle_removed_ms = 300, settle_added_ms = 300, verify_ms = 1500, panel_off_delay_ms = 200, panel_off_verify_ms = 400 }' "$WORK/acpi-lid")
{ printf '%s\n' "$override"; cat "$WORK/hyprland.lua"; } > "$WORK/hyprland.lua.new"
mv "$WORK/hyprland.lua.new" "$WORK/hyprland.lua"
# The log file is written through a stream nobody flushes, so a line can
# arrive seconds late; stdout is flushed per line, so the checks read that.
printf 'hl.config({ debug = { disable_logs = false, enable_stdout_logs = true, colored_stdout_logs = false } })\n' >> "$WORK/hyprland.lua"
mkdir -p "$WORK/state/hypr"

before=$(hyprctl instances -j 2>/dev/null | jq -r '.[].instance')

XDG_STATE_HOME="$WORK/state" env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland -c "$WORK/hyprland.lua" >"$WORK/hyprland.out" 2>&1 &
PID=$!

SIG=""
for _ in $(seq 100); do
    for s in $(hyprctl instances -j 2>/dev/null | jq -r '.[].instance'); do
        grep -qx "$s" <<<"$before" && continue
        SIG=$s
    done
    [[ -n "$SIG" ]] && HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl version >/dev/null 2>&1 && break
    SIG=""
    sleep 0.2
done
if [[ -z "$SIG" ]]; then
    echo "FAIL  the nested compositor never answered; its output is in $WORK/hyprland.out"
    cat "$WORK/hyprland.out" | tail -20
    trap - EXIT
    [[ -n "$PID" ]] && kill "$PID" 2>/dev/null
    exit 1
fi
LOG="$WORK/hyprland.out"

n()    { HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl "$@"; }
mons() { n monitors all -j | jq -r '.[] | "\(.name) disabled=\(.disabled) \(.width)x\(.height)@\(.refreshRate|floor) pos=\(.x)x\(.y) scale=\(.scale) mirror=\(.mirrorOf)"' | sort | tr '\n' ';'; echo; }
# Numbered workspaces as id@output, special ones left out.
wss()  { n workspaces -j | jq -r '[.[] | select(.id > 0)] | sort_by(.id) | map("\(.id)@\(.monitor)") | join(" ")'; }
focus() { n dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null; }
mark() { wc -l < "$LOG"; }
since() { tail -n +"$(( $1 + 1 ))" "$LOG"; }

FAILED=0
expect() {
    local label="$1" want="$2" got
    got=$(mons)
    if [[ "$got" == *"$want"* ]]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label: wanted [$want] got: $got"
        FAILED=1
    fi
}
# Polls a check up to $1 seconds, for changes Hyprland finishes through its
# 1 s mode retries on the nested panel (it has no mode list).
settle() {
    local seconds="$1"; shift
    local i
    for (( i = 0; i < seconds * 5; i++ )); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.2
    done
    return 1
}
mirrors() { [[ "$(n monitors all -j | jq -r --arg m "$1" '.[] | select(.name == $m) | .mirrorOf')" != "none" ]]; }
not_mirroring() { ! mirrors "$1"; }
expect_re() {
    local label="$1" want="$2" got
    got=$(mons)
    if [[ "$got" =~ $want ]]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label: wanted /$want/ got: $got"
        FAILED=1
    fi
}
expect_ws() {
    local label="$1" want="$2" got
    got=$(wss)
    if [[ " $got " == *" $want "* ]]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label: wanted [$want] got: $got"
        FAILED=1
    fi
}
on_panel() { n workspaces -j | jq -r '[.[] | select(.id > 0 and .monitor == "WAYLAND-1") | .id] | sort | map(tostring) | join(",")'; }
# Beside a lit external the panel holds workspace 1 and nothing else.
expect_panel_holds_one() {
    local label="$1" got
    got=$(on_panel)
    if [[ "$got" == "1" ]]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label: the panel holds [$got]"
        FAILED=1
    fi
}
# Switched off, the panel keeps no workspace out of sight.
expect_panel_holds_none() {
    local label="$1" got
    got=$(on_panel)
    if [[ -z "$got" ]]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label: the panel still holds [$got]"
        FAILED=1
    fi
}
expect_no_flip() {
    local label="$1" m="$2" flips
    flips=$(since "$m" | grep -c 'Added new monitor with name WAYLAND-1')
    if (( flips == 0 )); then echo "PASS  $label"; else echo "FAIL  $label: the panel came on $flips time(s)"; FAILED=1; fi
}

sleep 2
expect "alone: panel on" "WAYLAND-1 disabled=false"

# The workspace in use when an external arrives moves to it; the panel keeps 1.
focus 3
sleep 0.3
n output create headless HEADLESS-1 >/dev/null
sleep 1.2
expect "docked: panel stays on" "WAYLAND-1 disabled=false"
expect "docked: external on, at 0x0" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0"
expect_ws "docked: workspace 1 on the panel" "1@WAYLAND-1"
expect_ws "docked: the workspace in use moved to the external" "3@HEADLESS-1"
expect_panel_holds_one "docked: the panel holds workspace 1 only"

# Gaps and border follow the output's share of the reference screen: the
# 1920x1080 headless is 0.75 of 2560x1440, so gaps 4/8 and border 3 become
# 3/6 and 2 on it.
# gapsIn and gapsOut print as four edges.
fitrule=$(n workspacerules -j | jq -c '.[] | select(.workspaceString == "m[HEADLESS-1]") | [.gapsIn[0], .gapsOut[0], .borderSize]' 2>/dev/null | tail -1)
if [[ "$fitrule" == "[3,6,2]" ]]; then echo "PASS  fit: gaps and border scaled for the headless output"; else echo "FAIL  fit: rule for m[HEADLESS-1] is [$fitrule], wanted [3,6,2]"; FAILED=1; fi

# From the panel, a workspace that does not exist yet opens on the external.
focus 1
focus 5
sleep 0.3
expect_ws "docked: a new workspace opens on the external" "5@HEADLESS-1"

# Moved by hand, workspaces go back at the next evaluation. Each is focused
# while it moves: an empty workspace lives only while an output shows it.
n dispatch 'hl.dsp.workspace.move({ workspace = 5, monitor = "WAYLAND-1" })' >/dev/null
n eval 'MONITORS.evaluate("selftest", false)' >/dev/null
sleep 0.5
expect_ws "moved by hand: workspace 5 back on the external" "5@HEADLESS-1"
expect_panel_holds_one "moved by hand: the panel holds workspace 1 only"
focus 1
n dispatch 'hl.dsp.workspace.move({ workspace = 1, monitor = "HEADLESS-1" })' >/dev/null
n eval 'MONITORS.evaluate("selftest", false)' >/dev/null
sleep 0.5
expect_ws "moved by hand: workspace 1 back on the panel" "1@WAYLAND-1"
expect_panel_holds_one "moved by hand: the panel holds workspace 1 only again"
focus 1

# Lid shut beside an external: the panel goes off, in its own emission after
# the lighting one (both in one commit left the real machine stuck on
# FALLBACK with no output), and keeps no workspace. Only the module's log
# shows the order; the end state is the same either way.
m=$(mark)
n eval 'MONITORS.lid_close()' >/dev/null
sleep 1.2
expect "lid shut: panel off" "WAYLAND-1 disabled=true"
expect "lid shut: external still on" "HEADLESS-1 disabled=false"
expect_panel_holds_none "lid shut: no workspace left on the panel"
lit=$(since "$m" | grep -c 'monitors: lid shut -> ')
off=$(since "$m" | grep -c 'monitors: lid shut (off) -> WAYLAND-1:off')
if (( lit == 1 && off == 1 )); then
    echo "PASS  lid shut: the external was lit and the panel darkened in separate emissions"
else
    echo "FAIL  lid shut: wanted one lit emission and one panel-off emission, got lit=$lit off=$off"
    since "$m" | grep 'monitors:' | sed 's/^.*\[Lua\] /      /'
    FAILED=1
fi
if since "$m" | grep -q 'monitors: lid shut -> .*WAYLAND-1:off'; then
    echo "FAIL  lid shut: the panel was darkened in the same emission that lit the external"
    FAILED=1
else
    echo "PASS  lid shut: the lighting emission carried no disabled rule"
fi

n eval 'MONITORS.lid_open()' >/dev/null
sleep 1.2
expect "lid open: panel back on" "WAYLAND-1 disabled=false"
expect_ws "lid open: workspace 1 back on the panel" "1@WAYLAND-1"
expect_panel_holds_one "lid open: the panel holds workspace 1 only"

m=$(mark)
n reload >/dev/null
sleep 1.5
expect "reload while docked: panel still on" "WAYLAND-1 disabled=false"
removed=$(since "$m" | grep -c 'Removed monitor WAYLAND-1')
if (( removed == 0 )); then echo "PASS  reload while docked: the panel did not go off and on again"; else echo "FAIL  reload while docked: the panel went off $removed time(s)"; FAILED=1; fi
expect_ws "reload while docked: workspace 1 still on the panel" "1@WAYLAND-1"

# A reload has no lid event to go by; the state at load comes from ACPI.
n eval 'MONITORS.lid_close()' >/dev/null
sleep 1.2
lid closed
m=$(mark)
n reload >/dev/null
sleep 1.5
expect "reload with the lid shut: panel still off" "WAYLAND-1 disabled=true"
expect_no_flip "reload with the lid shut: the panel did not come on and go off again" "$m"

# Unplugged with the lid shut, the external was the last output.
n output remove HEADLESS-1 >/dev/null
sleep 0.15
mons | grep -q FALLBACK && echo "      FALLBACK appeared after the removal, as expected"
sleep 2.5
expect "undocked with the lid shut: panel back on" "WAYLAND-1 disabled=false"
if mons | grep -q FALLBACK; then echo "FAIL  undocked: FALLBACK still present"; FAILED=1; else echo "PASS  undocked: FALLBACK gone"; fi
lid open
n eval 'MONITORS.lid_open()' >/dev/null
sleep 0.5

m=$(mark)
for _ in 1 2 3; do n output create headless HEADLESS-1 >/dev/null; sleep 0.1; n output remove HEADLESS-1 >/dev/null; sleep 0.1; done
sleep 2.5
expect "burst: panel on" "WAYLAND-1 disabled=false"
expect_ws "burst: workspace 1 on the panel" "1@WAYLAND-1"
evals=$(since "$m" | grep -c '\[Lua\] monitors:')
if (( evals <= 2 )); then echo "PASS  burst: $evals evaluation(s) for six events"; else echo "FAIL  burst: $evals evaluations for six events"; FAILED=1; fi

# The external last showed workspace 1 (the lid was shut when it left), and
# Hyprland gives a returning output the workspace it showed; the rules must
# still put 1 back on the panel.
n output create headless HEADLESS-1 >/dev/null
sleep 1.2
expect "docked again: panel on" "WAYLAND-1 disabled=false"
expect_ws "docked again: workspace 1 on the panel" "1@WAYLAND-1"
expect_panel_holds_one "docked again: the panel holds workspace 1 only"

# keep_internal = false brings back the panel going off beside any external;
# the keep-internal marker overrides it.
printf 'return { keep_internal = false }\n' > "$WORK/monitor_settings.lua"
n reload >/dev/null
sleep 1.5
expect "keep_internal = false: panel off beside the external" "WAYLAND-1 disabled=true"
expect_panel_holds_none "keep_internal = false: no workspace left on the panel"
touch "$WORK/keep-internal"
n eval 'MONITORS.evaluate("selftest", false)' >/dev/null
sleep 1.2
expect "keep-internal marker: panel on beside the external" "WAYLAND-1 disabled=false"
expect_ws "keep-internal marker: workspace 1 back on the panel" "1@WAYLAND-1"
rm -f "$WORK/keep-internal"
n eval 'MONITORS.evaluate("selftest", false)' >/dev/null
sleep 1.2
expect "marker removed: panel off" "WAYLAND-1 disabled=true"
rm -f "$WORK/monitor_settings.lua"
n reload >/dev/null
sleep 1.5
expect "settings removed: panel on beside the external" "WAYLAND-1 disabled=false"
expect_ws "settings removed: workspace 1 back on the panel" "1@WAYLAND-1"

# ---------------------------------------------------------------------------
# Overrides, through the script, against the nested instance's state dir.
# ---------------------------------------------------------------------------
OV="$SRC/scripts/monitor-override.sh"
ov() { XDG_STATE_HOME="$WORK/state" HYPRLAND_INSTANCE_SIGNATURE=$SIG "$OV" "$@"; }
OVFILE="$WORK/state/hypr/monitor-overrides"
if [[ ! -x "$OV" ]]; then
    echo "FAIL  $OV is missing or not executable; skipping the override cases"
    FAILED=1
else
# A bad value is refused before anything is written.
if printf 'name:HEADLESS-1\tenabled\tmaybe\n' | ov set 2>/dev/null; then
    echo "FAIL  set: a bad value was accepted"; FAILED=1
elif [[ -e "$OVFILE" ]]; then
    echo "FAIL  set: a refused set still wrote $OVFILE"; FAILED=1
else
    echo "PASS  set: a bad value is refused and nothing is written"
fi

# Laptop only: the external goes off in its own emission, the panel keeps 0x0.
m=$(mark)
printf 'name:HEADLESS-1\tenabled\tfalse\n' | ov set || { echo "FAIL  set: laptop only exited $?"; FAILED=1; }
sleep 1.5
expect "laptop only: external off" "HEADLESS-1 disabled=true"
expect_re "laptop only: panel on at 0x0" 'WAYLAND-1 disabled=false [0-9x@]+ pos=0x0'
expect_ws "laptop only: workspace 1 on the panel" "1@WAYLAND-1"
if since "$m" | grep 'monitors: override -> ' | grep -q ':off'; then
    echo "FAIL  laptop only: the lighting emission carried a disabled rule"; FAILED=1
else
    echo "PASS  laptop only: the lighting emission carried no disabled rule"
fi
if since "$m" | grep -q 'monitors: override (off) -> HEADLESS-1:off'; then
    echo "PASS  laptop only: the external went off in the off emission"
else
    echo "FAIL  laptop only: no off emission for HEADLESS-1"; FAILED=1
fi

# Lid shut suspends the external off: it lights, then the panel goes off.
n eval 'MONITORS.lid_close()' >/dev/null
sleep 1.5
expect "laptop only, lid shut: external back on" "HEADLESS-1 disabled=false"
expect "laptop only, lid shut: panel off" "WAYLAND-1 disabled=true"
expect_panel_holds_none "laptop only, lid shut: no workspace left on the panel"
n eval 'MONITORS.lid_open()' >/dev/null
sleep 1.5
expect "laptop only, lid open: panel back on" "WAYLAND-1 disabled=false"
expect "laptop only, lid open: external off again" "HEADLESS-1 disabled=true"
expect_ws "laptop only, lid open: workspace 1 on the panel" "1@WAYLAND-1"

# External only: the panel off although the lid is open, stage two.
m=$(mark)
printf 'name:WAYLAND-1\tenabled\tfalse\n' | ov set || { echo "FAIL  set: external only exited $?"; FAILED=1; }
sleep 1.5
expect "external only: external on at 0x0" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0"
expect "external only: panel off" "WAYLAND-1 disabled=true"
expect_panel_holds_none "external only: no workspace left on the panel"
if since "$m" | grep 'monitors: override -> ' | grep -q ':off'; then
    echo "FAIL  external only: the lighting emission carried a disabled rule"; FAILED=1
else
    echo "PASS  external only: the lighting emission carried no disabled rule"
fi
# The panel goes off only once the external is lit, so the off emission
# belongs to the evaluation the external's arrival schedules.
if since "$m" | grep -q 'monitors: .* (off) -> WAYLAND-1:off'; then
    echo "PASS  external only: the panel went off in an off emission"
else
    echo "FAIL  external only: no off emission for WAYLAND-1"; FAILED=1
fi

# Both off is refused as a state: the panel off counts only beside a lit
# external, so the panel comes back and the external goes.
m=$(mark)
printf 'name:WAYLAND-1\tenabled\tfalse\nname:HEADLESS-1\tenabled\tfalse\n' | ov set || { echo "FAIL  set: both off exited $?"; FAILED=1; }
sleep 2
expect "both off: panel on" "WAYLAND-1 disabled=false"
expect "both off: external off" "HEADLESS-1 disabled=true"
if since "$m" | grep -q 'monitors: .*panel stays on'; then
    echo "PASS  both off: warned that the panel stays on"
else
    echo "FAIL  both off: no warning that the panel stays on"; FAILED=1
fi

ov clear || { echo "FAIL  clear exited $?"; FAILED=1; }
sleep 1.5
[[ -e "$OVFILE" ]] && { echo "FAIL  clear: $OVFILE still exists"; FAILED=1; } || echo "PASS  clear: the file is gone"
expect "cleared: panel on" "WAYLAND-1 disabled=false"
expect "cleared: external on at 0x0" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0"
expect_ws "cleared: workspace 1 on the panel" "1@WAYLAND-1"

# Scale: the external at 2 is 960 logical pixels wide, so the panel lands at 960.
printf 'name:HEADLESS-1\tscale\t2\n' | ov set || { echo "FAIL  set: scale exited $?"; FAILED=1; }
sleep 1.2
expect "scale 2: external at scale 2" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0 scale=2"
expect_re "scale 2: panel placed after 960 logical pixels" 'WAYLAND-1 disabled=false [0-9x@]+ pos=960x0'

# A mode the output does not offer is refused with a warning; the output
# stays on at highrr. A listed one is passed through.
m=$(mark)
printf 'name:HEADLESS-1\tmode\t1280x720@60.00\n' | ov set || { echo "FAIL  set: bad mode exited $?"; FAILED=1; }
sleep 1.2
expect "unlisted mode: external still on at its own mode" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0 scale=1"
if since "$m" | grep -q 'monitors: HEADLESS-1 does not offer 1280x720@60.00'; then
    echo "PASS  unlisted mode: warned and fell back"
else
    echo "FAIL  unlisted mode: no warning"; FAILED=1
fi
m=$(mark)
printf 'name:HEADLESS-1\tmode\t1920x1080@60.00\n' | ov set || { echo "FAIL  set: listed mode exited $?"; FAILED=1; }
sleep 1.2
expect "listed mode: external on" "HEADLESS-1 disabled=false 1920x1080@60"
if since "$m" | grep -q 'HEADLESS-1:1920x1080@60.00/0x0/x1'; then
    echo "PASS  listed mode: the rule carried the mode"
else
    echo "FAIL  listed mode: the rule did not carry the mode"; FAILED=1
fi

# Side: the panel on the left takes 0x0 and the external follows it.
printf 'name:WAYLAND-1\tside\tleft\n' | ov set || { echo "FAIL  set: side exited $?"; FAILED=1; }
sleep 1.2
expect_re "side left: panel at 0x0" 'WAYLAND-1 disabled=false [0-9x@]+ pos=0x0'
expect_re "side left: external to its right" 'HEADLESS-1 disabled=false 1920x1080@60 pos=[1-9][0-9]*x0'
expect_ws "side left: workspace 1 on the panel" "1@WAYLAND-1"

# Mirror: the panel shows the external and holds no workspace.
m=$(mark)
printf 'name:WAYLAND-1\tmirror\ttrue\n' | ov set || { echo "FAIL  set: mirror exited $?"; FAILED=1; }
settle 6 mirrors WAYLAND-1 || echo "      (the mirror did not land within 6 s)"
sleep 0.5
hid=$(n monitors all -j | jq -r '.[] | select(.name == "HEADLESS-1") | .id')
mirror=$(n monitors all -j | jq -r '.[] | select(.name == "WAYLAND-1") | .mirrorOf')
if [[ -n "$hid" && ( "$mirror" == "$hid" || "$mirror" == "HEADLESS-1" ) ]]; then
    echo "PASS  mirror: the panel mirrors HEADLESS-1"
else
    echo "FAIL  mirror: mirrorOf is [$mirror], HEADLESS-1 is id [$hid]"; FAILED=1
fi
expect_panel_holds_none "mirror: no workspace on the panel"
if since "$m" | grep -q 'WAYLAND-1:highrr/[^ ]*/x1/mirror=HEADLESS-1'; then
    echo "PASS  mirror: the rule named the external"
else
    echo "FAIL  mirror: the rule did not name the external"; FAILED=1
fi

# Not reloaded while mirrored: the nested panel has no mode list, and after
# a reload Hyprland cannot pick a mode for it when the mirror ends ("NO
# PREFERRED MODE ... retrying"), so it stays a mirror until the parent
# resizes the window. A real panel offers modes and is not affected.

# Revert swaps the previous set (side left) back in: the mirror ends, the
# panel is its own screen again at 0x0 and workspace 1 comes home.
ov revert || { echo "FAIL  revert exited $?"; FAILED=1; }
settle 6 not_mirroring WAYLAND-1 || echo "      (the mirror did not end within 6 s)"
sleep 1.5
if [[ "$(ov show)" == "$(printf 'name:WAYLAND-1\tside\tleft')" ]]; then
    echo "PASS  revert: the previous overrides are back"
else
    echo "FAIL  revert: the file holds [$(ov show | tr '\t' ' ' | tr '\n' ';')]"; FAILED=1
fi
expect_re "revert: panel its own screen at 0x0" 'WAYLAND-1 disabled=false [0-9x@]+ pos=0x0 scale=1 mirror=none'
expect_ws "revert: workspace 1 back on the panel" "1@WAYLAND-1"
expect_panel_holds_one "revert: the panel holds workspace 1 only"

ov clear || { echo "FAIL  clear (2) exited $?"; FAILED=1; }
sleep 1.5
expect "cleared again: external back at 0x0" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0"
expect_ws "cleared again: workspace 1 on the panel" "1@WAYLAND-1"
fi

# Resume re-reads the lid: shut, the panel stays off beside the external;
# open, it comes back.
lid closed
n eval 'MONITORS.resume()' >/dev/null
sleep 1.5
expect "resume with the lid shut: panel off" "WAYLAND-1 disabled=true"
expect "resume with the lid shut: external on" "HEADLESS-1 disabled=false"
lid open
n eval 'MONITORS.resume()' >/dev/null
sleep 1.5
expect "resume with the lid open: panel on" "WAYLAND-1 disabled=false"
expect_ws "resume with the lid open: workspace 1 on the panel" "1@WAYLAND-1"

n output remove HEADLESS-1 >/dev/null
sleep 2
expect "alone again: panel on" "WAYLAND-1 disabled=false"
n output create headless HEADLESS-1 >/dev/null
n output create headless HEADLESS-2 >/dev/null
sleep 1.5
expect "two externals: panel on" "WAYLAND-1 disabled=false"
expect "two externals: first at 0x0" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0"
focus 1
focus 6
sleep 0.3
expect_ws "two externals: a new workspace opens on the first" "6@HEADLESS-1"

# Workspace schemes: the override file's "*" line replaces the preset's.
# blocks gives the second external 11-20; dynamic binds nothing, so a new
# workspace opens where it is asked for; clear puts panel-first back.
if [[ -x "$OV" ]]; then
printf '*\tworkspaces\tblocks\n' | ov set || { echo "FAIL  set: blocks exited $?"; FAILED=1; }
sleep 1.2
focus 1; focus 15; sleep 0.3
expect_ws "blocks: 15 opens on the second external" "15@HEADLESS-2"
focus 1; focus 25; sleep 0.3
expect_ws "blocks: 25 stays with the main external" "25@HEADLESS-1"
expect_panel_holds_one "blocks: the panel holds workspace 1 only"
printf '*\tworkspaces\tdynamic\n' | ov set || { echo "FAIL  set: dynamic exited $?"; FAILED=1; }
sleep 1.2
focus 1; focus 45; sleep 0.3
expect_ws "dynamic: a new workspace opens where it is asked for" "45@WAYLAND-1"
status=$(n repl 'return MONITORS.status()' 2>/dev/null)
if [[ "$status" == *"workspaces=dynamic source=override"* ]]; then echo "PASS  status: reports the override scheme"; else echo "FAIL  status: [$status]"; FAILED=1; fi
ov clear || { echo "FAIL  clear exited $?"; FAILED=1; }
sleep 1.2
focus 1; focus 46; sleep 0.3
expect_ws "cleared: panel-first again, 46 opens on the main external" "46@HEADLESS-1"
focus 1
fi

# The first external leaves: the one now first takes the workspaces from
# then on, and none may land on the panel.
n output remove HEADLESS-1 >/dev/null
sleep 1.5
focus 1
focus 7
sleep 0.3
expect_ws "first external gone: a new workspace opens on the next one" "7@HEADLESS-2"
expect_panel_holds_one "first external gone: the panel holds workspace 1 only"
n output remove HEADLESS-2 >/dev/null
sleep 2.5
expect "all unplugged: panel on" "WAYLAND-1 disabled=false"

# auto_scale is off for the nested outputs above (WAYLAND-1's size is whatever
# the parent gave the window), so the chooser is exercised as a function:
# nearest integral logical width to the target for the kind.
autoscale() { n repl "return string.format('%g', MONITORS.auto_scale($1, $2, '$3', { internal = 1920, external = 2560 }))" 2>/dev/null | tr -d '[:space:]"'; }
expect_scale() {
    local label="$1" want="$2" got
    got=$(autoscale "$3" "$4" "$5")
    if [[ "$got" == "$want" ]]; then echo "PASS  $label"; else echo "FAIL  $label: wanted $want got [$got]"; FAILED=1; fi
}
expect_scale "auto scale: 2880x1800 panel -> 1.5" 1.5 2880 1800 internal
expect_scale "auto scale: 3840x2400 panel -> 2" 2 3840 2400 internal
expect_scale "auto scale: 2560x1600 panel -> 1.25 (1.5 is not integral)" 1.25 2560 1600 internal
expect_scale "auto scale: 1920x1080 panel -> 1" 1 1920 1080 internal
expect_scale "auto scale: 2560x1440 external -> 1" 1 2560 1440 external
expect_scale "auto scale: 3840x2160 external -> 1.5" 1.5 3840 2160 external
expect_scale "auto scale: 1920x1080 external -> 1" 1 1920 1080 external

errors=$(n configerrors 2>/dev/null | grep -c '[^[:space:]]')
if (( errors == 0 )); then echo "PASS  no config errors"; else echo "FAIL  config errors:"; n configerrors; FAILED=1; fi
# A refused dispatch is only logged, and names hl.dispatch ([C]) rather than
# the calling line, so any Lua warning counts; this config is all that runs.
warnings=$(grep -E 'Lua (warning|error) \(' "$LOG")
if [[ -z "$warnings" ]]; then echo "PASS  no Lua warnings"; else echo "FAIL  Lua warnings:"; printf '      %s\n' "$warnings"; FAILED=1; fi

echo "--- the module's log lines:"
grep '\[Lua\] monitors:' "$LOG" | sed 's/^.*\[Lua\] /      /'
if (( FAILED )); then
    echo "--- the compositor's errors and warnings:"
    grep -E '(ERR|WARN)[^]]*\]:' "$LOG" | grep -vE 'start-hyprland|overlap' | tail -25 | sed 's/^/      /' | cut -c1-180
fi

n dispatch 'hl.dsp.exit()' >/dev/null 2>&1
for _ in $(seq 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
kill -0 "$PID" 2>/dev/null && kill "$PID" 2>/dev/null
PID=""
# Remove the nested instance's runtime dir once its lock is gone.
[[ -e "$RT/hypr/$SIG/hyprland.lock" ]] || rm -rf -- "${RT:?}/hypr/${SIG:?}"

if (( FAILED )); then echo "result: FAILURES"; else echo "result: all checks passed"; fi
exit "$FAILED"
