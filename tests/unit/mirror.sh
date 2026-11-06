#!/usr/bin/env bash
# Runs quickshell/bar/scripts/mirror.sh against a stand-in /sys/bus/usb/devices and
# stand-ins for systemctl, systemd-run, journalctl, scrcpy and adb: no device, no
# unit and no adb of the machine's are touched. Tells no tablet, a tablet with USB
# debugging off and one with it on; reports a failed mirror in scrcpy's words; starts
# scrcpy with the words it was given in a named unit, not twice; and stops that unit.
# The stand-ins expand their own variables.
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-desktop-mirror.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0 failed=0
ok() {
    if [[ "$2" == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        printf 'FAIL  mirror: %s: wanted [%s], got [%s]\n' "$1" "$3" "$2"
    fi
}

mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/scrcpy"
printf '#!/bin/sh\nexit 1\n' >"$WORK/bin/pgrep"
# adb's answers from a file of the test's, what it is asked in the calls.
cat >"$WORK/bin/adb" <<EOF
#!/bin/sh
echo "adb \$*" >>"$WORK/calls"
case "\$*" in
    "devices -l") printf 'List of devices attached\n'; cat "$WORK/adb-devices" 2>/dev/null ;;
    devices) printf 'List of devices attached\n'; cat "$WORK/adb-devices" 2>/dev/null ;;
    *"shell ip -4"*) cat >/dev/null; echo '38: wlan0    inet 10.0.0.7/24 brd 10.0.0.255 scope global wlan0' ;;
    "connect "*) echo "connected to \$2" ;;
esac
EOF
cat >"$WORK/bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >>"$WORK/calls"
case "\$*" in
    *is-active*) [ -e "$WORK/active" ] ;;
    *is-failed*) [ -e "$WORK/failed" ] ;;
    *) exit 0 ;;
