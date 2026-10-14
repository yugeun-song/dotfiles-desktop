#!/usr/bin/env bash
# Runs tests/unit/qml/shell.qml against a copy of quickshell/bar, offscreen.
#
# Nothing in the copy may reach the machine: the key reader would ask for a
# password and read the keyboard, app-scope.sh would start programs in the
# user's systemd, and the services call ddcutil (the monitor's i2c bus),
# brightnessctl and hyprctl the moment they exist. Those become stubs on PATH
# or in the copy; the session bus is one that does not exist, so the
# notification server cannot take the running bar's name, and so is the
# system bus, so the network and weather services see no NetworkManager;
# state, config and runtime directories are temporary.
# The runtime directory sits in /tmp, not under a long path: quickshell puts
# its IPC socket there, and a socket path has a 108-byte limit.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
command -v qs >/dev/null 2>&1 || { echo "SKIP  qml: quickshell (qs) is not installed"; exit 0; }

WORK=$(mktemp -d -p /tmp qs-unit.XXXXXX)
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/state/quickshell/bar" "$WORK/config" "$WORK/cache" "$WORK/run"
chmod 700 "$WORK/run"
cp -a "$REPO/quickshell/bar" "$WORK/bar"
cp "$REPO/tests/unit/qml/shell.qml" "$WORK/bar/shell.qml"
cp "$REPO/tests/unit/qml/TestModules.qml" "$WORK/bar/TestModules.qml"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bar/scripts/app-scope.sh"
for tool in ddcutil brightnessctl notify-send canberra-gtk-play fcitx5-remote gdbus; do
    printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done
# cava: a line of levels, then alive until stopped or qs is gone. A stop
# takes 300 ms, as a real cava's can, so the exit arrives after a quick
# resume (testCava).
cat > "$WORK/bin/cava" <<'EOF'
#!/bin/sh
echo "1;2;3"
trap 'sleep 0.3; exit 0' TERM
while kill -0 "$PPID" 2>/dev/null; do sleep 0.05; done
EOF
chmod +x "$WORK/bin/cava"
# The key reader as the bar runs root's (KeyFeed.qml): pkexec runs it, or
# answers as $WORK/keyfeed/mode says, and the reader ignores TERM, since the
# bar cannot signal a process of root's: only the end of its stdin stops it.
mkdir -p "$WORK/keyfeed"
cat > "$WORK/bin/pkexec" <<'EOF'
#!/bin/sh
case "$(cat "$KEYFEED_TEST_DIR/mode" 2>/dev/null)" in
    dismiss) exit 126 ;;
    refuse) echo "Error executing command as another user: Not authorized" >&2; exit 127 ;;
    noagent) echo "Error executing command as another user: No authentication agent found." >&2; exit 127 ;;
esac
exec "$@"
EOF
# The reader logs its start, its arguments, every control line, and its end;
# it sends one key for each resume.
cat > "$WORK/keyfeed/reader" <<'EOF'
#!/bin/sh
trap '' TERM
echo started >> "$KEYFEED_TEST_DIR/log"
echo "$*" > "$KEYFEED_TEST_DIR/args"
echo '{"type": "ready", "devices": 1}'
while IFS= read -r line; do
    echo "$line" >> "$KEYFEED_TEST_DIR/control"
    [ "$line" = stop ] && break
    [ "$line" = resume ] && echo '{"type": "key", "mods": ["Ctrl"], "key": "K"}'
done
echo stopped >> "$KEYFEED_TEST_DIR/log"
EOF
chmod +x "$WORK/bin/pkexec" "$WORK/keyfeed/reader"
# echowatch.py in the copy: "secret" while $WORK/echo/secret exists, else
# "clear", on every change; each "pid" line the bar sends is logged.
mkdir -p "$WORK/echo"
cat > "$WORK/bar/scripts/echowatch.py" <<'EOF'
import os, select, sys
flag, log = os.environ["ECHOWATCH_TEST_FLAG"], os.environ["ECHOWATCH_TEST_LOG"]
said = None
while True:
    if select.select([sys.stdin], [], [], 0.05)[0]:
        line = sys.stdin.readline()
        if not line:
            break
        with open(log, "a") as fh:
            fh.write(line)
        said = None
    word = "secret" if os.path.exists(flag) else "clear"
    if word != said:
        print(word, flush=True)
        said = word
EOF
# hyprctl: `hyprctl locked`, which only the key overlay asks, holds its
# answer until $WORK/lock-go exists, then says false unless
# $WORK/session-locked does; anything else is a no-op.
cat > "$WORK/bin/hyprctl" <<EOF
#!/bin/sh
[ "\$1" = locked ] || exit 0
while [ ! -e "$WORK/lock-go" ] && kill -0 "\$PPID" 2>/dev/null; do sleep 0.05; done
if [ -e "$WORK/session-locked" ]; then echo true; else echo false; fi
EOF
chmod +x "$WORK/bin/hyprctl"
# The camera indicator's sources, driven by the suite through files in
# $WORK/camera: the status reading and its exit code, the device events
# (a line appended is an event), and the switch file. tail follows only
# while qs lives, or an orphan would outlast the run.
mkdir -p "$WORK/camera/state"
printf '{"switch": "off", "busy": false, "cameras": [{"name": "Cam A", "state": "off", "nodes": []}], "power_switches": [], "missing": []}\n' \
    > "$WORK/camera/status.json"
