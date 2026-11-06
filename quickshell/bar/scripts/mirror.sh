#!/usr/bin/env bash
# The tablet mirror behind modules/MirrorPanel.qml: a tablet's screen in a window
# through scrcpy, to write on it and share that window in a call (the user,
# 2026-11-07).
#   mirror.sh status             one line of JSON: usb, name, running, via, error
#   mirror.sh devices [ADDRESS]  one line of JSON: the tablets that can be reached
#   mirror.sh start ARGS         scrcpy ARGS, in a user unit of its own
#   mirror.sh start-wifi ADDRESS ARGS   the same over Wi-Fi, turning it on by USB if need be
#   mirror.sh forget ADDRESS     close the tablet's network port again
#   mirror.sh release            end an adb server that devices started
#   mirror.sh stop
#
# A transient unit and not a child of the bar: installing while a call goes on
# reloads the bar, which would end the mirror on the screen being shared. The unit
# has a name, so stop ends this and nothing else, and its cgroup takes along the adb
# server scrcpy started; one the user already ran is outside it and stays.
set -uo pipefail
shopt -s nullglob

UNIT=tablet-mirror.service
USB=${MIRROR_USB_DIR:-/sys/bus/usb/devices}
# Set while an adb server is this script's to end: asking for devices starts one,
# and one the user was already running is theirs.
SERVER_MARK=${XDG_RUNTIME_DIR:-/tmp}/tablet-mirror-adb

first_line() {
    local line=""
    [[ -r "$1" ]] && IFS= read -r line <"$1"
    printf '%s' "$line"
}

