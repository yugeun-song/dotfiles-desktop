#!/usr/bin/env bash
# Runs tests/unit/qml/shell.qml against a copy of quickshell/bar, offscreen.
#
# Nothing in the copy may reach the machine: the key reader would read the
# keyboard, app-scope.sh would start programs in the user's systemd, and the
# services call ddcutil (the monitor's i2c bus), brightnessctl and hyprctl the
# moment they exist. Those become stubs on PATH or in the copy; the session
# bus is one that does not exist, so the notification server cannot take the
# running bar's name; state, config and runtime directories are temporary.
# The runtime directory sits in /tmp, not under a long path: quickshell puts
# its IPC socket there, and a socket path has a 108-byte limit.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
command -v qs >/dev/null 2>&1 || { echo "SKIP  qml: quickshell (qs) is not installed"; exit 0; }

WORK=$(mktemp -d -p /tmp qs-unit.XXXXXX)
trap 'rm -rf -- "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/state" "$WORK/config" "$WORK/cache" "$WORK/run"
chmod 700 "$WORK/run"
cp -a "$REPO/quickshell/bar" "$WORK/bar"
cp "$REPO/tests/unit/qml/shell.qml" "$WORK/bar/shell.qml"
cp "$REPO/tests/unit/qml/TestModules.qml" "$WORK/bar/TestModules.qml"
printf '#!/bin/sh\necho %s\n' "'{\"type\": \"ready\", \"devices\": 0}'; sleep 3600" > "$WORK/bar/scripts/keyfeed.py"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bar/scripts/app-scope.sh"
for tool in ddcutil brightnessctl hyprctl notify-send canberra-gtk-play fcitx5-remote gdbus cava; do
    printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/$tool"
    chmod +x "$WORK/bin/$tool"
done

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
    XDG_RUNTIME_DIR="$WORK/run" \
    XDG_STATE_HOME="$WORK/state" \
    XDG_CONFIG_HOME="$WORK/config" \
    XDG_CACHE_HOME="$WORK/cache" \
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
errors=$(sed -E 's/\x1b\[[0-9;]*m//g' "$out" | grep -E 'WARN scene|ERROR' | grep -v -E 'portal|Could not register' || true)
[[ -n "$errors" ]] && { echo "FAIL  qml: warnings from the bar's QML:"; awk '{ print "      " $0 }' <<<"$errors"; }
passed=$(sed -E 's/.*passed=([0-9]+).*/\1/' <<<"$done_line")
failed=$(sed -E 's/.*failed=([0-9]+).*/\1/' <<<"$done_line")
if [[ "$failed" == 0 && -z "$errors" ]]; then
    echo "PASS  qml: $passed checks"
    exit 0
fi
exit 1
