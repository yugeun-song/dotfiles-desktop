#!/usr/bin/env bash
# The camera switch against a real kernel, in a virtual machine:
#
#   tests/vm/camera.sh
#
# virtme-ng boots the running kernel on a copy-on-write view of this machine,
# where the script runs again as root (--guest). Inside, dummy_hcd and
# raw_gadget (tests/vm/usb_camera.py) present USB cameras that the real
# uvcvideo binds, vivid stands in for a camera that is not on USB, and vim2m
# for a codec that must be left alone. camera-switch, its udev rule and its
# switch file sit at their installed paths on tmpfs mounts, so nothing
# reaches the host, and the laptop's own camera is never touched.
#
# Every check reads sysfs, udev's database or the kernel log: whether an
# interface is authorized, whether a driver is bound, which capture nodes
# exist. No camera is ever streamed from, real or emulated.
#
# Needs vng, QEMU and /dev/kvm; skips without them. About half a minute.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

if [[ "${1:-}" != --guest ]]; then
    for tool in vng qemu-system-x86_64; do
        command -v "$tool" >/dev/null 2>&1 || { echo "SKIP  camera vm: $tool is not installed"; exit 0; }
    done
    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        echo "SKIP  camera vm: no access to /dev/kvm"
        exit 0
    fi
    for mod in dummy_hcd raw_gadget uvcvideo vivid vim2m; do
        modinfo -n "$mod" >/dev/null 2>&1 || { echo "SKIP  camera vm: the kernel has no $mod module"; exit 0; }
    done
    log=$(mktemp)
    trap 'rm -f -- "$log"' EXIT
    # A pipe, not a terminal: vng warns that stderr may be lost, which the
    # guest avoids by writing everything to stdout.
    timeout 300 vng -r --user root --memory 1G --cpus 2 \
        --exec "bash $REPO/tests/vm/camera.sh --guest $REPO" >"$log" 2>&1
    grep -E '^(PASS|FAIL|SKIP) ' "$log"
    if ! grep -qx 'result: ok' "$log"; then
        echo "FAIL  camera vm: the guest did not finish cleanly; its last lines:"
        grep -vE '^(PASS|FAIL|SKIP) ' "$log" | tail -40
        exit 1
    fi
    exit 0
fi

# In the guest from here on. stderr joins stdout (see above).
exec 2>&1
REPO=$2
failed=0
pass() { echo "PASS  camera vm: $*"; }
fail() { echo "FAIL  camera vm: $*"; failed=1; }
check() {
    local what=$1
    shift
    if "$@"; then pass "$what"; else fail "$what"; fi
}

mount -t tmpfs tmpfs /usr/local/bin
mount -t tmpfs tmpfs /var/lib
mount -t tmpfs tmpfs /etc/udev/rules.d
install -m755 "$REPO/camera/camera-switch.py" /usr/local/bin/camera-switch
install -m644 "$REPO/camera/70-camera-switch.rules" /etc/udev/rules.d/70-camera-switch.rules
udevadm control --reload

switch() { /usr/local/bin/camera-switch "$@"; }

# Capture nodes as udev classified them, for the device below $1 if given.
capture_nodes() {
    local n
    for n in /sys/class/video4linux/video*; do
        [[ -e "$n" ]] || continue
        [[ -n "${1:-}" && "$(readlink -f "$n/device")" != "$1"* ]] && continue
        udevadm info -q property -p "$n" 2>/dev/null | grep -q '^ID_V4L_CAPABILITIES=.*:capture:' \
            && basename "$n"
    done
}
count() { capture_nodes | wc -l; }
# A function, so wait_until counts again on every try.
nodes_are() { [[ "$(count)" == "$1" ]]; }

wait_until() {
    local deadline=$((SECONDS + $1))
    shift
    until "$@"; do
        (( SECONDS >= deadline )) && return 1
        sleep 0.1
    done
}