esac
EOF
cat >"$WORK/bin/systemd-run" <<EOF
#!/bin/sh
echo "systemd-run \$*" >>"$WORK/calls"
EOF
cat >"$WORK/bin/journalctl" <<EOF
#!/bin/sh
printf 'INFO: something\nERROR: Device is unauthorized\n'
EOF
chmod +x "$WORK"/bin/*
export PATH="$WORK/bin:$PATH" MIRROR_USB_DIR="$WORK/usb"

device() { # name vendor maker product
    mkdir -p "$WORK/usb/$1"
    echo "$2" >"$WORK/usb/$1/idVendor"
    echo "$3" >"$WORK/usb/$1/manufacturer"
    echo "$4" >"$WORK/usb/$1/product"
}
iface() { # name class subclass protocol
    mkdir -p "$WORK/usb/$1"
    echo "$2" >"$WORK/usb/$1/bInterfaceClass"
    echo "$3" >"$WORK/usb/$1/bInterfaceSubClass"
    echo "$4" >"$WORK/usb/$1/bInterfaceProtocol"
}
script="$REPO/quickshell/bar/scripts/mirror.sh"
field() { "$script" status | jq -r ".$1"; }

mkdir -p "$WORK/usb"
ok "nothing plugged in" "$(field usb)" none

# A receiver and a webcam are no tablet.
device 3-1 046d Logitech "USB Receiver"
iface 3-1:1.0 03 01 01
device 3-5 3277 Shinetech "ASUS FHD webcam"
iface 3-5:1.0 0e 01 00
ok "other devices are no tablet" "$(field usb)" none

device 3-4 04e8 SAMSUNG SAMSUNG_Android
iface 3-4:1.0 06 01 01
iface 3-4:1.1 02 02 01
ok "a tablet with debugging off is told apart" "$(field usb)" off
ok "and named, its maker once" "$(field name)" "SAMSUNG Android"

iface 3-4:1.3 ff 42 01
ok "debugging on shows as the adb interface" "$(field usb)" on
ok "the mirror is not running yet" "$(field running)" false

rm -rf "$WORK/usb/3-4:1.0" "$WORK/usb/3-4:1.1"
ok "the adb interface alone is enough" "$(field usb)" on
iface 3-4:1.0 06 01 01

touch "$WORK/failed"
ok "a failed mirror says why, in scrcpy's words" "$(field error)" "Device is unauthorized"
rm "$WORK/failed"
ok "and nothing else does" "$(field error)" ""

: >"$WORK/calls"
"$script" start --no-control --max-size=1920
line=$(grep '^systemd-run' "$WORK/calls")
case "$line" in
    *"--unit=tablet-mirror.service"*"-- scrcpy --no-control --max-size=1920") ok "start runs scrcpy with its words in the named unit" yes yes ;;
    *) ok "start runs scrcpy with its words in the named unit" "$line" "a unit and the words" ;;
esac
case "$line" in
    *"SDL_VIDEODRIVER=wayland"*) ok "on Wayland" yes yes ;;
    *) ok "on Wayland" "$line" SDL_VIDEODRIVER=wayland ;;
esac
case "$line" in
    *"StandardOutput=null"*) ok "its output, with the serial, kept out of the journal" yes yes ;;
    *) ok "its output, with the serial, kept out of the journal" "$line" StandardOutput=null ;;
esac

touch "$WORK/active"
ok "a running mirror shows" "$(field running)" true
: >"$WORK/calls"
"$script" start --no-control
ok "and is not started twice" "$(grep -c '^systemd-run' "$WORK/calls")" 0

: >"$WORK/calls"
"$script" stop
ok "stop ends that unit" "$(grep -c 'stop tablet-mirror.service' "$WORK/calls")" 1
ok "and asks to end nothing else" "$(grep -c -E 'kill|pkill' "$WORK/calls")" 0

# ---- what can be reached ----
export XDG_RUNTIME_DIR="$WORK"
rows() { "$script" devices "$@" | jq -r '.devices | map(.id + "=" + .state) | join(" ")'; }
rm -f "$WORK/active"
rm -rf "$WORK/usb/3-4:1.3"
ok "debugging off is a row that says so" "$(rows)" "usb=debugging"
iface 3-4:1.3 ff 42 01
printf 'R5SERIAL0  unauthorized usb:3-4 transport_id:1\n' >"$WORK/adb-devices"
ok "a tablet not yet allowed" "$(rows)" "usb=unauthorized"
printf 'R5SERIAL0  device usb:3-4 product:p model:SM_X620 device:d transport_id:1\n' >"$WORK/adb-devices"
ok "one on USB, and its Wi-Fi offered through it" "$(rows)" "usb=ready wifi:10.0.0.7:5555=offered"
ok "its model, in words" "$("$script" devices | jq -r '.devices[0].name')" "SM X620"
case "$("$script" devices)" in
    *R5SERIAL0*) ok "the USB serial stays out of the rows" leaked "" ;;
    *) ok "the USB serial stays out of the rows" "" "" ;;
esac
printf 'R5SERIAL0  device usb:3-4 model:SM_X620 transport_id:1\n10.0.0.7:5555  device model:SM_X620 transport_id:2\n' >"$WORK/adb-devices"
ok "a tablet already on Wi-Fi is not offered again" "$(rows)" "usb=ready wifi:10.0.0.7:5555=ready"
printf 'R5SERIAL0  device usb:3-4 model:SM_X620 transport_id:1\n10.0.0.7:5555  offline transport_id:2\n' >"$WORK/adb-devices"
ok "one gone offline is offered, not lost" "$(rows)" "usb=ready wifi:10.0.0.7:5555=offered"
rm -rf "$WORK/usb/3-4" "$WORK"/usb/3-4:*
printf '' >"$WORK/adb-devices"
: >"$WORK/calls"
ok "nothing plugged in and nothing known: no rows" "$(rows)" ""
ok "and no adb is started for it" "$(grep -c '^adb' "$WORK/calls")" 0
printf '10.0.0.7:5555  device model:SM_X620 transport_id:2\n' >"$WORK/adb-devices"
ok "a kept address is tried without USB" "$(rows 10.0.0.7:5555)" "wifi:10.0.0.7:5555=ready"
ok "by connecting to it" "$(grep -c 'adb connect 10.0.0.7:5555' "$WORK/calls")" 1

: >"$WORK/calls"
"$script" start-wifi 10.0.0.7:5555 --no-control
case "$(grep '^systemd-run' "$WORK/calls")" in
    *"-- scrcpy --serial=10.0.0.7:5555 --no-control") ok "start-wifi names the address to scrcpy" yes yes ;;
    *) ok "start-wifi names the address to scrcpy" "$(cat "$WORK/calls")" "--serial" ;;
esac
rm -f "$WORK/tablet-mirror-adb"
"$script" start-wifi 10.0.0.7:5555 --no-control
ok "and marks a server it starts as its own to end" "$([[ -e "$WORK/tablet-mirror-adb" ]] && echo yes)" yes
: >"$WORK/calls"
"$script" forget 10.0.0.7:5555
ok "forget closes the port" "$(grep -c 'adb -s 10.0.0.7:5555 usb' "$WORK/calls")" 1
: >"$WORK/calls"
touch "$WORK/tablet-mirror-adb"
"$script" release
ok "release ends the server this started" "$(grep -c 'adb kill-server' "$WORK/calls")" 1
: >"$WORK/calls"
"$script" release
ok "and only that one" "$(grep -c 'adb kill-server' "$WORK/calls")" 0

# Its own directory alone on the path, for this machine has the real one.
rm "$WORK/bin/scrcpy"
PATH="$WORK/bin" /usr/bin/bash "$script" start --no-control 2>/dev/null
ok "without scrcpy it says so by its status" "$?" 3
"$script" nonsense 2>/dev/null
ok "an unknown word is refused" "$?" 2

if (( failed )); then
    exit 1
fi
printf 'PASS  mirror: %d checks\n' "$passed"
