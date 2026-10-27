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
NESTED_PID="" DBUS_PID="" QS_PID="" SIG="" WL="" TRAY_PID="" HIDER_PID="" MPRIS_PID="" LOCK_PID="" REC_PID=""
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
    # A bar scenario 18 stopped takes no TERM until it goes on.
    kill -CONT "$QS_PID" "${tree[@]}" 2>/dev/null
    kill "$QS_PID" "${tree[@]}" 2>/dev/null
    for _ in $(seq 30); do kill -0 "$QS_PID" 2>/dev/null || break; sleep 0.1; done
    QS_PID=""
}

# A process with all under it: benv is a function, so a $! taken after it is
# the function's subshell and the program a child of that.
stop_tree() {
    local tree=()
    mapfile -t tree < <(descendants "$1")
    kill "$1" "${tree[@]}" 2>/dev/null
}

cleanup() {
    stop_bar
    # The key reader's holder outlives the bar by design; this run's, by the
    # pid it wrote, while it still is one. Its reader ends with it.
    local held
    held=$(cat "$WORK/keyfeed/hold.pid" 2>/dev/null)
    [[ -n "$held" ]] && tr '\0' ' ' <"/proc/$held/cmdline" 2>/dev/null | grep -q keyfeed-hold.py \
        && kill -TERM "$held" 2>/dev/null
    [[ -n "$TRAY_PID" ]] && kill "$TRAY_PID" 2>/dev/null
    [[ -n "$MPRIS_PID" ]] && stop_tree "$MPRIS_PID"
    [[ -n "$REC_PID" ]] && stop_tree "$REC_PID"
    # Killed, never unlocked: a signalled unlock is a failed attempt to
    # pam_faillock. Only ever the nested compositor's.
    [[ -n "$LOCK_PID" ]] && kill -KILL "$LOCK_PID" 2>/dev/null
    [[ -n "$HIDER_PID" ]] && kill -KILL "$HIDER_PID" 2>/dev/null
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
    # vfs holds a lock per shell id, and every run's bar is a new id.
    for id in "${shells[@]}"; do
        rm -rf -- "${RT:?}/quickshell/by-shell/${id:?}" "${RT:?}/quickshell/by-path/${id:?}" \
            "${RT:?}/quickshell/vfs/${id:?}"
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
        XDG_DATA_DIRS="$WORK/data:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
        CAMERA_SWITCH_SYSTEM="$WORK/bin/camera-switch-stub" CAMERA_SWITCH_FILE="$WORK/camera-off" \
        KEYFEED_SYSTEM="$WORK/keyfeed-stub" PATH="$WORK/bin:$PATH" BAR_VIZ_DEMO=1 \
        KEYFEED_SOCKET="$WORK/keyfeed/socket" KEYFEED_HOLD_DETACHED=1 \
        BAR_TRAY_HIDERS="[{\"process\": \"e2e-hider\", \"entry\": \"e2e-hider\", \"name\": \"Hider\", \"icon\": \"$WORK/hider.png\"}]" "$@"
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
# A position read from captures until two agree: Hyprland pops a new layer in
# from 93% of its size (layersIn), and a capture in those frames once put the
# badge 17 px right of where its click lands.
steady() { local last=$x; "$@" || return 1; [[ $x == "$last" ]]; }
# Captured, not ended in grep -q: an early exit under pipefail failed the
# pipe, and the ! turned many warnings into none.
no_qml_warnings() { local w; w=$(grep -E "WARN scene|ERROR" "$WORK/qs.out" | grep -v -E "portal|Could not register"); [[ -z "$w" ]]; }
# A scenario's own warnings: no line naming these files after the mark its
# start took. A reload's old generation, torn down, can warn "Unable to
# assign [undefined]" from any file it had loaded (Theme, Brightness and
# Calls seen, 2026-10-27), which is no later scenario's doing; warnings at
# load are scenario 1's. The lines found are printed.
output_mark() { wc -l < "$WORK/qs.out"; }
quiet_since() { local w; w=$(tail -n +"$(( $1 + 1 ))" "$WORK/qs.out" | grep -E "$2"); [[ -z "$w" ]] || { echo "$w"; return 1; }; }
session_dialog_open() { has_layer quickshell:powermenu && [[ "$(ipc e2e session)" == true ]]; }
overlay_on() { has_layer quickshell:keys && key_state_is .enabled true; }
no_writes() { ! grep -q -E '^(lock|suspend|session-power|ddc-set|backlight-set)' "$WORK/apps.log" 2>/dev/null; }
shot_saved() { compgen -G "$WORK/home/Pictures/Screenshots/*.png" >/dev/null; }

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
# The camera indicator reads a switch that is on, with no camera: the bar
# under test must not read this machine's cameras or watch its devices.
cat > "$WORK/bin/camera-switch-stub" <<'EOF'
#!/bin/sh
echo '{"switch": "on", "busy": false, "cameras": [], "power_switches": [], "missing": []}'
EOF
cat > "$WORK/bin/udevadm" <<'EOF'
#!/bin/sh
exec tail -f /dev/null --pid="$PPID"
EOF
chmod +x "$WORK/bin/camera-switch-stub" "$WORK/bin/udevadm"
# pkexec runs the key reader's stand-in as asked, with no password: the bar
# under test must never put a dialog on the real session. Compiled, so that
# it shows as pkexec until it becomes the reader, as the real one does, and
# it logs the process it runs for: one line a password would have cost.
cat > "$WORK/pkexec.c" <<'C'
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    FILE *log = fopen(PKEXEC_LOG, "a");
    if (log) { fprintf(log, "%d\n", (int)getppid()); fclose(log); }
    if (argc < 2) return 127;
    execvp(argv[1], argv + 1);
    return 127;
}
C
gcc -O1 -DPKEXEC_LOG="\"$WORK/pkexec.log\"" -o "$WORK/bin/pkexec" "$WORK/pkexec.c" \
    || { echo "FAIL  e2e: the pkexec stand-in does not build"; exit 1; }
# An application that hides its window and has no tray item, as KakaoTalk:
# a copy of sleep, so the kernel calls it e2e-hider, which the bar under test
# is told to look for (BAR_TRAY_HIDERS) and the running bar knows nothing of.
cp "$(command -v sleep)" "$WORK/bin/e2e-hider"
magick -size 22x22 xc:white "$WORK/hider.png"
mkdir -p "$WORK/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Hider\nExec=touch %s/hider-opened\n' "$WORK" \
    > "$WORK/data/applications/e2e-hider.desktop"
# The program sharing the screen, as PipeWire shows it: pw-dump's stand-in
# links the portal's screen to a stream of e2e-sharer's, which no window
# owns, so the bar names it by its desktop entry, its icon a green nothing
# else on the bar has. It also keeps the bar off this machine's PipeWire.
magick -size 48x48 xc:'#20d060' "$WORK/sharer.png"
printf '[Desktop Entry]\nType=Application\nName=Sharer\nIcon=%s/sharer.png\nExec=true\n' "$WORK" \
    > "$WORK/data/applications/e2e-sharer.desktop"
# Programs on the microphone, for the island's calls (services/Calls.qml):
# one an ordinary program's, in blue, and one a recorder's, which is no
# call. Handed to the bar by the probe (callsFake): no microphone of this
# machine's reaches the nested session.
magick -size 48x48 xc:'#2050e0' "$WORK/caller.png"
printf '[Desktop Entry]\nType=Application\nName=Caller\nIcon=%s/caller.png\nExec=true\nCategories=Network;\n' "$WORK" \
    > "$WORK/data/applications/e2e-caller.desktop"
printf '[Desktop Entry]\nType=Application\nName=Recorder\nExec=true\nCategories=AudioVideo;Recorder;\n' \
    > "$WORK/data/applications/e2e-recorder.desktop"
