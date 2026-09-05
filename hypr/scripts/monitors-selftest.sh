#!/usr/bin/env bash
#
# Exercises config/monitors.lua in a nested Hyprland, without touching the
# real outputs.
#
# The nested compositor's one real output is a window on the desktop, named
# WAYLAND-1. The policy override makes that window the "built-in panel" and
# every headless output an "external", so docking and undocking are
# `hyprctl output create` and `remove`, and removing the last external
# reaches the FALLBACK path for real: the compositor makes its headless
# FALLBACK output, the policy has to notice, and the panel has to come back.
#
# What it checks, in order: the panel is on alone; plugging an external turns
# it off; unplugging turns it back on and FALLBACK goes away; a burst of
# plug/unplug settles to one evaluation; a reload while docked does not flip
# the panel; the keep-internal marker keeps both on; two externals sit left
# to right with the first at 0x0. The nested log is opened with
# debug:disable_logs off so the module's own lines can be read afterwards.
#
# Run it from a Hyprland session. A window appears for about twenty seconds
# and two harmless notifications show inside it: the "started without
# start-hyprland" warning and an overlap notice from the moment a headless
# output is created at 0x0 before the layout is rearranged.
#
# Usage: monitors-selftest.sh [config-dir]     (default: the directory above this)

set -uo pipefail

SRC="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

for tool in Hyprland hyprctl jq; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'selftest: %s is not installed\n' "$tool" >&2; exit 2; }
done
# Without a wayland display to nest in, Hyprland would take the real outputs
# over as a second DRM compositor, which is not a test of anything.
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
# No autostart in the nested compositor, for the same reason verify-config.sh
# empties it: a second copy of every session service is not a test.
printf -- '-- emptied by monitors-selftest.sh\n' > "$WORK/config/execs.lua"
sed -i '1i MONITOR_POLICY_OVERRIDE = { internal = { "^WAYLAND%-", "^WL%-" }, synthetic = { "^FALLBACK$" }, sysfs = false, settle_removed_ms = 300, settle_added_ms = 300, verify_ms = 1500 }' "$WORK/hyprland.lua"
printf 'hl.config({ debug = { disable_logs = false } })\n' >> "$WORK/hyprland.lua"
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
LOG="$RT/hypr/$SIG/hyprland.log"

n()    { HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl "$@"; }
mons() { n monitors all -j | jq -r '.[] | "\(.name) disabled=\(.disabled) \(.width)x\(.height)@\(.refreshRate|floor) pos=\(.x)x\(.y)"' | sort | tr '\n' ';'; echo; }
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

sleep 2
expect "alone: panel on" "WAYLAND-1 disabled=false"

n output create headless HEADLESS-1 >/dev/null
sleep 1.2
expect "docked: panel off" "WAYLAND-1 disabled=true"
expect "docked: external on" "HEADLESS-1 disabled=false"

m=$(mark)
n output remove HEADLESS-1 >/dev/null
sleep 0.15
mons | grep -q FALLBACK && echo "      FALLBACK appeared after the removal, as expected"
sleep 2.5
expect "undocked: panel back on" "WAYLAND-1 disabled=false"
if mons | grep -q FALLBACK; then echo "FAIL  undocked: FALLBACK still present"; FAILED=1; else echo "PASS  undocked: FALLBACK gone"; fi

m=$(mark)
for _ in 1 2 3; do n output create headless HEADLESS-1 >/dev/null; sleep 0.1; n output remove HEADLESS-1 >/dev/null; sleep 0.1; done
sleep 2.5
expect "burst: panel on" "WAYLAND-1 disabled=false"
evals=$(since "$m" | grep -c '\[Lua\] monitors:')
if (( evals <= 2 )); then echo "PASS  burst: $evals evaluation(s) for six events"; else echo "FAIL  burst: $evals evaluations for six events"; FAILED=1; fi

n output create headless HEADLESS-1 >/dev/null
sleep 1.2
expect "docked again: panel off" "WAYLAND-1 disabled=true"
m=$(mark)
n reload >/dev/null
sleep 1.5
expect "reload while docked: panel still off" "WAYLAND-1 disabled=true"
flips=$(since "$m" | grep -c 'Added new monitor with name WAYLAND-1')
if (( flips == 0 )); then echo "PASS  reload while docked: the panel did not come on and go off again"; else echo "FAIL  reload while docked: the panel came on $flips time(s)"; FAILED=1; fi

touch "$WORK/keep-internal"
n eval 'MONITORS.evaluate("selftest", false)' >/dev/null
sleep 1.2
expect "keep-internal: panel on beside the external" "WAYLAND-1 disabled=false"
expect "keep-internal: external still on" "HEADLESS-1 disabled=false"
rm -f "$WORK/keep-internal"
n eval 'MONITORS.evaluate("selftest", false)' >/dev/null
sleep 1.2
expect "marker removed: panel off" "WAYLAND-1 disabled=true"

n output remove HEADLESS-1 >/dev/null
sleep 2
expect "alone again: panel on" "WAYLAND-1 disabled=false"
n output create headless HEADLESS-1 >/dev/null
n output create headless HEADLESS-2 >/dev/null
sleep 1.5
expect "two externals: panel off" "WAYLAND-1 disabled=true"
expect "two externals: first at 0x0" "HEADLESS-1 disabled=false 1920x1080@60 pos=0x0"
n output remove HEADLESS-2 >/dev/null
n output remove HEADLESS-1 >/dev/null
sleep 2.5
expect "all unplugged: panel on" "WAYLAND-1 disabled=false"

errors=$(n configerrors 2>/dev/null | grep -c '[^[:space:]]')
if (( errors == 0 )); then echo "PASS  no config errors"; else echo "FAIL  config errors:"; n configerrors; FAILED=1; fi

echo "--- the module's log lines:"
grep '\[Lua\] monitors:' "$LOG" | sed 's/^.*\[Lua\] /      /'

n dispatch 'hl.dsp.exit()' >/dev/null 2>&1
for _ in $(seq 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
kill -0 "$PID" 2>/dev/null && kill "$PID" 2>/dev/null
PID=""
# The nested compositor's runtime directory is this test's, and nobody else's
# to clean. Only once its lock is gone.
[[ -e "$RT/hypr/$SIG/hyprland.lock" ]] || rm -rf -- "${RT:?}/hypr/${SIG:?}"

if (( FAILED )); then echo "result: FAILURES"; else echo "result: all checks passed"; fi
exit "$FAILED"