: > "$WORK/camera/events"
cat > "$WORK/bin/camera-switch-stub" <<'EOF'
#!/bin/sh
echo run >> "$CAMERA_TEST_DIR/calls"
code=$(cat "$CAMERA_TEST_DIR/exit" 2>/dev/null || echo 0)
[ "$code" = 0 ] && cat "$CAMERA_TEST_DIR/status.json"
exit "$code"
EOF
cat > "$WORK/bin/udevadm" <<'EOF'
#!/bin/sh
echo "monitor will print the received events for:"
exec tail -n 0 -F --pid="$PPID" "$CAMERA_TEST_DIR/events"
EOF
chmod +x "$WORK/bin/camera-switch-stub" "$WORK/bin/udevadm"
# The weather fetch, in the copy: each run is logged, takes 0.4 s like a
# slow network, and reports live or not as $WORK/weather/live says.
mkdir -p "$WORK/weather"
cat > "$WORK/bar/scripts/weather.sh" <<'EOF'
#!/bin/sh
echo run >> "$WEATHER_TEST_DIR/calls"
sleep 0.4
live=$(cat "$WEATHER_TEST_DIR/live" 2>/dev/null || echo false)
echo "{\"place\": \"Test\", \"fetched\": 1, \"live\": $live, \"code\": 0, \"temp\": 20, \"feels\": 20, \"humidity\": 50, \"wind\": 1, \"day\": 1, \"today\": {\"min\": 10, \"max\": 25}}"
EOF
chmod +x "$WORK/bar/scripts/weather.sh"

# QML_TEST_WAYLAND names a Wayland display to run on instead (tests/e2e
# passes its nested one): the Launcher and Displays suites need one.
platform=offscreen
display=()
if [[ -n "${QML_TEST_WAYLAND:-}" ]]; then
    platform=wayland
    # Absolute: the runtime directory below is not the one the socket is in.
    socket="$QML_TEST_WAYLAND"
    [[ "$socket" == /* ]] || socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$socket"
    [[ -S "$socket" ]] || { echo "FAIL  qml: no Wayland socket at $socket"; exit 1; }
    display=(WAYLAND_DISPLAY="$socket")
fi

out="$WORK/out"
# In a subshell: the shell that waits reports the TERM the test shell sends
# itself, and that report is noise.
( env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY \
    "${display[@]}" \
    PATH="$WORK/bin:$PATH" \
    QT_QPA_PLATFORM="$platform" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$WORK/no-bus" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$WORK/no-system-bus" \
    XDG_RUNTIME_DIR="$WORK/run" \
    XDG_STATE_HOME="$WORK/state" \
    XDG_CONFIG_HOME="$WORK/config" \
    XDG_CACHE_HOME="$WORK/cache" \
    CAMERA_SWITCH_SYSTEM="$WORK/bin/camera-switch-stub" \
    CAMERA_SWITCH_FILE="$WORK/camera/state/off" \
    CAMERA_TEST_DIR="$WORK/camera" \
    WEATHER_TEST_DIR="$WORK/weather" \
    QML_TEST_LOCK_GO="$WORK/lock-go" \
    KEYFEED_SYSTEM="$WORK/keyfeed/reader" \
    KEYFEED_TEST_DIR="$WORK/keyfeed" \
    ECHOWATCH_TEST_FLAG="$WORK/echo/secret" \
    ECHOWATCH_TEST_LOG="$WORK/echo/log" \
    XDG_VTNR=7 \
    timeout 60 qs -n -p "$WORK/bar" >"$out" 2>&1; true ) 2>/dev/null

# The colour codes and log prefixes go; the test lines stay.
results=$(sed -E 's/\x1b\[[0-9;]*m//g' "$out" | grep -o '\[test\] .*')
fails=$(grep '^\[test\] FAIL' <<<"$results")
done_line=$(grep '^\[test\] DONE' <<<"$results")
if [[ -z "$done_line" ]]; then
    echo "FAIL  qml: the test shell never finished; its log:"
    sed -E 's/\x1b\[[0-9;]*m//g' "$out" | tail -20
    exit 1
fi
[[ -n "$fails" ]] && awk '{ sub(/^\[test\] FAIL /, "FAIL  qml: "); print }' <<<"$fails"
grep '^\[test\] SKIP' <<<"$results" | awk '{ sub(/^\[test\] SKIP /, "SKIP  qml: "); print }'
# A QML error in the bar's own files is a failure even if every check passed.
errors=$(sed -E 's/\x1b\[[0-9;]*m//g' "$out" | grep -E 'WARN scene|ERROR' | grep -v -E 'portal|Could not register|Could not find an available backend' || true)
[[ -n "$errors" ]] && { echo "FAIL  qml: warnings from the bar's QML:"; awk '{ print "      " $0 }' <<<"$errors"; }
passed=$(sed -E 's/.*passed=([0-9]+).*/\1/' <<<"$done_line")
failed=$(sed -E 's/.*failed=([0-9]+).*/\1/' <<<"$done_line")
if [[ "$failed" == 0 && -z "$errors" ]]; then
    echo "PASS  qml: $passed checks"
    exit 0
fi
exit 1