cat > "$WORK/bin/pw-dump" <<'EOF'
#!/bin/sh
cat <<'JSON'
[{"id": 41, "type": "PipeWire:Interface:Client", "info": {"props": {"application.name": "Sharer", "application.process.binary": "e2e-sharer", "application.process.id": 1}}},
 {"id": 100, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Video/Source", "client.id": 40}}},
 {"id": 101, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Stream/Input/Video", "client.id": 41}}},
 {"id": 200, "type": "PipeWire:Interface:Link", "info": {"output-node-id": 100, "input-node-id": 101}}]
JSON
EOF
chmod +x "$WORK/bin/pw-dump"

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
    printf 'MONITOR_POLICY_OVERRIDE = { internal = { "^HEADLESS%%-1$" }, synthetic = { "^FALLBACK$", "^WAYLAND%%-" }, sysfs = false, auto_scale = false, acpi_lid = "%s", lid_lock_cmd = "echo lock >> %s/locks", settle_removed_ms = 300, settle_added_ms = 300, verify_ms = 1500, panel_off_delay_ms = 200, panel_off_verify_ms = 400 }\n' "$WORK/acpi" "$WORK"
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
elif ! { x=""; wait_for 5 steady power_x; }; then
    fail "the power button: no glyph at the bar's right end"
else
    # Waited for, not slept on: on a loaded machine the dialog maps later
    # than any fixed pause, and the check failed once beside a busy build.
    input move 2000 600 sleep 100 move "$x" 16 sleep 200 click sleep 100
    check "the power button opens the session dialog" wait_for 3 session_dialog_open
    input key 1 sleep 100
    check "Esc closes it" wait_for 2 lacks_layer quickshell:powermenu
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

# 4. The key overlay's password is asked only when Super+Y turns it on (the
# user, 2026-10-26): a reload or a restart finds the held reader again.
# Each line in pkexec.log is a password the real pkexec would have asked for.
asked() { wc -l < "$WORK/pkexec.log" 2>/dev/null || echo 0; }
input key super 21 sleep 800
check "Super+Y turns the key overlay on" overlay_on
check "asking for its password once" test "$(asked)" = 1
check "its reader held for the bar, not the bar's own child" \
    test "$(tail -1 "$WORK/pkexec.log")" = "$(cat "$WORK/keyfeed/hold.pid" 2>/dev/null)"
reload_bar
check "the overlay is still on after a reload" wait_for 5 overlay_on
check "and the reload asked nothing" test "$(asked)" = 1
stop_bar
start_bar
sleep 1
check "the overlay is still on after a restart" wait_for 5 overlay_on
check "and the restart asked nothing" test "$(asked)" = 1

# 5. A reader that dies says why, and is not started again behind the
# user's back: every start asks for a password. Super+Y twice starts it.
echo "ERR every keyboard went away" > "$WORK/keyfifo"
echo EXIT > "$WORK/keyfifo"
sleep 0.3
state=$(ipc e2e keys)
echo "$state" > "$WORK/reader-state.json"
check "a dead reader leaves the overlay on" test "$(jq -r .enabled <<<"$state")" = true
check "and shows its reason" test "$(jq -r .failure <<<"$state")" = "every keyboard went away"
sleep 2.5
check "and is not started again by itself" key_state_is .failure "every keyboard went away"
input key super 21 sleep 800
input key super 21 sleep 800
# Bounded: with no reader started, a write to the fifo would wait forever.
timeout 5 tee "$WORK/keyfifo" <<<k >/dev/null
check "Super+Y twice starts it again" wait_for 3 key_state_is .failure ""

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
check "and its holder goes with the reader" wait_for 3 test ! -e "$WORK/keyfeed/socket"

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
    check "the shot was saved" shot_saved
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

# 14. The badge's menu draws every mark it offers, at one size, and a mark
# picked from it is the badge from then on, through a reload.
badge_x() {
    shot -g "0,0 200x34" "$WORK/bar-start.png" 2>/dev/null || return 1
    x=$(python3 - "$WORK/bar-start.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
cols = [x for x in range(w) if any(im.getpixel((x, y)) > 150 for y in range(h))]
if not cols:
    sys.exit(1)
left = right = cols[0]
while right + 1 in cols or right + 2 in cols or right + 3 in cols:
    right += 1
print((left + right) // 2)
EOF
)
}
# Below the bar, where the menu opens; picker.py reads it against a capture
# taken while the menu was closed.
PICKER_AREA="0,40 760x560"
picker_open() { shot -g "$PICKER_AREA" "$WORK/picker.png" && python3 "$REPO/tests/e2e/picker.py" "$WORK/picker-closed.png" "$WORK/picker.png" > "$WORK/picker.json"; }
picker_closed() { shot -g "$PICKER_AREA" "$WORK/picker-now.png"; python3 "$REPO/tests/e2e/picker.py" "$WORK/picker-closed.png" "$WORK/picker-now.png" >/dev/null; [[ $? == 1 ]]; }
badge_is() { [[ "$(ipc e2e badge | jq -r .choice)" == "$1" ]]; }
marks_drawn() { [[ "$(jq '.tiles | length' "$WORK/picker.json")" == "$(ipc e2e badge | jq '.offered | length')" ]]; }
marks_differ() { jq -e '[.tiles[].ink] | (unique | length) == length' "$WORK/picker.json" >/dev/null; }
marks_even() { jq -e '[.tiles[] | [.w, .h] | max] | max / min < 1.15' "$WORK/picker.json" >/dev/null; }
open_picker() {
    input move 2000 600 sleep 100 move "$x" 16 sleep 200 click sleep 100
    wait_for 3 picker_open
}

if (( ! PIL )); then
    skip "badge: python3-pillow is not installed"
elif ! { x=""; wait_for 5 steady badge_x; }; then
    fail "the badge: no glyph at the bar's left end"
else
    shot -g "$PICKER_AREA" "$WORK/picker-closed.png"
    if open_picker; then
        pass "a click on the badge opens its menu"
        check "every mark it offers is drawn" marks_drawn
        check "no two are drawn alike" marks_differ
        check "they are drawn at one size" marks_even
        i=$(ipc e2e badge | jq '.offered | index("void")')
        read -r tx ty < <(jq -r --argjson i "$i" '.tiles[$i] | "\(.x) \(.y + 40)"' "$WORK/picker.json")
        input move "$tx" "$ty" sleep 200 click sleep 100
        check "a mark picked from it is the badge" wait_for 3 badge_is void
        check "the menu closes on the pick" wait_for 3 picker_closed
        check "the pick is kept" file_is "$WORK/state/quickshell/bar/badge" void
        reload_bar
        check "and outlives a reload" badge_is void
        if open_picker; then
            read -r ax ay < <(jq -r '.automatic | "\(.[0]) \(.[1] + 40)"' "$WORK/picker.json")
            input move "$ax" "$ay" sleep 200 click sleep 100
            check "Automatic gives the badge back to os-release" wait_for 3 badge_is auto
        else
            fail "the badge's menu after a reload"
        fi
    else
        fail "a click on the badge opens its menu"
    fi
    input move 2000 600 sleep 100
fi

# 15. The suites for modules with windows, on the nested display.
if QML_TEST_WAYLAND="$RT/$WL" "$REPO/tests/unit/qml.sh" > "$WORK/qml.out"; then
    pass "$(grep -o 'qml: .*' "$WORK/qml.out" | head -1)"
else
    fail "unit tests on the nested display:"
    cat "$WORK/qml.out"
fi

# 16. The lid: shut beside an external it only darkens the panel; shut with
# no other display it locks (monitors.lua). The lock goes to $WORK/locks.
locks() { if [[ -f "$WORK/locks" ]]; then wc -l < "$WORK/locks"; else echo 0; fi; }
locked_once() { [[ "$(locks)" == 1 ]]; }
n eval 'MONITORS.lid_close()' >/dev/null
sleep 2.5
check "the lid shut beside an external does not lock" test "$(locks)" = 0
n eval 'MONITORS.lid_open()' >/dev/null
n output remove HEADLESS-2 >/dev/null
sleep 1.5
n eval 'MONITORS.lid_close()' >/dev/null
check "the lid shut with no other display locks" wait_for 5 locked_once
n eval 'MONITORS.lid_open()' >/dev/null

# 17. The external unplugged beside a panel the screensaver keeps dark: the
# panel shows the desktop. Black for being unused, it is in use once it is
# the only screen. Off and then lit by something else, it is seen lit when
# the displays are read again: the workspace events of the unplug already
# cause a reading, but reconcile passes over one taken within its settle
# window of the saver's request, so the bar reads them once more after it
# (2026-10-17: the panel stayed black on the desk).
replug() {
    outputs_are "HEADLESS-1=2880 HEADLESS-2=2560" || n output create headless HEADLESS-2 >/dev/null
    wait_for 10 outputs_are "HEADLESS-1=2880 HEADLESS-2=2560"
    sleep 0.5
}
panel_off() { [[ "$(dpms HEADLESS-1)" == false ]]; }
replug
printf 'name:HEADLESS-1\t1\n' > "$WORK/state/quickshell/bar/screensaver"
for _ in $(seq 12); do
    input move $((1000 + RANDOM % 50)) 700 >/dev/null
    has_layer quickshell:screensaver HEADLESS-1 && break
    sleep 2
done
if has_layer quickshell:screensaver HEADLESS-1; then
    n output remove HEADLESS-2 >/dev/null
    check "unplugged from the external, a panel black for being unused is lit at once" \
        wait_for 1 lacks_layer quickshell:screensaver HEADLESS-1
else
    fail "unplug: the panel was not black to begin with"
fi
for settled in 1 0; do
    replug
    input move 1000 700 >/dev/null
    if ! wait_for 25 panel_off; then
        fail "unplug: the panel did not go off with nobody at the keys"
        continue
    fi
    # Lit behind the bar's back, long after its request or within reconcile's
    # settle window; nothing but the change of screens may lift the black.
    (( settled )) && sleep 5
    n dispatch 'hl.dsp.dpms({ action = "enable", monitor = "HEADLESS-1" })' >/dev/null
    sleep 0.5
    n output remove HEADLESS-2 >/dev/null
    if (( settled )); then
        check "nor one the saver turned off and something else lit" wait_for 2 lacks_layer quickshell:screensaver HEADLESS-1
    else
        check "nor one lit again right after the saver's request" wait_for 8 lacks_layer quickshell:screensaver HEADLESS-1
    fi
done
rm -f "$WORK/state/quickshell/bar/screensaver"

# 18. bin/recover-desktop finds a lit display that shows nothing but black
# and has the bar's screensaver let go of it, with no modeset or bar
# restart. Its systemd steps go to stubs, since they would reach this
# session's units; the outputs it may count as real are listed in a stand-in
# for /sys/class/drm (WAYLAND-1 too, which it would otherwise remove).
mkdir -p "$WORK/recover-bin"
for o in HEADLESS-1 HEADLESS-2 WAYLAND-1; do
    mkdir -p "$WORK/drm/card0-$o"
    echo connected > "$WORK/drm/card0-$o/status"
done
printf '#!/bin/sh\necho "dbus-update-activation-environment $*" >> "%s/recover-calls"\n' "$WORK" \
    > "$WORK/recover-bin/dbus-update-activation-environment"
# A restart of bar.service lets a bar the test stopped go on (bar.stopped
# lists its processes), which then answers as a new one would.
cat > "$WORK/recover-bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >> "$WORK/recover-calls"
case "\$*" in
    *"restart bar.service"*) [ -f "$WORK/bar.stopped" ] && kill -CONT \$(cat "$WORK/bar.stopped") ;;
esac
exit 0
EOF
chmod +x "$WORK/recover-bin/systemctl" "$WORK/recover-bin/dbus-update-activation-environment"
recover() {
    env PATH="$WORK/recover-bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE="$SIG" RECOVER_DRM_DIR="$WORK/drm" \
        BAR_CONFIG_DIR="$WORK/bar" "$REPO/bin/recover-desktop" "$@"
}
replug
ipc screensaver preview HEADLESS-1 60 >/dev/null
if wait_for 3 has_layer quickshell:screensaver HEADLESS-1; then
    recover > "$WORK/recover.out" 2>&1
    check "recover-desktop finds the lit display that shows only black" \
        logged "$WORK/recover.out" "lit but showing nothing but black: HEADLESS-1"
    check "and the bar's screensaver lets go of it" lacks_layer quickshell:screensaver HEADLESS-1
    check "without a modeset" bash -c "! grep -q 'DPMS off, then on' '$WORK/recover.out'"
    check "or a bar restart" bash -c "! grep -q 'restart bar.service' '$WORK/recover-calls'"
    recover --status > "$WORK/recover-status.out" 2>&1
    check "then nothing reads black" bash -c "! grep -q 'nothing but black' '$WORK/recover-status.out'"
    check "and the bar is found on both displays" \
        logged "$WORK/recover-status.out" "the bar answers and is drawn on every display"
else
    fail "recover: the preview did not black the panel"
fi

# A bar that hangs is started anew: its windows stay on screen, but it
# answers nothing within the timeout. Stopped here with SIGSTOP, the whole
# tree; the stub's restart lets it go on.
: > "$WORK/recover-calls"
mapfile -t bar_tree < <(descendants "$QS_PID")
echo "$QS_PID ${bar_tree[*]}" > "$WORK/bar.stopped"
kill -STOP "$QS_PID" "${bar_tree[@]}"
recover > "$WORK/recover-hung.out" 2>&1
rc=$?
kill -CONT "$QS_PID" "${bar_tree[@]}" 2>/dev/null
rm -f "$WORK/bar.stopped"
check "recover-desktop finds a bar that does not answer" \
    logged "$WORK/recover-hung.out" "the bar does not answer over IPC within 3 s; starting it anew"
check "and restarts it, its start limit reset first" \
    bash -c "grep -A1 'reset-failed bar.service$' '$WORK/recover-calls' | grep -q 'restart bar.service'"
check "then finds it on both displays" \
    logged "$WORK/recover-hung.out" "the bar answers and is drawn on every display again"
check "and exits 0" test "$rc" = 0
wait_for 5 bar_up

# 19. The session dialog shows over the screensaver's black.
ipc screensaver preview HEADLESS-1 30 >/dev/null
input move 3400 600 sleep 200 move 3420 610 >/dev/null
n dispatch 'hl.dsp.global("quickshell:powerMenu")' >/dev/null
if wait_for 3 has_layer quickshell:powermenu HEADLESS-1 && wait_for 3 has_layer quickshell:screensaver HEADLESS-1; then
    sleep 0.5
    # Counted, not the brightest pixel: the pointer sits on this screen and
    # the nested compositor draws it into the capture (about 300 pixels; the
    # dialog lights about 30000).
    lit=0
    if (( PIL )) && shot -o HEADLESS-1 -t ppm "$WORK/dialog.ppm" 2>/dev/null; then
        lit=$(python3 -c 'import sys; from PIL import Image; print(sum(Image.open(sys.argv[1]).convert("L").histogram()[41:]))' "$WORK/dialog.ppm")
    fi
    if (( PIL )); then
        check "the session dialog is drawn over the black" test "$lit" -gt 5000
    else
        skip "session dialog over the black: python3-pillow is not installed"
    fi
else
    fail "the session dialog over the black: it did not open on the black panel"
fi
input key 1 sleep 300
ipc screensaver wake >/dev/null

# 20. The key overlay's guard for a terminal asking for a password, in a
# window opened after the bar started. quickshell knew no pid for such a
# window, so its terminal was never watched (2026-10-17). promptwin.py's
# process holds a terminal with its echo off, as a shell under sudo does.
promptwin_pid() { n clients -j | jq -r '[.[] | select(.class == "promptwin") | .pid] | first // empty'; }
promptwin_up() { [[ -n "$(promptwin_pid)" ]]; }
input key super 21 sleep 800
if overlay_on; then
    n dispatch "hl.dsp.exec_cmd('python3 -I $REPO/tests/e2e/promptwin.py')" >/dev/null
    if wait_for 10 promptwin_up; then
        pid=$(promptwin_pid)
        n dispatch "hl.dsp.focus({ window = 'class:promptwin' })" >/dev/null
        check "a window opened after the bar is known by its pid" wait_for 3 key_state_is .pid "$pid"
        check "its terminal asking for a password pauses the key reader" wait_for 3 key_state_is .secret true
        kill -USR1 "$pid"
        check "and the prompt's end lets the reader go" wait_for 3 key_state_is .secret false
        kill "$pid"
    else
        fail "the guard: the prompt window did not open"
    fi
    input key super 21 sleep 800
    check "Super+Y turns the overlay off again" lacks_layer quickshell:keys
else
    fail "the guard: the overlay did not come on"
fi

# 21. Applications running with no window show between the workspaces and
# the app name (services/Tray.qml) and are quit from there: a tray item
# through its own menu's Exit (trayapp.py, as Zoom), a process found by name
# through Quit (e2e-hider, as KakaoTalk), which a click first opens by running
# its desktop entry. A window opening is what has the bar look for hiders, as
# KakaoTalk's own window would.
mark=$(output_mark)
tray_is() { [[ "$(ipc e2e tray | jq -c "$1")" == "$2" ]]; }
# The icons are solid white squares in a capture of the bar's left part: the
# workspace indicator is taller, digits and letters are thinner.
tray_x() {
    shot -g "0,0 1000x34" "$WORK/tray.png" 2>/dev/null || return 1
    x=$(python3 - "$WORK/tray.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
def tallest(x):
    best = run = 0
    for y in range(h):
        run = run + 1 if im.getpixel((x, y)) > 200 else 0
        best = max(best, run)
    return best
square = [14 <= tallest(x) <= 20 for x in range(w)] + [False]
found, start = [], None
for x, on in enumerate(square):
    if on and start is None:
        start = x
    elif not on and start is not None:
        if 14 <= x - start <= 20:
            found.append(str((start + x - 1) // 2))
        start = None
if not found:
    sys.exit(1)
print(" ".join(found))
EOF
)
}
# The menu under an icon at x: its entries' text lines, top to bottom, as
# screen y (the separator is too faint to count).
menu_rows() {
    shot -g "$(( $1 - 150 )),40 300x220" "$WORK/traymenu.png" 2>/dev/null || return 1
    rows=$(python3 - "$WORK/traymenu.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
lit = [any(im.getpixel((x, y)) > 150 for x in range(w)) for y in range(h)] + [False]
found, start = [], None
for y, on in enumerate(lit):
    if on and start is None:
        start = y
    elif not on and start is not None:
        if y - start >= 6:
            found.append(str(40 + (start + y - 1) // 2))
        start = None
print(" ".join(found))
EOF
)
}
rows_are() { menu_rows "$1" && [[ $(wc -w <<<"$rows") == "$2" ]]; }
# The last lit column of the bar's left part: with no window focused, the
# end of the workspaces.
lit_end() {
    shot -g "0,0 1000x34" "$WORK/tray-before.png" 2>/dev/null || return 1
    python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("L"); w, h = im.size
print(max(x for x in range(w) if any(im.getpixel((x, y)) > 150 for y in range(h))))' "$WORK/tray-before.png"
}
hider_gone() { [[ ! -e "/proc/$HIDER_PID" || "$(cut -d' ' -f3 "/proc/$HIDER_PID/stat" 2>/dev/null)" == Z ]]; }
hider_opened() { [[ -e "$WORK/hider-opened" ]] || logged "$WORK/apps.log" "$WORK/hider-opened"; }
right_click() { input move 2000 600 sleep 100 move "$1" 16 sleep 200 click right sleep 100; }

if (( ! PIL )); then
    skip "tray: python3-pillow is not installed"
else
    check "no icons while nothing runs hidden" tray_is . '{"items":[],"hiders":[]}'
    input move 2000 600 sleep 300
    ws_end=$(lit_end)
    benv python3 -I "$REPO/tests/e2e/trayapp.py" "$WORK/tray.log" &
    TRAY_PID=$!
    "$WORK/bin/e2e-hider" 120 &
    HIDER_PID=$!
    n dispatch "hl.dsp.exec_cmd('[workspace 3 silent] python3 -I $REPO/tests/e2e/promptwin.py')" >/dev/null
    wait_for 10 promptwin_up && kill "$(promptwin_pid)"
    check "a tray item and a hider show" wait_for 8 tray_is . '{"items":["E2E tray"],"hiders":["Hider"]}'
    if wait_for 5 steady tray_x && [[ $(wc -w <<<"$x") == 2 ]]; then
        read -r item_x hider_x <<<"$x"
        check "both are drawn right of the workspaces" test "$item_x" -gt "$(( ${ws_end:-9999} + 8 ))"
        input move 2000 600 sleep 100 move "$item_x" 16 sleep 200 click sleep 100
        check "a click opens the tray item's application" wait_for 3 logged "$WORK/tray.log" activate
        right_click "$item_x"
        if wait_for 5 rows_are "$item_x" 2; then
            pass "a right click opens its own menu, Open and Exit"
            exit_y=$(awk '{print $2}' <<<"$rows")
            input move "$item_x" "$exit_y" sleep 200 click sleep 100
            check "its Exit reaches the application" wait_for 3 logged "$WORK/tray.log" "event 3 clicked"
            check "whose icon goes when it ends" wait_for 5 tray_is .items '[]'
        else
            fail "a right click opens its own menu, Open and Exit"
        fi
        input move 2000 600 sleep 300
        if wait_for 5 steady tray_x && [[ $(wc -w <<<"$x") == 1 ]]; then
            hider_x=$x
            input move 2000 600 sleep 100 move "$hider_x" 16 sleep 200 click sleep 100
            check "a click on the hider runs its desktop entry" wait_for 3 hider_opened
            right_click "$hider_x"
            if wait_for 5 rows_are "$hider_x" 2; then
                pass "a right click opens the hider's menu, Open and Quit"
                quit_y=$(awk '{print $2}' <<<"$rows")
                input move "$hider_x" "$quit_y" sleep 200 click sleep 100
                check "Quit ends the hider" wait_for 5 hider_gone
                wait "$HIDER_PID"
                check "with TERM" test $? = 143
                HIDER_PID=""
                check "and its icon goes" wait_for 3 tray_is .hiders '[]'
            else
                fail "a right click opens the hider's menu, Open and Quit"
            fi
        else
            fail "the hider's icon after the tray item ended"
        fi
    else
        fail "two icons are drawn"
    fi
    input move 2000 600 sleep 100
    check "the tray's files raised no QML warning" quiet_since "$mark" 'Tray(Icons)?\.qml'
fi

# 22. Nothing on the bar opens under the pointer but the clock's month (and
# the player card while something plays, which this session has no player
# for), and only what a click or the pointer acts on lights up and turns the
# pointer into a hand, as the user chose: no tooltips, nothing on a plain
# readout. Every lit spot of the external's bar is hovered in turn,
# entering from below, and compared with captures taken with the pointer
# away: the strip under the bar, and the rows above the spot's ink, which a
# highlight covers and the pointer does not. The clock, second from the
# right end, is the control for the strip: a hover that never reached the
# bar would pass the rest. The badge and the power button take a click, the
# clock opens its month, and the cameras-off glyph, called up through the
# stub, is a plain readout; these are on every machine, in places known.
# Last, the status items stand at even gaps, a glyph and its value counted
# as one item and the value padded inside it (the user's layout).
mark=$(output_mark)
bar_spots() {
    shot -g "0,0 2560x34" "$WORK/bar-all.png" 2>/dev/null || return 1
    spots=$(python3 - "$WORK/bar-all.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
lit = [x for x in range(w) if any(im.getpixel((x, y)) > 100 for y in range(h))]
# Items stand 25 px apart at this size; gaps inside one are under 10.
spots, start = [], None
for i, x in enumerate(lit):
    if start is None:
        start = x
    if i + 1 == len(lit) or lit[i + 1] - x > 14:
        spots.append(f"{start}:{x}")
        start = None
if len(spots) < 3:
    sys.exit(1)
print(" ".join(spots))
EOF
)
}
# From y 48: the pointer resting on the bar draws down to 40.
UNDER_BAR="0,48 2560x400"
# The spot from $1 to $2 hovered: pixels changed under the bar, then above
# its ink. Rows 6-9 lie inside a highlight (from barInset, 5 px) and above
# both the ink and the pointer, which rests at y 16.
hover_change() {
    input move 2000 600 sleep 400
    shot -g "0,0 2560x34" "$WORK/bar-away.png" 2>/dev/null || return 1
    shot -g "$UNDER_BAR" "$WORK/under-away.png" 2>/dev/null || return 1
    input move "$(( ($1 + $2) / 2 ))" 16 sleep 700
    shot -g "0,0 2560x34" "$WORK/bar-hover.png" 2>/dev/null || return 1
    shot -g "$UNDER_BAR" "$WORK/under-hover.png" 2>/dev/null || return 1
    python3 - "$WORK" "$1" "$2" <<'EOF'
import sys
from PIL import Image, ImageChops
work, x0, x1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def changed(name, box, step):
    a, b = (Image.open(f"{work}/{name}-{s}.png").convert("L") for s in ("away", "hover"))
    if box:
        a, b = a.crop(box), b.crop(box)
    return ImageChops.difference(a, b).point(lambda v: 255 if v > step else 0).histogram()[255]
print(changed("under", None, 40), changed("bar", (x0, 6, x1 + 1, 10), 10))
EOF
}
# The pointer's shape over the spot from $1 to $2, saved as $3: resting at
# y 28, its lower part hangs below the bar, over a plain background (the
# desktop, or the month's margin under the clock).
pointer_shot() {
    local x=$(( ($1 + $2) / 2 ))
    input move 2000 600 sleep 300 move "$x" 28 sleep 600
    shot -g "$(( x - 16 )),36 48x15" "$WORK/pointer-$3.png" 2>/dev/null
}
# How alike two pointer shapes are: the share of their pixels in common,
# each shape being what stands out from its capture's background.
pointer_alike() {
    python3 - "$WORK/pointer-$1.png" "$WORK/pointer-$2.png" <<'EOF'
import sys
from PIL import Image
def shape(path):
    px = list(Image.open(path).convert("L").tobytes())
    bg = max(set(px), key=px.count)
    return {i for i, v in enumerate(px) if abs(v - bg) > 40}
a, b = shape(sys.argv[1]), shape(sys.argv[2])
print(f"{len(a & b) * 100 // max(1, len(a | b))} {min(len(a), len(b))}")
EOF
}
camera_stub() {
    printf '#!/bin/sh\necho %s\n' "'{\"switch\": \"$1\", \"busy\": false, \"cameras\": [$2], \"power_switches\": [], \"missing\": []}'" \
        > "$WORK/bin/camera-switch-stub"
    ipc camera refresh >/dev/null
}
camera_is() { [[ "$(ipc camera state)" == "$1" ]]; }
status_gaps() {
    input move 2000 600 sleep 400
    shot -g "0,0 2560x34" "$WORK/bar-gaps.png" 2>/dev/null || return 1
    ipc e2e statusBoxes > "$WORK/boxes.json" || return 1
    gaps=$(python3 - "$WORK/bar-gaps.png" "$WORK/boxes.json" <<'EOF'
import json, sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
def ink(box):
    cols = [x for x in range(max(0, box["x"]), min(im.width, box["x"] + box["w"]))
            if any(im.getpixel((x, y)) > 50 for y in range(2, 31))]
    return (cols[0], cols[-1]) if cols else None
gaps, last = [], None
for box in json.load(open(sys.argv[2])):
    span = None if box["filled"] else ink(box)
    if span and last:
        gaps.append(span[0] - last[1] - 1)
    last = span
if len(gaps) < 4:
    sys.exit(1)
print(" ".join(map(str, gaps)))
EOF
)
}
# Even: no gap more than 3 px from another (side bearings differ by a pixel).
gaps_even() { local g; g=$(tr ' ' '\n' <<<"$gaps" | sort -n); (( $(tail -1 <<<"$g") - $(head -1 <<<"$g") <= 3 )); }

if (( ! PIL )); then
    skip "hover: python3-pillow is not installed"
elif ! wait_for 5 bar_spots; then
    fail "hover: nothing lit on the bar"
else
    before=" $spots "
    camera_stub off '{"name": "E2E", "state": "off", "nodes": []}'
    wait_for 5 camera_is off && sleep 0.5
    wait_for 5 bar_spots
    read -r -a spot <<<"$spots"
    badge=${spot[0]} clock=${spot[-2]} power=${spot[-1]} camera=""
    # In the status group, right of the middle: a part of the bar still
    # settling after a start (the badge) may differ between the two captures.
    for s in "${spot[@]}"; do
        (( ${s%:*} > 1280 )) || continue
        [[ $before == *" $s "* || -n $camera ]] || camera=$s
    done
    opened=() badge_lit="" power_lit="" camera_lit=""
    for s in "${spot[@]}"; do
        [[ $s == "$clock" ]] && continue
        read -r under lit < <(hover_change "${s%:*}" "${s#*:}") || { opened+=("$s:no-capture"); continue; }
        (( under > 100 )) && opened+=("$s:$under")
        [[ $s == "$badge" ]] && badge_lit=$lit
        [[ $s == "$power" ]] && power_lit=$lit
        [[ $s == "$camera" ]] && camera_lit=$lit
    done
    (( ${#opened[@]} )) && echo "e2e: opened under x0:x1:pixels ${opened[*]}"
    check "hovering the bar opens nothing" test "${#opened[@]}" = 0
    under="" lit=""
    read -r under lit < <(hover_change "${clock%:*}" "${clock#*:}")
    echo "e2e: changed pixels: month ${under:-none}; above the ink: clock ${lit:-none}," \
        "badge ${badge_lit:-none}, power ${power_lit:-none}, cameras off (${camera:-not found}) ${camera_lit:-none}"
    check "hovering the clock opens the month" test "${under:-0}" -gt 500
    check "the clock lights up under the pointer, as the badge and the power button do" \
        test "${lit:-0}" -gt 8 -a "${badge_lit:-0}" -gt 8 -a "${power_lit:-0}" -gt 8
    check "a plain readout does not" test -n "$camera" -a "${camera_lit:-99}" -le 2
    if [[ -n $camera ]] && pointer_shot "${power%:*}" "${power#*:}" power \
        && pointer_shot "${clock%:*}" "${clock#*:}" clock && pointer_shot "${camera%:*}" "${camera#*:}" plain; then
        read -r same same_px < <(pointer_alike power clock)
        read -r other other_px < <(pointer_alike power plain)
        echo "e2e: pointer shapes alike: clock and power ${same:-?}% (${same_px:-?} px), plain readout and power ${other:-?}% (${other_px:-?} px)"
        check "the pointer is the same hand over the clock as over the power button" \
            test "${same:-0}" -ge 80 -a "${same_px:-0}" -ge 20
        check "and another shape over a plain readout" test "${other:-100}" -le 60 -a "${other_px:-0}" -ge 20
    else
        fail "the pointer's shapes: no capture, or no plain readout found"
    fi
    # One gap between every two items, a glyph and its value counted as one:
    # from the end of one item's ink to the start of the next one's, in rows
    # clear of the bar's edges, dim glyphs included. A filled pill (an alarm
    # ringing) is its own box edge to edge and is left out.
    if status_gaps; then
        echo "e2e: gaps between status items: ${gaps:-none}"
        check "the status items stand at even gaps" gaps_even
    else
        fail "the status items' gaps: no capture or no boxes"
    fi

    camera_stub on ""
    check "the cameras-off glyph goes again" wait_for 5 camera_is on
    input move 2000 600 sleep 400
    check "the hovered files raised no QML warning" \
        quiet_since "$mark" '[@/](StatusItems?|CalendarPopup|CalendarMonth|MediaChip|SystemBadge|AppTitle|Workspaces|Bar)\.qml'
fi

# 23. A click on the speaker mutes or unmutes the output, as the mute key
# does. The click reaches Volume.toggleMute, whose write the copy refuses
# with a log line (defang.py) rather than muting this machine.
speaker_x() { x=$(ipc e2e sound | jq -r .x 2>/dev/null); [[ $x =~ ^[0-9]+$ ]] && (( x > 0 )); }
mutes_asked() { grep -c '\[e2e\] mute refused' "$WORK/qs.out"; }
mute_asked() { (( $(mutes_asked) > asked_before )); }

if ! wait_for 5 speaker_x; then
    fail "the speaker: not found on the bar"
elif [[ "$(ipc e2e sound | jq -r .known)" != true ]]; then
    skip "the speaker: Pipewire gave the nested bar no output to mute"
else
    asked_before=$(mutes_asked)
    input move 2000 600 sleep 100 move "$x" 16 sleep 200 click sleep 100
    check "a click on the speaker mutes or unmutes the output" wait_for 3 mute_asked
    input move 2000 600 sleep 100
fi

# 24. A toast is laid out as the banner the user chose as the model,
# measured the same way in both, in each one's em: the model's text, a
# corner fitted with a circle, baselines from each line's ink profile. The
# model's figures (em 27 px): 25.56 em wide, ink 1.00 em in from the left and
# under the top, baselines 1.185 em apart, the last 1.148 em over the bottom,
# corners 1.19 em, 0.458 bar heights under the bar, the right edge under the
# bar's last glyph.
toast_layout() {
    shot -g "0,0 2560x400" "$WORK/toast.png" 2>/dev/null || return 1
    layout=$(python3 - "$WORK/toast.png" <<'EOF'
import json, math, sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
px = im.load()
W, H = im.size
# The bar: its rows in its own colour (Theme.bg, #0f111b; no edge line since
# 2026-10-27), read where nothing is drawn on it.
rgb = Image.open(sys.argv[1]).convert("RGB").load()
rows = [y for y in range(0, 80) if max(abs(a - b) for a, b in zip(rgb[1300, y], (15, 17, 27))) <= 3]
bar = rows[-1] + 1 if rows else None
# The last glyph on the bar.
glyph_end = max(x for x in range(2300, W) if any(px[x, y] > 100 for y in range(2, bar - 3)))
# The card: its hairline border, outside the bar, right of the screen's middle.
border = [(x, y) for y in range(bar + 2, H) for x in range(1400, W) if 28 <= px[x, y] <= 70]
left = min(x for x, _ in border); right = max(x for x, _ in border)
top = min(y for _, y in border); bottom = max(y for _, y in border)
text = lambda x, y: px[x, y] > 110
cols = range(left + 3, right - 2)
rows = [y for y in range(top + 3, bottom - 2) if any(text(x, y) for x in cols)]
runs, start, prev = [], None, None
for y in rows:
    if start is None:
        start = y
    elif y != prev + 1:
        runs.append((start, prev)); start = y
    prev = y
runs.append((start, prev))
def baseline(run):
    counts = [(y, sum(1 for x in cols if text(x, y))) for y in range(run[0], run[1] + 1)]
    peak = max(c for _, c in counts)
    return max(y for y, c in counts if c >= 0.25 * peak)
bases = [baseline(r) for r in runs]
ink_left = min(x for x in cols if any(text(x, y) for y in range(runs[0][0], runs[-1][1] + 1)))
# em from the title's first capital (M): Inter's cap height is 0.7275 em.
m_rows = [y for y in range(runs[0][0], runs[0][1] + 1) if any(text(x, y) for x in range(ink_left, ink_left + 6))]
em = (m_rows[-1] - m_rows[0] + 1) / 0.7275
# The corner: the border's outermost pixel per row and per column near the
# top-left, fitted with a circle tangent to both edges.
pts = []
for y in range(top, top + int(2 * em)):
    xs = [x for x in range(left, left + int(2 * em)) if 28 <= px[x, y] <= 70]
    if xs:
        pts.append((xs[0], y))
for x in range(left, left + int(2 * em)):
    ys = [y for y in range(top, top + int(2 * em)) if 28 <= px[x, y] <= 70]
    if ys:
        pts.append((x, ys[0]))
def rms(r):
    cx, cy = left + r, top + r
    d = [math.hypot(x - cx, y - cy) - r for x, y in pts if x < cx and y < cy]
    return math.sqrt(sum(v * v for v in d) / len(d)) if d else 99
radius = min((r / 4 for r in range(8, int(8 * em))), key=rms)
print(json.dumps({
    "em": round(em, 2), "lines": len(runs),
    "width": round((right - left + 1) / em, 3),
    "left": round((ink_left - left) / em, 3),
    "top": round((runs[0][0] - top) / em, 3),
    "pitch": [round((b - a) / em, 3) for a, b in zip(bases, bases[1:])],
    "bottom": round((bottom - bases[-1]) / em, 3),
    "radius": round(radius / em, 3),
    "gap": round((top - bar) / bar, 3),
    "right": right - glyph_end,
}))
EOF
)
}
near() { python3 -c 'import sys; v, want, tol = map(float, sys.argv[1:]); sys.exit(abs(v - want) > tol)' "$1" "$2" "$3"; }
layout_is() { near "$(jq -r "$1" <<<"$layout")" "$2" "$3"; }
insets_are_one_em() { layout_is .left 1.0 0.1 && layout_is .top 1.0 0.1; }
pitches_are() { local p; for p in $(jq -r '.pitch[]' <<<"$layout"); do near "$p" "$1" "$2" || return 1; done; }

if (( ! PIL )); then
    skip "toast layout: python3-pillow is not installed"
else
    input move 2000 600 sleep 200
    benv notify-send -a e2e "Managed Update" "An update to System 14.1 has been scheduled for 11/3/23, 5:00 PM."
    sleep 1.2
    if toast_layout; then
        echo "e2e: toast layout in em: $layout"
        check "a toast is 25.56 em wide, as the model" layout_is .width 25.56 0.3
        check "its ink stands 1 em in from the left and under the top" insets_are_one_em
        check "its baselines are 1.185 em apart" pitches_are 1.185 0.05
        check "its last baseline stands 1.148 em over the bottom" layout_is .bottom 1.148 0.1
        check "its corners are rounded as the model's (1.19 em)" layout_is .radius 1.19 0.1
        check "it hangs 0.458 bar heights under the bar" layout_is .gap 0.458 0.05
        check "its right edge is under the bar's last glyph" layout_is .right 0 3
        # The history draws it as the same card, in one panel whose right
        # edge is the toast's (the user's calls, 2026-10-25): under the
        # count, the newest entry's card is the toast's, pixel for pixel.
        # Borders are found by their runs down the screen: the panel's two,
        # then the cards' two inside, each card's broken at its corners.
        n dispatch 'hl.dsp.global("quickshell:notifications")' >/dev/null
        sleep 1
        shot -g "0,0 2560x400" "$WORK/centre.png" 2>/dev/null
        input key 1 sleep 300
        same=$(python3 - "$WORK/toast.png" "$WORK/centre.png" <<'EOF'
import sys
from PIL import Image, ImageChops
def read(path):
    im = Image.open(path).convert("L")
    px = im.load()
    W, H = im.size
    rgb = Image.open(path).convert("RGB").load()
    rows = [y for y in range(0, 80) if max(abs(a - b) for a, b in zip(rgb[1300, y], (15, 17, 27))) <= 3]
    bar = rows[-1] + 1
    border = lambda x, y: 28 <= px[x, y] <= 70
    # Columns a border runs straight down for 18 px or more (no glyph's
    # edge does), grouped where they touch.
    def longest(x):
        best = run = 0
        for y in range(bar + 2, H):
            run = run + 1 if border(x, y) else 0
            best = max(best, run)
        return best
    cols = [x for x in range(1400, W) if longest(x) >= 18]
    groups = []
    for x in cols:
        if groups and x - groups[-1][-1] <= 2:
            groups[-1].append(x)
        else:
            groups.append([x])
    def runs(x):
        out, start = [], None
        for y in range(bar + 2, H):
            if border(x, y) and start is None:
                start = y
            elif not border(x, y) and start is not None:
                out.append((start, y - 1)); start = None
        return [r for r in out if r[1] - r[0] >= 17]
    return im, groups, runs
toast, tg, truns = read(sys.argv[1])
centre, cg, cruns = read(sys.argv[2])
if len(tg) != 2 or len(cg) != 4:
    print("borders", len(tg), len(cg)); sys.exit()
tl, tr = tg[0][0], tg[1][-1]
cl, cr = cg[1][0], cg[2][-1]
if cg[3][-1] != tr:
    print("panel edge", cg[3][-1], "toast edge", tr); sys.exit()
(t0, t1), (c0, c1) = truns(tl)[0], cruns(cl)[0]
a = toast.crop((tl, t0, tr + 1, t1 + 1)); b = centre.crop((cl, c0, cr + 1, c1 + 1))
worst = max(ImageChops.difference(a, b).getdata()) if a.size == b.size else 255
print("same" if worst <= 8 else f"differ {a.size} {b.size} {worst}")
EOF
)
        check "the history draws it as the same card, in a panel at the toasts' edge" test "$same" = same
        [[ "$same" == same ]] || echo "e2e: toast against history: $same"
    else
        fail "the toast's layout: no toast found under the bar"
    fi
fi

# 25. The island, a black pill in the bar's middle (Theme.islandColor) with
# its cover and a line of text: there while a player has a track, paused too
# until the player closes (the user, 2026-10-26), gone when Super+M switches
# it off (kept in the bar's state). A hover grows the pill itself into the
# player, black from the screen's edge over the desktop's grey (#111111),
# nothing of it left in the bar, which runs on beside it; the card
# stays while its play-pause pauses and goes when the pointer leaves or the
# switch turns it off. Then what plays as wide as it needs and no wider than
# the music island's most (half the bar's idle width), an event as wide as it
# holds, over what plays as alone, and a call and OBS as parts of their own,
# from the probe. Its pixels are read between the groups, 820 to 1720, down
# the bar or the rows asked for.
# mprisapp.py plays on the suite's bus; its cover is a magenta square.
mark=$(output_mark)
island_pixels() {
    shot -g "820,0 900x${1:-34}" "$WORK/island.png" 2>/dev/null || return 1
    python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.tobytes())
rgb = [px[i:i + 3] for i in range(0, len(px), 3)]
ink = sum(1 for r, g, b in rgb if r > 150 and g > 150 and b > 100)
cover = sum(1 for r, g, b in rgb if r > 180 and g < 90 and b > 110)
pill = sum(1 for r, g, b in rgb if r < 6 and g < 6 and b < 6)
print(ink, cover, pill)' "$WORK/island.png"
}
island_shows() { local t c p; read -r t c p < <(island_pixels) && (( t > 100 && c > 40 && p > 2000 )); }
island_gone() { local t c p; read -r t c p < <(island_pixels) && (( t < 5 && c < 5 && p < 5 )); }
# The bar's last row in its own colour (Theme.bg, #0f111b; no edge line
# since 2026-10-27): under the island's middle, and beside it to the left.
bar_row_pixels() {
    shot -g "0,36 2560x1" "$WORK/row.png" 2>/dev/null || return 1
    python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.tobytes())
rgb = [px[i:i + 3] for i in range(0, len(px), 3)]
bar = [abs(r - 15) <= 3 and abs(g - 17) <= 3 and abs(b - 27) <= 3 for r, g, b in rgb]
print(sum(bar[1000:1560]), sum(bar[200:900]))' "$WORK/row.png"
}
# Under the bar, once the island has grown: its black over the desktop,
# and the cover on it.
card_pixels() {
    shot -g "880,38 800x240" "$WORK/card.png" 2>/dev/null || return 1
    python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.tobytes())
rgb = [px[i:i + 3] for i in range(0, len(px), 3)]
black = sum(1 for r, g, b in rgb if r < 6 and g < 6 and b < 6)
cover = sum(1 for r, g, b in rgb if r > 180 and g < 90 and b > 110)
print(black, cover)' "$WORK/card.png"
}
card_open() { local b c; read -r b c < <(card_pixels) && (( b > 20000 )); }
card_closed() { local b c; read -r b c < <(card_pixels) && (( b < 500 )); }
all_gone() { island_gone && card_closed; }
player() { benv dbus-send --session --print-reply --dest=org.mpris.MediaPlayer2.e2e /org/mpris/MediaPlayer2 \
    "org.mpris.MediaPlayer2.Player.$1" >/dev/null 2>&1; }
island_switch() { n dispatch 'hl.dsp.global("quickshell:island")' >/dev/null; }

if (( ! PIL )); then
    skip "island: python3-pillow is not installed"
else
    python3 -c 'import sys; from PIL import Image; Image.new("RGB", (64, 64), (230, 30, 160)).save(sys.argv[1])' "$WORK/cover.png"
    input move 2000 600 sleep 100
    check "no island while nothing plays" island_gone
    benv python3 -I "$REPO/tests/e2e/mprisapp.py" "$WORK/mpris.log" "$WORK/cover.png" &
    MPRIS_PID=$!
    check "the island shows, with the cover, while something plays" wait_for 8 island_shows
    player Pause
    sleep 2
    check "paused, the island stays while the player is open" island_shows
    player Play
    check "and plays on" wait_for 5 island_shows
    island_switch
    check "Super+M takes it away while it plays" wait_for 3 island_gone
    check "and the bar keeps the switch off" wait_for 3 file_is "$WORK/state/quickshell/bar/island" off
    island_switch
    check "Super+M brings it back" wait_for 3 island_shows
    input move 2000 600 sleep 300 move 1280 16 sleep 900
    read -r below cover < <(card_pixels)
    echo "e2e: the grown island: ${below:-?} of its black under the bar, ${cover:-?} of the cover"
    check "hovering the island grows it into the player under the bar" \
        test "${below:-0}" -gt 20000 -a "${cover:-0}" -gt 1500
    # Above the grown card, whose padding (20 px) starts at the screen's edge:
    # the rows the pill's cover and title cross, its own cover and title not.
    read -r ink small pill < <(island_pixels 20)
    echo "e2e: the bar's middle meanwhile: ink ${ink:-?}, cover ${small:-?}, black ${pill:-?}"
    check "and the pill in the bar has given way to it: none of its cover or text is left there" \
        test "${small:-999}" -lt 5 -a "${ink:-999}" -lt 5 -a "${pill:-0}" -gt 2000
    read -r joint beside < <(bar_row_pixels)
    echo "e2e: the bar's last row: ${joint:-?} of it under the island's middle, ${beside:-?} beside"
    check "the grown island lies over the bar's middle, the bar running on beside it" \
        test "${joint:-999}" -lt 10 -a "${beside:-0}" -gt 600
    # Its play-pause, the disc in the middle of the transport row: the card's
    # padding from the screen's edge (20), the cover's row (58), the gap
    # (16), half the disc (20). The log is emptied first: the Pause asked
    # above passed this check once while the click had reached nothing.
    : > "$WORK/mpris.log"
    input move 1280 114 sleep 300 click sleep 300
    check "its play-pause reaches the player" wait_for 3 logged "$WORK/mpris.log" Pause
    check "and the card stays open under the pointer though paused" card_open
    input move 2000 600 sleep 900
    check "paused and left, the card closes and the pill is back" wait_for 3 card_closed
    check "and the pill is back in the bar" wait_for 3 island_shows
    island_shows || echo "e2e: paused and left: island $(island_pixels), card $(card_pixels)"
    read -r joint beside < <(bar_row_pixels)
    check "and the bar is whole again where the island hung" test "${joint:-0}" -gt 500
    player Play
    wait_for 5 island_shows
    input move 1280 16 sleep 900
    island_switch
    check "Super+M takes the island and its card away under the pointer" wait_for 3 all_gone
    input move 2000 600 sleep 300
    island_switch
    check "and brings the island back once the pointer has gone" wait_for 3 island_shows
    check "the card not opened again by a hover it never saw end" card_closed
    stop_tree "$MPRIS_PID"
    wait "$MPRIS_PID" 2>/dev/null
    MPRIS_PID=""
    check "the island goes with the player" wait_for 5 island_gone

    island_width() { ipc e2e island | jq -r '.["HEADLESS-2"].width'; }
    island_widest() { ipc e2e island | jq -r '.["HEADLESS-2"].widest'; }
    island_has() { [[ "$(ipc e2e island | jq -r --arg k "$1" '.["HEADLESS-2"][$k]')" == true ]]; }
    island_lacks() { ! island_has "$1"; }
    # The island's green and red (Theme.islandGreen, islandRed) in the
    # bar's middle: a call's time, a recording's dot and time.
    tone_pixels() {
        shot -g "820,0 900x34" "$WORK/tones.png" 2>/dev/null || return 1
        python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.tobytes())
rgb = [px[i:i + 3] for i in range(0, len(px), 3)]
green = sum(1 for r, g, b in rgb if g > 150 and r < 110 and b < 130 and g - r > 70)
red = sum(1 for r, g, b in rgb if r > 200 and g < 90 and b < 90)
print(green, red)' "$WORK/tones.png"
    }
    benv python3 -I "$REPO/tests/e2e/mprisapp.py" "$WORK/mpris.log" "$WORK/cover.png" &
    MPRIS_PID=$!
    wait_for 8 island_shows
    sleep 0.8
    plays=$(island_width)
    widest=$(island_widest)
    echo "e2e: the island ${plays:-?} wide with what plays, ${widest:-?} at most"
    check "what plays is no wider than the island's most" test -n "$plays" -a "${plays:-1}" -le "${widest:-0}"
    ipc e2e islandReadout Volume 40 0.4 >/dev/null
    wait_for 3 island_has event
    sleep 0.8
    over=$(island_width)
    echo "e2e: the island ${plays:-?} wide with what plays, ${over:-?} with the volume over it"
    stop_tree "$MPRIS_PID"
    wait "$MPRIS_PID" 2>/dev/null
    MPRIS_PID=""
    wait_for 8 island_gone
    # An event is as wide as it holds, alone as over what plays (the volume
    # readout again, so the two hold the same).
    ipc e2e islandReadout Volume 40 0.4 >/dev/null
    wait_for 3 island_has event
    sleep 0.8
    alone=$(island_width)
    echo "e2e: an event alone ${alone:-?} wide"
    check "an event is as wide as it holds, over what plays as alone" \
        test -n "$over" -a "${alone:-0}" = "${over:-1}" -a "${alone:-999}" -lt "$(ipc e2e island | jq -r '.["HEADLESS-2"].widest')"
    wait_for 6 island_gone
    ipc e2e callsFake '{"binary":"e2e-caller","name":"Caller VoiceEngine"}' >/dev/null
    check "a call shows as a part of its own" wait_for 3 island_has call
    sleep 0.8
    read -r green red < <(tone_pixels)
    check "with its time in the island's green" test "${green:-0}" -gt 20
    input move 1280 16 sleep 900
    read -r below cover < <(card_pixels)
    check "hovering a call grows the island into its row" test "${below:-0}" -gt 20000
    input move 2000 600 sleep 900
    ipc e2e callsFake '{"binary":"e2e-recorder","name":"Recorder"}' >/dev/null
    check "a recorder on the microphone is no call" wait_for 3 island_lacks call
    ipc e2e callsFake none >/dev/null
    ipc e2e obsFeed '{"op":2,"d":{"negotiatedRpcVersion":1}}' >/dev/null
    ipc e2e obsFeed '{"op":7,"d":{"requestId":"record","requestStatus":{"result":true,"code":100},"responseData":{"outputActive":true,"outputPaused":false,"outputDuration":61000}}}' >/dev/null
    check "OBS recording shows as a part of its own" wait_for 3 island_has obs
    sleep 0.8
    read -r green red < <(tone_pixels)
    check "with its dot and its time in the island's red" test "${red:-0}" -gt 20
    ipc e2e obsFeed '{"op":5,"d":{"eventType":"RecordStateChanged","eventData":{"outputActive":false,"outputState":"OBS_WEBSOCKET_OUTPUT_STOPPED"}}}' >/dev/null
    check "and goes when it stops" wait_for 3 island_lacks obs
    check "the island goes with the last thing on it" wait_for 5 island_gone
    check "the island's files raised no QML warning" \
        quiet_since "$mark" '[@/](MediaChip|MediaPopup|MediaPlayer|IslandShape|IslandPart|IslandEvent|IslandActivities|IslandButton|Visualizer|Media|Island|Calls|Obs|ObsSocket)\.qml'
fi

# 26. A screen share on the island (services/ScreenShare.qml): wf-recorder
# copies a corner of the screen through the compositor, as the portal does
# for a call, and the island shows the red dot, the sharer's green icon
# (pw-dump's stand-in), what is shared and for how long. Switched off with
# Super+M it shows no share either (the user, 2026-10-26: all or nothing).
# What plays opens beside the share and stays when it ends; a screenshot
# (grim) shows nothing. Pixels are read as in scenario 25.
mark=$(output_mark)
share_pixels() {
    shot -g "820,0 900x34" "$WORK/share.png" 2>/dev/null || return 1
    python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB"); px = list(im.tobytes())
rgb = [px[i:i + 3] for i in range(0, len(px), 3)]
red = sum(1 for r, g, b in rgb if r > 220 and g < 90 and b < 90)
icon = sum(1 for r, g, b in rgb if r < 70 and g > 180 and b < 130)
ink = sum(1 for r, g, b in rgb if r > 150 and g > 150 and b > 100)
cover = sum(1 for r, g, b in rgb if r > 180 and g < 90 and b > 110)
print(red, icon, ink, cover)' "$WORK/share.png"
}
share_shows() { local r i t c; read -r r i t c < <(share_pixels) && (( r > 20 && i > 150 && t > 100 )); }
both_show() { local r i t c; read -r r i t c < <(share_pixels) && (( r > 20 && i > 150 && c > 40 )); }
music_only() { local r i t c; read -r r i t c < <(share_pixels) && (( r < 5 && i < 5 && c > 40 )); }

if (( ! PIL )); then
    skip "share: python3-pillow is not installed"
elif ! command -v wf-recorder >/dev/null 2>&1; then
    skip "share: wf-recorder is not installed"
else
    input move 2000 600 sleep 100
    shot -g "0,0 64x64" "$WORK/one.png"
    sleep 2.5
    check "a screenshot's copy puts nothing on the island" island_gone
    island_switch
    check "the island switched off, with nothing playing" wait_for 3 file_is "$WORK/state/quickshell/bar/island" off
    benv wf-recorder -y -D --no-dmabuf -g "100,100 64x64" -c rawvideo -m null -f /dev/null >"$WORK/wf.out" 2>&1 &
    REC_PID=$!
    sleep 3
    check "switched off, the island shows no share either" island_gone
    island_switch
    check "switched on, a share that lasts shows: the dot, who shares, what and how long" \
        wait_for 8 share_shows
    share_shows || echo "e2e: share pixels $(share_pixels); wf-recorder: $(tail -3 "$WORK/wf.out" | tr '\n' ' ')"
    benv python3 -I "$REPO/tests/e2e/mprisapp.py" "$WORK/mpris.log" "$WORK/cover.png" &
    MPRIS_PID=$!
    check "switched on, what plays opens beside the share" wait_for 8 both_show
    both_show || echo "e2e: share and player pixels $(share_pixels)"
    # Both parts side by side, for a look with E2E_KEEP=1.
    cp "$WORK/share.png" "$WORK/share-and-player.png"
    stop_tree "$REC_PID"
    wait "$REC_PID" 2>/dev/null
    REC_PID=""
    check "the share leaves with the recorder, what plays stays" wait_for 5 music_only
    stop_tree "$MPRIS_PID"
    wait "$MPRIS_PID" 2>/dev/null
    MPRIS_PID=""
    check "and the island goes with the player" wait_for 5 island_gone
    check "the share's files raised no QML warning" \
        quiet_since "$mark" '[@/](ScreenShare|MediaChip)\.qml'
fi

# 27. The unlock's sweep (modules/UnlockSweep.qml): told of a lock the
# compositor confirms, each screen keeps a capture in an overlay the lock
# hides, and at the unlock draws it up off the screen and lets it go. The
# compositor's answer to `hyprctl locked` is a stand-in on the bar's PATH:
# nothing unlocks a real lock here without a password (scenario 28 locks for
# real, last).
mark=$(output_mark)
real_hyprctl=$(command -v hyprctl)
cat > "$WORK/bin/hyprctl" <<EOF
#!/bin/sh
if [ "\$1" = locked ] && [ -f "$WORK/fake-locked" ]; then cat "$WORK/fake-locked"; exit 0; fi
exec "$real_hyprctl" "\$@"
EOF
chmod +x "$WORK/bin/hyprctl"
echo true > "$WORK/fake-locked"
ipc keys lock >/dev/null
check "a confirmed lock leaves a sheet on each screen, under the lock" \
    wait_for 5 has_layer quickshell:unlock HEADLESS-2
sleep 1.5
echo false > "$WORK/fake-locked"
ipc keys unlock >/dev/null
check "at the unlock the sheet is drawn up and goes" wait_for 3 lacks_layer quickshell:unlock
check "the sweep raised no QML warning" quiet_since "$mark" '[@/]UnlockSweep\.qml'
rm -f "$WORK/bin/hyprctl" "$WORK/fake-locked"

# 28. The lock screen as the user's design has it (hyprlock.conf,
# scripts/lock-media.py, scripts/lock-colours.py), on the nested compositor
# only and last, since a lock that is killed rather than unlocked leaves that
# compositor locked. Over a wallpaper light down to the field and dark under
# it: the island at the top with its lock, the clock in a dark, the playing
# track's card (the bar's grown island at 1.6 times) with its cover and its
# play-pause disc in that dark, "Press to unlock" in the bar's beige, and a
# click on the disc reaching the player, the card then drawing play. The
# card and the covers go to the run's own directory, not the session's.
# Positions are HEADLESS-2's at the panel's proportions (lock-fit.sh): 0.683
# times the design's heights, 0.759 its widths, but the card's and its
# controls' 0.683 too (fit: even).
lock_pixels() {
    shot -o HEADLESS-2 "$WORK/lock.png" 2>/dev/null || return 1
    python3 - "$WORK/lock.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
def pixels(box):
    data = im.crop(box).tobytes()
    return [data[i:i + 3] for i in range(0, len(data), 3)]
def count(box, test):
    return sum(1 for c in pixels(box) if test(c))
# The island in the bar's colour, its lock in the bar's beige.
beige = lambda c: c[0] > 200 and c[1] > 200 and 150 < c[2] < 215
island = count((1180, 8, 1380, 58), lambda c: abs(c[0] - 15) <= 3 and abs(c[1] - 17) <= 3 and abs(c[2] - 27) <= 3)
lock = count((1190, 18, 1225, 48), beige)
clock_box = (1110, 505, 1450, 572)
clock = count(clock_box, lambda c: max(c) < 120)
# The cover scenario 25 made: magenta, as the island's check reads it.
cover = count((1009, 705, 1057, 752), lambda c: c[0] > 180 and c[1] < 90 and c[2] > 110)
unlock = count((1130, 890, 1430, 935), beige)
# The play-pause disc in the clock's dark, not washed by the card's pane.
ink = min(pixels(clock_box), key=sum)
toggle = min(pixels((1260, 772, 1300, 812)), key=sum)
print(island, lock, clock, cover, unlock, max(abs(a - b) for a, b in zip(ink, toggle)))
EOF
}
lock_shows() {
    local b l c v u o
    read -r b l c v u o < <(lock_pixels) && (( b > 6000 && l > 40 && c > 5000 && v > 1500 && u > 400 && o < 40 ))
}
# The card drawn for the paused player: its state names the status.
paused_card() { grep -qs $'\tPaused\t' "$WORK"/lockrun/card-????????; }

if (( ! PIL )); then
    skip "lock screen: python3-pillow is not installed"
elif [[ -z "$WL" || "$WL" == "$WAYLAND_DISPLAY" || ! -S "$RT/$WL" ]]; then
    fail "lock screen: refusing to lock anything but the nested compositor"
else
    benv python3 -I "$REPO/tests/e2e/mprisapp.py" "$WORK/mpris.log" "$WORK/cover.png" &
    MPRIS_PID=$!
    python3 -c 'import sys
from PIL import Image
im = Image.new("RGB", (2560, 1440), (220, 216, 208))
im.paste((24, 26, 32), (0, 868, 2560, 1440))
im.save(sys.argv[1])' "$WORK/wall.png"
    sleep 1
    lockconf="$WORK/config/hypr/hyprlock.conf"
    sed -i "s#^\$media = .*#\$media = python3 $WORK/config/hypr/scripts/lock-media.py#; s#~/.config/hypr/lock-blank.png#$WORK/config/hypr/lock-blank.png#; s#~/Pictures/Wallpapers/current.png#$WORK/wall.png#" "$lockconf"
    if fitted=$(HYPRLAND_INSTANCE_SIGNATURE="$SIG" "$WORK/config/hypr/scripts/lock-fit.sh" "$lockconf" "$WORK/hyprlock-fit.conf"); then
        WAYLAND_DISPLAY="$WL" HYPRLAND_INSTANCE_SIGNATURE="$SIG" DBUS_SESSION_BUS_ADDRESS="$BUS" \
            LOCK_MEDIA_RUN="$WORK/lockrun" LOCK_WEATHER="$WORK/bar/scripts/weather.sh" \
            hyprlock -c "$fitted" >"$WORK/hyprlock.out" 2>&1 &
        LOCK_PID=$!
        check "the lock shows its island and lock, a dark clock, the card with its dark disc and a beige Press to unlock" \
            wait_for 10 lock_shows
        read -r b l c v u o < <(lock_pixels)
        echo "e2e: lock pixels: island ${b:-?}, lock ${l:-?}, clock ${c:-?}, cover ${v:-?}, unlock ${u:-?}, toggle off the clock's ink by ${o:-?}"
        : > "$WORK/mpris.log"
        input move 1280 792 sleep 300 click sleep 300
        check "a click on the lock's play-pause reaches the player" wait_for 4 logged "$WORK/mpris.log" Pause
        check "and the card draws play, in the run's own directory" wait_for 4 paused_card
        check "hyprlock raised no error" bash -c "! grep -E 'ERR' '$WORK/hyprlock.out'"
        kill -KILL "$LOCK_PID" 2>/dev/null
        LOCK_PID=""
    else
        fail "lock screen: lock-fit.sh wrote no configuration"
    fi
    stop_tree "$MPRIS_PID"
    MPRIS_PID=""
fi

check "no session action or hardware write was even attempted" no_writes

if (( failed == 0 )); then
    echo "PASS  e2e: $passed checks"
    exit 0
fi
echo "FAIL  e2e: $failed of $((passed + failed)) checks failed"
exit 1
