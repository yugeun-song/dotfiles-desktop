#!/usr/bin/env bash
# End-to-end checks of the bar and the compositor policy, in a nested headless
# Hyprland:  tests/e2e/run.sh   (or tests/run.sh --e2e). About three minutes.
#
# It needs a running Hyprland session to nest in, and leaves that session
# alone. The nested compositor starts on a hidden special workspace with its
# own window output disabled before it maps, and two headless outputs stand
# in for the laptop panel (HEADLESS-1, 2880x1800 at 1.5) and an external
# (HEADLESS-2, 2560x1440). A copy of the bar runs on it with its own D-Bus,
# its own state and config directories, and every action that could reach
# the machine replaced by a log line (defang.py). Input comes from vinput,
# built here and only ever pointed at the nested socket. Everything started
# is recorded and stopped at the end, and only that: the quickshell runtime
# entries are removed only where they name this run's directory.

# Predicates and cleanup are called through check, wait_for and the trap.
# shellcheck disable=SC2329

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

missing=()
for tool in Hyprland hyprctl jq qs grim dbus-daemon notify-send gcc wayland-scanner pkg-config python3 slurp magick; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if (( ${#missing[@]} )); then
    echo "SKIP  e2e: not installed: ${missing[*]}"
    exit 0
fi
if [[ -z "${WAYLAND_DISPLAY:-}" || -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    echo "SKIP  e2e: no Hyprland session to nest in"
    exit 0
fi
PIL=1
python3 -c 'import PIL' 2>/dev/null || PIL=0

WORK=$(mktemp -d -p /tmp e2e.XXXXXX)
NESTED_PID="" DBUS_PID="" QS_PID="" SIG="" WL=""
failed=0
passed=0

pass() { passed=$((passed + 1)); echo "PASS  e2e: $*"; }
fail() { failed=$((failed + 1)); echo "FAIL  e2e: $*"; }
skip() { echo "SKIP  e2e: $*"; }
# A check is a command: its status is the verdict.
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

# ---------------------------------------------------------------- teardown --
# Every process under one, grandchildren included.
descendants() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null); do
        echo "$child"
        descendants "$child"
    done
}

# qs runs the shell as its child, and the shell runs the helpers: killing qs
# alone left them, the key reader among them, which went on reading the
# FIFO and took the next test's keys. The whole tree is listed first.
stop_bar() {
    [[ -n "$QS_PID" ]] || return 0
    local tree=()
    mapfile -t tree < <(descendants "$QS_PID")
    kill "$QS_PID" "${tree[@]}" 2>/dev/null
    for _ in $(seq 30); do kill -0 "$QS_PID" 2>/dev/null || break; sleep 0.1; done
    QS_PID=""
}

cleanup() {
    stop_bar
    [[ -n "$NESTED_PID" ]] && kill "$NESTED_PID" 2>/dev/null
    [[ -n "$DBUS_PID" ]] && kill "$DBUS_PID" 2>/dev/null
    sleep 0.5
    [[ -n "$SIG" && -d "$RT/hypr/$SIG" ]] && rm -rf -- "${RT:?}/hypr/${SIG:?}"
    local d id shells=()
    for d in "$RT"/quickshell/by-id/*/; do
        if [[ ! -f "$d/log.log" ]] || ! grep -qF -- "$WORK/" "$d/log.log" 2>/dev/null; then
            continue
        fi
        id=$(grep -o 'Shell ID: "[0-9a-f]*"' "$d/log.log" | head -1 | grep -o '[0-9a-f]\{32\}')
        [[ -n "$id" ]] && shells+=("$id")
        rm -rf -- "${d:?}"
    done
    for d in "$RT"/quickshell/by-pid/*; do
        [[ -L "$d" && ! -e "$d" ]] && rm -f -- "$d"
    done
    for id in "${shells[@]}"; do
        rm -rf -- "${RT:?}/quickshell/by-shell/${id:?}" "${RT:?}/quickshell/by-path/${id:?}"
    done
    # E2E_KEEP=1 keeps the screenshots and logs for a look at a failure.
    if [[ "${E2E_KEEP:-}" == 1 ]]; then
        echo "e2e: kept $WORK"
    else
        rm -rf -- "$WORK"
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------------- setup --
n() { HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@"; }
has_layer() { n layers -j | jq -e --arg ns "$1" --arg m "${2:-}" \
    '[to_entries[] | select($m == "" or .key == $m) | .value.levels[][] | .namespace] | index($ns) != null' >/dev/null; }
dpms() { n monitors -j | jq -r --arg m "$1" '.[] | select(.name == $m) | .dpmsStatus'; }
benv() {
    env WAYLAND_DISPLAY="$WL" HYPRLAND_INSTANCE_SIGNATURE="$SIG" DBUS_SESSION_BUS_ADDRESS="$BUS" \
        XDG_STATE_HOME="$WORK/state" XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" \
        PATH="$WORK/bin:$PATH" "$@"
}
ipc() { benv qs -p "$WORK/bar" ipc call "$@" 2>/dev/null; }
# Only ever the nested socket: refused if it is the session's own.
input() {
    [[ -n "$WL" && "$WL" != "$WAYLAND_DISPLAY" && -S "$RT/$WL" ]] || { echo "e2e: refusing input to $WL" >&2; return 1; }
    WAYLAND_DISPLAY="$WL" "$WORK/vinput" "$@"
}
shot() { benv grim "$@"; }
wait_for() {
    local seconds="$1" i
    shift
    for (( i = 0; i < seconds * 10; i++ )); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

# Predicates for check and wait_for.
lacks_layer() { ! has_layer "$@"; }
key_state() { ipc e2e keys | jq -r "$1"; }
key_state_is() { [[ "$(key_state "$1")" == "$2" ]]; }
bar_up() { ipc e2e keys | grep -q enabled; }
file_is() { [[ "$(cat "$1" 2>/dev/null)" == "$2" ]]; }
both_dpms() { [[ "$(dpms HEADLESS-1)" == "$1" && "$(dpms HEADLESS-2)" == "$1" ]]; }
alarm_is() { [[ "$(ipc e2e alarm)" == "$1" ]]; }
countdown_over() { (( $(ipc e2e displaysState | jq .countdown) > $1 )); }
outputs_are() { [[ "$(n monitors -j | jq -r '[.[] | "\(.name)=\(.width)"] | sort | join(" ")')" == "$1" ]]; }
logged() { grep -q -- "$2" "$1" 2>/dev/null; }
no_qml_warnings() { ! grep -E "WARN scene|ERROR" "$WORK/qs.out" | grep -v -E "portal|Could not register" | grep -q .; }
session_dialog_open() { has_layer quickshell:powermenu && [[ "$(ipc e2e session)" == true ]]; }
overlay_on() { has_layer quickshell:keys && key_state_is .enabled true; }
no_writes() { ! grep -q -E '^(lock|suspend|session-power|ddc-set|backlight-set)' "$WORK/apps.log" 2>/dev/null; }

start_bar() {
    benv qs -n --log-rules 'quickshell.hyprland.ipc.events.debug=false;quickshell.dbus.properties.debug=false' \
        -p "$WORK/bar" >>"$WORK/qs.out" 2>&1 &
    QS_PID=$!
    wait_for 15 bar_up || { echo "e2e: the bar did not come up"; tail -20 "$WORK/qs.out"; exit 1; }
}

reload_bar() {
    ipc shell reload >/dev/null
    sleep 1
    wait_for 15 bar_up
    sleep 1
}

mkdir -p "$WORK/bin" "$WORK/state/hypr" "$WORK/state/quickshell/bar" "$WORK/cache" "$WORK/config" \
    "$WORK/home/Pictures" "$WORK/capture" "$WORK/acpi/LID"
chmod 700 "$WORK/capture"

read -ra wl_flags <<<"$(pkg-config --cflags --libs wayland-client xkbcommon)"
for p in wlr-virtual-pointer-unstable-v1:pointer virtual-keyboard-unstable-v1:keyboard; do
    wayland-scanner client-header "$REPO/tests/e2e/vinput/${p%%:*}.xml" "$WORK/${p%%:*}-client.h"
    wayland-scanner private-code "$REPO/tests/e2e/vinput/${p%%:*}.xml" "$WORK/${p##*:}.c"
done
gcc -O1 -o "$WORK/vinput" -I "$WORK" "$REPO/tests/e2e/vinput/vinput.c" "$WORK/pointer.c" "$WORK/keyboard.c" \
    "${wl_flags[@]}" || { echo "FAIL  e2e: vinput does not build"; exit 1; }

# Stubs for what reads or writes hardware; a call is logged, nothing runs.
for tool in ddcutil brightnessctl canberra-gtk-play; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/hardware.log"\n' "$tool" "$WORK" > "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done

cp -a "$REPO/hypr" "$WORK/config/hypr"
cp -a "$REPO/quickshell/bar" "$WORK/bar"
printf -- '-- emptied by tests/e2e\n' > "$WORK/config/hypr/config/execs.lua"
printf 'state:      open\n' > "$WORK/acpi/LID/state"
# Headless outputs list a single 1920x1080 mode; the policy is asked for the
# sizes of the real desk through the override file, and must not refuse them.
python3 - "$WORK/config/hypr/config/monitors.lua" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'if type(modes) ~= "table" then\n        return true\n    end'
if old not in s:
    sys.exit("e2e: offers_mode changed; update tests/e2e/run.sh")
open(p, "w").write(s.replace(old, 'if true then\n        return true\n    end', 1))
EOF
printf 'name:HEADLESS-1\tmode\t2880x1800@60\nname:HEADLESS-1\tscale\t1.5\nname:HEADLESS-2\tmode\t2560x1440@60\nname:HEADLESS-2\tscale\t1\n' \
    > "$WORK/state/hypr/monitor-overrides"
{
    printf 'MONITOR_POLICY_OVERRIDE = { internal = { "^HEADLESS%%-1$" }, synthetic = { "^FALLBACK$", "^WAYLAND%%-" }, sysfs = false, auto_scale = false, acpi_lid = "%s", settle_removed_ms = 300, settle_added_ms = 300, verify_ms = 1500, panel_off_delay_ms = 200, panel_off_verify_ms = 400 }\n' "$WORK/acpi"
    cat "$REPO/hypr/hyprland.lua"
    printf 'hl.monitor({ output = "WAYLAND-1", disabled = true })\nhl.config({ xwayland = { enabled = false } })\n'
} > "$WORK/config/hypr/hyprland.lua"
python3 "$REPO/tests/e2e/defang.py" "$WORK" || exit 1
mkfifo "$WORK/keyfifo"
printf 'XDG_PICTURES_DIR="%s/home/Pictures"\n' "$WORK" > "$WORK/config/user-dirs.dirs"

before=$(hyprctl instances -j | jq -r '.[].instance')
cat > "$WORK/launch.sh" <<EOF
#!/usr/bin/env bash
echo \$\$ > "$WORK/nested.pid"
exec env -u HYPRLAND_INSTANCE_SIGNATURE XDG_STATE_HOME="$WORK/state" XDG_CONFIG_HOME="$WORK/config" \
    XDG_CACHE_HOME="$WORK/cache" Hyprland -c "$WORK/config/hypr/hyprland.lua" > "$WORK/hyprland.out" 2>&1
EOF
hyprctl dispatch "hl.dsp.exec_cmd('[workspace special:e2e silent] bash $WORK/launch.sh')" >/dev/null
for _ in $(seq 100); do
    for s in $(hyprctl instances -j | jq -r '.[].instance'); do
        grep -qx "$s" <<<"$before" || SIG=$s
    done
    [[ -n "$SIG" ]] && HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl version >/dev/null 2>&1 && break
    SIG=""
    sleep 0.2
done
NESTED_PID=$(cat "$WORK/nested.pid" 2>/dev/null)
[[ -n "$SIG" ]] || { echo "FAIL  e2e: the nested compositor did not start"; tail -20 "$WORK/hyprland.out"; exit 1; }
WL=$(hyprctl instances -j | jq -r --arg s "$SIG" '.[] | select(.instance == $s) | .wl_socket')
n output create headless HEADLESS-1 >/dev/null
n output create headless HEADLESS-2 >/dev/null
# The nested compositor's own notice (no start-hyprland) would sit over
# the screenshots.
n dismissnotify >/dev/null 2>&1
wait_for 10 outputs_are "HEADLESS-1=2880 HEADLESS-2=2560" \
    || { echo "FAIL  e2e: the headless outputs did not take their modes"; exit 1; }

cat > "$WORK/dbus.conf" <<'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
bus_out=$(dbus-daemon --config-file="$WORK/dbus.conf" --fork --print-address=1 --print-pid=1)
BUS=$(sed -n 1p <<<"$bus_out")
DBUS_PID=$(sed -n 2p <<<"$bus_out")

start_bar
echo "e2e: nested session $SIG on $WL, bar pid $QS_PID"

# --------------------------------------------------------------- scenarios --
# The external is at 0,0 (2560x1440), the panel to its right (1920x1200
# logical); vinput's default extent is that layout.

# 1. The bar comes up clean.
check "the bar loads without QML warnings" no_qml_warnings

# 2. The power button at the bar's right end opens the session dialog.
# The glyph at the bar's right end, found in a capture of it once the bar
# has drawn it (the first frames come a moment after the bar answers IPC).
power_x() {
    shot -g "2360,0 200x34" "$WORK/bar-end.png" 2>/dev/null || return 1
    x=$(python3 - "$WORK/bar-end.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
cols = [x for x in range(w) if any(im.getpixel((x, y)) > 150 for y in range(h))]
if not cols:
    sys.exit(1)
right = cols[-1]
left = right
while left - 1 in cols or left - 2 in cols or left - 3 in cols:
    left -= 1
print(2360 + (left + right) // 2)
EOF
)
}

if (( ! PIL )); then
    skip "power button: python3-pillow is not installed"
elif ! wait_for 5 power_x; then
    fail "the power button: no glyph at the bar's right end"
else
    input move 2000 600 sleep 100 move "$x" 16 sleep 200 click sleep 600
    check "the power button opens the session dialog" session_dialog_open
    input key 1 sleep 300
    check "Esc closes it" lacks_layer quickshell:powermenu
fi

# 3. A long launcher query stays inside the card.
n dispatch 'hl.dsp.global("quickshell:launcher")' >/dev/null
wait_for 3 has_layer quickshell:launcher
input type "fgdfgdfgdfgdfgdsghdgkjhdfkghdfkghkdfjghkdfjhgkldjfhglkdjhgkldfjhgkldshgkdsjfhgkldsfjhgkldsfjhgkldsfhglkdsjfhgkldsfjhglksdhgdlksfjghdklsfj" sleep 400
if (( PIL )); then
    mon=$(n layers -j | jq -r 'to_entries[] | select([.value.levels[][] | .namespace] | index("quickshell:launcher")) | .key')
    shot -o "$mon" "$WORK/launcher.png"
    right=$(python3 - "$WORK/launcher.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
# The card is centred; text right of 70% of the width ran out of it. Below
# the bar, whose own readouts sit there too.
band = im.crop((int(w * 0.7), 100, w, int(h * 0.4)))
print(sum(band.histogram()[71:]))
EOF
)
    check "a long launcher query stays inside the card" test "$right" = 0
fi
input key 1 sleep 300

# 4. The key overlay keeps its switch across a reload and a restart.
input key super 21 sleep 800
check "Super+Y turns the key overlay on" overlay_on
check "and records it" file_is "$WORK/state/quickshell/bar/keyoverlay" on
reload_bar
check "the overlay is still on after a reload" overlay_on
stop_bar
start_bar
sleep 1
check "the overlay is still on after a restart" overlay_on

# 5. A reader that dies is restarted, and says why meanwhile.
echo "ERR every keyboard went away" > "$WORK/keyfifo"
echo EXIT > "$WORK/keyfifo"
sleep 0.3
# One reading for both: the supervisor starts the reader again after two
# seconds, and the reason goes with that start.
state=$(ipc e2e keys)
echo "$state" > "$WORK/reader-state.json"
check "a dead reader leaves the overlay on" test "$(jq -r .enabled <<<"$state")" = true
check "and shows its reason" test "$(jq -r .failure <<<"$state")" = "every keyboard went away"
sleep 2.5
echo "k" > "$WORK/keyfifo"
check "the reader is started again" wait_for 3 key_state_is .failure ""

# 6. Keys typed while the session is locked never reach the overlay.
ipc keys lock >/dev/null
for k in p a s s w o r d Enter; do echo "$k" > "$WORK/keyfifo"; done
sleep 0.3
check "keys typed into the lock screen are dropped" key_state_is '.chords | length' 0
ipc keys unlock >/dev/null
echo "x" > "$WORK/keyfifo"
sleep 0.3
check "keys after the unlock show" key_state_is '.chords | join(" ")' x
input key super 21 sleep 800
check "Super+Y turns it off" lacks_layer quickshell:keys
check "and records that" file_is "$WORK/state/quickshell/bar/keyoverlay" off

# 7. Notifications a reload hands back are not toasted again, and keep their marks.
for i in 1 2 3; do benv notify-send -a e2e "summary $i" "body $i"; sleep 0.2; done
n dispatch 'hl.dsp.global("quickshell:notifications")' >/dev/null
sleep 0.6
input key 1 sleep 300
benv notify-send -a e2e "summary 4" "unread"
sleep 0.5
marks_before=$(ipc e2e notifs | jq -c '[.[] | [.id, .read, .at]]')
reload_bar
check "a reload toasts nothing again" test "$(ipc e2e toasts)" = 0
check "a reload keeps read marks and times" test "$(ipc e2e notifs | jq -c '[.[] | [.id, .read, .at]]')" = "$marks_before"

# 8. The screensaver keeps dark displays dark through a reload. A minute is
# five seconds in this copy (defang.py).
printf 'name:HEADLESS-1\t1\nname:HEADLESS-2\t1\n' > "$WORK/state/quickshell/bar/screensaver"
check "with nobody at the keys both displays go off" wait_for 25 both_dpms false
reload_bar
check "a reload leaves them off" both_dpms false
input move 1200 700 sleep 100 move 1220 710
check "the next input lights them" wait_for 4 both_dpms true

# 9. A black display stays black through a reload, without a frame of the desktop.
printf 'name:HEADLESS-1\t1\n' > "$WORK/state/quickshell/bar/screensaver"
for _ in $(seq 12); do
    input move $((1000 + RANDOM % 50)) 700 >/dev/null
    has_layer quickshell:screensaver HEADLESS-1 && break
    sleep 2
done
check "the unused panel goes black while the external is in use" has_layer quickshell:screensaver HEADLESS-1
if (( PIL )); then
    mkdir -p "$WORK/frames"
    ( for i in $(seq 30); do shot -o HEADLESS-1 -t ppm "$WORK/frames/$(printf %03d "$i").ppm" 2>/dev/null; done ) &
    frames=$!
    sleep 0.2
    ipc shell reload >/dev/null
    wait "$frames"
    bright=$(python3 - "$WORK/frames" <<'EOF'
import os, sys
from PIL import Image
d = sys.argv[1]
print(max(Image.open(os.path.join(d, f)).convert("L").getextrema()[1] for f in os.listdir(d)))
EOF
)
    check "a reload shows no frame of the desktop on it" test "$bright" = 0
    wait_for 15 bar_up
fi

# 10. A region shot sees through the black and puts it back after.
for _ in 1 2 3; do input move 1100 700 >/dev/null; sleep 1; done
if has_layer quickshell:screensaver HEADLESS-1; then
    ( HOME="$WORK/home" benv bash "$WORK/config/hypr/scripts/capture.sh" region >"$WORK/capture.out" 2>&1 & )
    sleep 1.2
    check "a region shot lifts the black while it runs" lacks_layer quickshell:screensaver HEADLESS-1
    input move 500 300 sleep 150 down sleep 100 move 700 500 sleep 100 move 800 600 sleep 150 up sleep 1500
    check "the black comes back after the shot" has_layer quickshell:screensaver HEADLESS-1
    check "the shot was saved" compgen -G "$WORK/home/Pictures/Screenshots/*.png"
else
    fail "region shot: the panel was not black to begin with"
fi
rm -f "$WORK/state/quickshell/bar/screensaver"
input move 3400 600 sleep 300

# 11. Alarms: a state file that appears after the start is found, and a
# ringing alarm survives a reload.
stop_bar
rm -rf "$WORK/state/quickshell-bar"
start_bar
now=$(date +%s)
mkdir -p "$WORK/state/quickshell-bar"
printf '[{"id":"e2e","epoch":%d,"at":"%s","label":"e2e alarm","daily":false,"fired":false}]\n' \
    $((now + 2)) "$(date -d @$((now + 2)) +%H:%M)" > "$WORK/state/quickshell-bar/alarms.json"
check "an alarm in a file created after the start rings" wait_for 15 alarm_is "e2e alarm"
reload_bar
check "it is still ringing after a reload" alarm_is "e2e alarm"

# 12. A display trial outlives the bar.
OVR="$WORK/config/hypr/scripts/monitor-override.sh"
cp "$WORK/state/hypr/monitor-overrides" "$WORK/overrides.before"
trial_lines() { printf 'name:HEADLESS-1\tmode\t2880x1800@60\nname:HEADLESS-1\tscale\t1.5\nname:HEADLESS-2\tmode\t2560x1440@60\nname:HEADLESS-2\tscale\t1.25\n'; }
trial_lines | benv "$OVR" try 20 2>/dev/null
reload_bar
check "a reload during a trial keeps counting down" countdown_over 10
check "the countdown reverts the trial" wait_for 25 cmp -s "$WORK/state/hypr/monitor-overrides" "$WORK/overrides.before"
stop_bar
trial_lines | benv "$OVR" try 1 2>/dev/null
sleep 2
start_bar
check "a trial that ran out while the bar was down is reverted at its start" \
    wait_for 5 cmp -s "$WORK/state/hypr/monitor-overrides" "$WORK/overrides.before"

# 13. A display that comes later sends the brightness keys looking for it.
: > "$WORK/hardware.log"
n output remove HEADLESS-2 >/dev/null
sleep 1
n output create headless HEADLESS-2 >/dev/null
check "DDC detection runs again after a hotplug" wait_for 8 logged "$WORK/hardware.log" "ddcutil detect"
wait_for 10 outputs_are "HEADLESS-1=2880 HEADLESS-2=2560"

# 14. The suites for modules with windows, on the nested display.
if QML_TEST_WAYLAND="$RT/$WL" "$REPO/tests/unit/qml.sh" > "$WORK/qml.out"; then
    pass "$(grep -o 'qml: .*' "$WORK/qml.out" | head -1)"
else
    fail "unit tests on the nested display:"
    cat "$WORK/qml.out"
fi

check "no session action or hardware write was even attempted" no_writes

if (( failed == 0 )); then
    echo "PASS  e2e: $passed checks"
    exit 0
fi
echo "FAIL  e2e: $failed of $((passed + failed)) checks failed"
exit 1