# From sysfs and not from adb, so that asking starts no server, and so that a tablet
# plugged in with debugging off can be told from no tablet: that is the step left to
# do, and adb sees both as nothing. Debugging on shows as the adb interface, class
# ff, subclass 42, protocol 01. With it off a tablet still shows, as a media device
# (class 06, file or image transfer) or by name. usb=on wins over a second device.
usb=none name=""
for dev in "$USB"/*; do
    [[ -r "$dev/idVendor" ]] || continue
    adb=0 media=0
    for iface in "$dev":*; do
        [[ -r "$iface/bInterfaceClass" ]] || continue
        kind=$(first_line "$iface/bInterfaceClass")
        [[ "$kind" == 06 ]] && media=1
        [[ "$kind:$(first_line "$iface/bInterfaceSubClass"):$(first_line "$iface/bInterfaceProtocol")" == ff:42:01 ]] && adb=1
    done
    maker=$(first_line "$dev/manufacturer")
    product=$(first_line "$dev/product")
    (( adb || media )) || [[ "$product" == *Android* ]] || continue
    product=${product//_/ }
    label="$maker $product"
    # "SAMSUNG SAMSUNG Android" says its maker twice.
    [[ -n "$maker" && "$product" == "$maker"* ]] && label=$product
    if (( adb )); then
        usb=on name=$label
        break
    fi
    usb=off name=$label
done

# A tablet on the network is found through one on USB, whose Wi-Fi address adb can
# read, or at the address kept from last time, for as long as its port stays open.
# Not by mDNS, adb's own way (Wireless debugging): adb mdns services found nothing
# here with it on (2026-11-07), and firewalld's public zone, kept that way on purpose,
# lets no multicast in. A row's id is its route: the USB serial stays out of the
# shell's memory and of its logs, and scrcpy takes --select-usb.
row() { # id name via state address
    jq -nc --arg id "$1" --arg name "$2" --arg via "$3" --arg state "$4" --arg address "$5" \
        '{id: $id, name: $name, via: $via, state: $state, address: $address}'
}

# Before anything of this script's starts a server.
mark_server() {
    pgrep -x adb >/dev/null 2>&1 || : >"$SERVER_MARK"
}

device_rows() {
    local known=${1:-} serial state rest model addr listed
    command -v adb >/dev/null 2>&1 || return 0
    mark_server
    [[ -n "$known" ]] && timeout 2 adb connect "$known" >/dev/null 2>&1
    # One reading for the whole list: a device coming up between two would be in
    # neither a ready row nor an offered one.
    listed=$(timeout 5 adb devices -l 2>/dev/null | tail -n +2)
    while read -r serial state rest; do
        [[ -n "$serial" ]] || continue
        model=${rest##*model:}
        [[ "$model" == "$rest" ]] && model="Tablet"
        model=${model%% *}
        model=${model//_/ }
        case "$serial" in
            *:*)
                [[ "$state" == device ]] && row "wifi:$serial" "$model" wifi ready "$serial"
                ;;
            *)
                case "$state" in
                    device)
                        row usb "$model" usb ready ""
                        # Its stdin closed: adb shell would read the rest of this list.
                        addr=$(timeout 3 adb -s "$serial" shell ip -4 -o addr show wlan0 2>/dev/null </dev/null | awk '{print $4}')
                        addr=${addr%%/*}
                        # Unless it is up there already: listed but offline, as just
                        # after a mirror stops, it is still there to be started.
                        if [[ -n "$addr" ]] && ! grep -q "^$addr:5555[[:space:]]*device" <<<"$listed"; then
                            row "wifi:$addr:5555" "$model" wifi offered "$addr:5555"
                        fi
                        ;;
                    unauthorized) row usb "$name" usb unauthorized "" ;;
                esac
                ;;
        esac
    done <<<"$listed"
}

case "${1:-}" in
    devices)
        {
            [[ "$usb" == off ]] && row usb "$name" usb debugging ""
            [[ "$usb" == on ]] || [[ -n "${2:-}" ]] && device_rows "${2:-}"
        } | jq -sc '{devices: .}'
        ;;
    release)
        if [[ -e "$SERVER_MARK" ]] && ! systemctl --user is-active --quiet "$UNIT"; then
            rm -f -- "$SERVER_MARK"
            adb kill-server 2>/dev/null
        fi
        exit 0
        ;;
    forget)
        [[ -n "${2:-}" ]] || exit 2
        timeout 5 adb -s "$2" usb >/dev/null 2>&1
        timeout 3 adb disconnect "$2" >/dev/null 2>&1
        exit 0
        ;;
    status)
        running=false error="" via=""
        if systemctl --user is-active --quiet "$UNIT"; then
            running=true
            via=usb
            [[ "$(systemctl --user show -p ExecStart --value "$UNIT" 2>/dev/null)" == *--serial=* ]] && via=wifi
        elif systemctl --user is-failed --quiet "$UNIT"; then
            # scrcpy's own words, such as a device that was not allowed yet. Only
            # what it says as an error is kept in the journal (start, below).
            error=$(journalctl --user -u "$UNIT" -n 20 -o cat --no-pager 2>/dev/null | grep -E '^ERROR' | tail -n 1)
            error=${error#ERROR: }
            [[ -n "$error" ]] || error="scrcpy stopped"
        fi
        jq -nc --arg usb "$usb" --arg name "$name" --argjson running "$running" --arg via "$via" --arg error "$error" \
            '{usb: $usb, name: $name, running: $running, via: $via, error: $error}'
        ;;
    start|start-wifi)
        verb=$1
        shift
        if [[ "$verb" == start-wifi ]]; then
            address=${1:?}
            shift
            mark_server
            # The port opens through USB and stays open until the tablet restarts
            # or forget closes it, so that the cable can go. adb asks for this
            # machine's key there too, so an open port is not an open tablet.
            if ! timeout 3 adb connect "$address" 2>/dev/null | grep -q connected; then
                timeout 8 adb -d tcpip "${address##*:}" >/dev/null 2>&1
                sleep 2
                timeout 5 adb connect "$address" >/dev/null 2>&1
            fi
            set -- --serial="$address" "$@"
        fi
        for tool in scrcpy adb; do
            command -v "$tool" >/dev/null 2>&1 || { echo "$tool is not installed" >&2; exit 3; }
        done
        systemctl --user is-active --quiet "$UNIT" && exit 0
        systemctl --user reset-failed "$UNIT" 2>/dev/null
        # Its output stays out of the journal, for it names the device's serial;
        # errors come by the other stream. Wayland asked for by name: SDL prefers
        # X11, where a window on the fractional panel is drawn blurred.
        exec systemd-run --user --quiet --unit="$UNIT" --property=StandardOutput=null \
            --property=ExecStopPost="$(realpath -- "$0") release" \
            --setenv=WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" --setenv=SDL_VIDEODRIVER=wayland \
            -- scrcpy "$@"
        ;;
    stop)
        systemctl --user stop "$UNIT" 2>/dev/null
        systemctl --user reset-failed "$UNIT" 2>/dev/null
        exit 0
        ;;
    *)
        echo "usage: mirror.sh status | start ARGS | stop" >&2
        exit 2
        ;;
esac