usb_device() {
    local d
    for d in /sys/bus/usb/devices/*; do
        [[ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" == "$1" ]] \
            && readlink -f "$d" && return 0
    done
    return 1
}

auth() { cat "$1/authorized"; }
driver() { [[ -e "$1/driver" ]] && basename "$(readlink -f "$1/driver")"; }
is() { [[ "$1" == "$2" ]]; }
lacks() { [[ "$1" != *"$2"* ]]; }
no_driver() { [[ ! -e "$1/driver" ]]; }

modprobe dummy_hcd num=2
modprobe raw_gadget
python3 -I "$REPO/tests/vm/usb_camera.py" dummy_udc.0 laptop >/tmp/laptop.log 2>&1 &
gadgets=($!)
cleanup() { kill "${gadgets[@]}" 2>/dev/null; }
trap cleanup EXIT

if ! wait_until 20 nodes_are 2; then
    fail "the emulated webcam never got its two capture nodes"
    cat /tmp/laptop.log
    dmesg | tail -30
    exit 1
fi
udevadm settle
cam=$(usb_device 1209:0001)
vc=("$cam/1-1:1.0" "$cam/1-1:1.2")
vs=("$cam/1-1:1.1" "$cam/1-1:1.3")
hid="$cam/1-1:1.4"

out=$(switch status)
check "status names the webcam and its two capture nodes" \
    grep -qE '^on +Test laptop webcam \(USB 1209:0001\): video[0-9]+, video[0-9]+$' <<<"$out"

mark=$(dmesg | wc -l)
out=$(switch off)
check "off exits 0 and says so" is "${out%%$'\n'*}" "Cameras off"
check "off: no capture node is left" is "$(count)" 0
for i in "${vc[@]}" "${vs[@]}"; do
    check "off: ${i##*/} deauthorized and unbound" bash -c "[[ \$(cat '$i/authorized') == 0 && ! -e '$i/driver' ]]"
done
check "off: the HID function stays authorized with its driver" is "$(auth "$hid"):$(driver "$hid")" "1:usbhid"
check "off: the USB device itself stays authorized" is "$(auth "$cam")" 1
check "off: the switch file is written" test -e /var/lib/camera-switch/off
echo "${vc[0]##*/}" >/sys/bus/usb/drivers_probe
check "off: the kernel refuses to bind a driver again" \
    bash -c "dmesg | awk 'NR > $mark' | grep -q '${vc[0]##*/}: Interface 0 is not authorized for usage'"
check "off: still no driver after the refused probe" no_driver "${vc[0]}"
check "status reports it off" grep -q '^off .*: USB video interfaces deauthorized$' <<<"$(switch status)"

mark=$(dmesg | wc -l)
out=$(switch on)
check "on exits 0 and says so" is "${out%%$'\n'*}" "Cameras on"
check "on: both capture nodes are back" is "$(count)" 2
for i in "${vc[@]}" "${vs[@]}"; do
    check "on: ${i##*/} authorized and bound to uvcvideo" is "$(auth "$i"):$(driver "$i")" "1:uvcvideo"
done
check "on: the kernel log shows uvcvideo finding the device again" \
    bash -c "dmesg | awk 'NR > $mark' | grep -q 'Found UVC 1.10 device Test laptop webcam'"
check "on: the switch file is gone" test ! -e /var/lib/camera-switch/off

check "toggle turns it off" is "$(switch toggle | head -1)" "Cameras off"
check "toggle turns it on again" is "$(switch toggle | head -1)" "Cameras on"

# A program holding the camera open (no frame is read) loses it on off.
node=$(capture_nodes "$cam" | head -1)
exec 3<"/dev/$node"
out=$(switch off)
check "off with the camera held open: no capture node is left" is "$(count)" 0
check "off with the camera held open: the claimed streaming interfaces are unbound too" \
    bash -c "[[ ! -e '${vs[0]}/driver' && ! -e '${vs[1]}/driver' ]]"
exec 3<&-
check "on after the program let go" is "$(switch on | head -1)" "Cameras on"
check "on after the program let go: both capture nodes are back" is "$(count)" 2

# Plugged in while off: udev's rule runs enforce before anyone can use it.
switch off >/dev/null
python3 -I "$REPO/tests/vm/usb_camera.py" dummy_udc.1 plain >/tmp/plain.log 2>&1 &
gadgets+=($!)
wait_until 20 usb_device 1209:0002 >/dev/null
udevadm settle
plug=$(usb_device 1209:0002)
check "plugged in while off: its interfaces are deauthorized" \
    bash -c "[[ \$(cat '$plug/2-1:1.0/authorized') == 0 && \$(cat '$plug/2-1:1.1/authorized') == 0 ]]"
check "plugged in while off: no capture node" is "$(count)" 0
out=$(switch on)
check "on brings back the camera plugged in while off" is "$(count)" 3

# What a reboot leaves: the record under /run gone, the USB cameras fresh.
fresh_boot() {
    local i
    rm -rf /run/camera-switch
    for i in /sys/bus/usb/devices/*:1.*; do
        [[ "$(cat "$i/bInterfaceClass")" == 0e && "$(cat "$i/authorized")" == 0 ]] && echo 1 >"$i/authorized"
    done
    for i in "${vc[@]}" "$plug/2-1:1.0"; do echo "${i##*/}" >/sys/bus/usb/drivers_probe; done
    udevadm settle
}

# A boot with the switch off: udev replays the add events. The switch file
# is set aside while the cameras come up, or the rule would turn each off as
# it binds.
switch off >/dev/null
mv /var/lib/camera-switch/off /var/lib/camera-switch/off.kept
fresh_boot
check "boot replay: the cameras are live before the replay" is "$(count)" 3
mv /var/lib/camera-switch/off.kept /var/lib/camera-switch/off
udevadm trigger --action=add --subsystem-match=usb --subsystem-match=video4linux
udevadm settle
check "boot replay: udev turns every camera off again" is "$(count)" 0
check "boot replay: on finds them without the old record" is "$(switch on | head -1)" "Cameras on"
check "boot replay: all three capture nodes are back" is "$(count)" 3

# The root step only partly done, the udev rule missing: a reboot brings the
# cameras up under an off switch, and the key goes by what is live.
mv /etc/udev/rules.d/70-camera-switch.rules /tmp/rule.kept
udevadm control --reload
check "without the rule: status names it" grep -q '^setup .*the udev rule is not installed' <<<"$(switch status)"
switch off >/dev/null
fresh_boot
check "without the rule: a reboot brings the cameras up under an off switch" is "$(count)" 3
out=$(switch toggle)
check "without the rule: the key turns the live cameras off" is "${out%%$'\n'*}" "Cameras off"
check "without the rule: no capture node is left" is "$(count)" 0
check "without the rule: off says a later camera stays on" grep -q 'the udev rule is not installed$' <<<"$out"
out=$(switch toggle)
check "without the rule: the next press turns them on" is "${out%%$'\n'*}" "Cameras on"
check "without the rule: all three capture nodes are back" is "$(count)" 3
mv /tmp/rule.kept /etc/udev/rules.d/70-camera-switch.rules
udevadm control --reload

# A camera that is not on USB, loaded while off: its own add event reaches
# enforce after udev has recorded the node's capabilities.
switch off >/dev/null
modprobe vivid n_devs=1 node_types=0x1 num_inputs=1 input_types=0x0
udevadm settle
check "vivid loaded while off: its driver is unbound" no_driver /sys/bus/platform/devices/vivid.0
check "vivid loaded while off: no capture node" is "$(count)" 0
out=$(switch on)
check "on binds vivid again" is "$(driver /sys/bus/platform/devices/vivid.0)" vivid
check "on: four capture nodes with vivid's" is "$(count)" 4

# A codec has video nodes but captures nothing from the room.
modprobe vim2m
udevadm settle
out=$(switch off)
check "vim2m is not taken for a camera" lacks "$out" vim2m
check "vim2m stays bound while the cameras are off" is "$(driver /sys/bus/platform/devices/vim2m.0)" vim2m
switch on >/dev/null

# The fallback for kernels without per-interface authorization relies on
# this: a deauthorized device loses its interfaces, and authorizing it again
# binds its drivers with no probe asked for.
echo 0 >"$plug/authorized"
check "device deauthorized: its interfaces are gone" test ! -e "$plug/2-1:1.0"
echo 1 >"$plug/authorized"
check "device authorized again: uvcvideo is bound with no probe" \
    wait_until 10 bash -c "[[ \$(basename \"\$(readlink -f '$plug/2-1:1.0/driver')\") == uvcvideo ]]"

if (( failed )); then
    echo "result: failed"
    dmesg | grep -E 'uvcvideo|usb [12]-1|vivid|authoriz' | tail -40
    exit 1
fi
echo "result: ok"
