#!/usr/bin/python3 -I
"""Turns every camera on this machine off, or back on.

    camera-switch                 what is on and what is off
    camera-switch status --json   the same, for programs
    camera-switch off|on|toggle   root's to do; asks polkit through pkexec
    camera-switch enforce         udev's call when a camera appears

Installed as /usr/local/bin/camera-switch by install.sh, with a polkit action
that lets the active local session run it without a password: that session
already holds the cameras through udev's uaccess, and a key that asks for a
password is not a key anyone presses. Root-owned and outside the home
directory, since whatever pkexec runs as root must not be writable by the user
it runs for.

Cameras are found from what the kernel publishes, never from a list of
models: video4linux nodes that capture from hardware, and USB interfaces of
the video class. Whether a node captures is read from udev's database, where
v4l_id recorded the driver's capabilities, so no camera device is ever opened
here. A node with an output, tuner or radio is a codec, a TV card or an output
and is left alone, and so is a virtual one such as v4l2loopback, which has no
hardware behind it.

Each camera is turned off by the strongest means its hardware and kernel
offer, and checked afterwards in sysfs. A camera that still has a capture node
falls through to the next means; one that nothing reaches is reported as still
on, never as off.

  platform switch  a laptop's own camera switch in its platform driver
                   (ideapad, asus-wmi, eeepc, out-of-tree msi-ec), kept by the
                   firmware below every driver. Tried first, for all cameras
                   at once; how far it reaches varies by model, so a camera
                   it leaves on the bus still goes through the rest.
  usb-interface    deauthorizes the camera's video interfaces: the kernel
                   unbinds the driver and refuses to bind one again, while the
                   rest of a composite device (a microphone, a presence sensor)
                   keeps working.
  usb-device       deauthorizes the whole USB device, as if unplugged: for a
                   kernel without per-interface authorization, or interfaces
                   that did not let go.
  unbind           unbinds the driver of whatever the capture nodes belong to:
                   the means for a camera that is not on USB (an ISP or CSI-2
                   receiver).
  module           unloads that driver's module, for a driver that offers no
                   unbind, if nothing holds it and it drives nothing else.

The switch position persists in /var/lib/camera-switch/off. While it is
there, udev runs `enforce` for every camera that appears (plugged in,
re-enumerated after a resume, found at boot), which turns it off at once. What
was done to which device lives under /run, because a reboot undoes all of it
anyway; `on` undoes exactly that, newest first.

Not reached: a camera driven from user space through libusb with no kernel
video driver, and root, which can always turn a camera back on.
"""

import fcntl
import json
import os
import shutil
import subprocess
import sys
import syslog
import time

SWITCH_FILE = "/var/lib/camera-switch/off"
# What install.sh's root step puts in place; each one missing costs something
# the program says out loud (see missing_setup).
SYSTEM_COPY = "/usr/local/bin/camera-switch"
POLKIT_ACTION = "/usr/share/polkit-1/actions/io.github.yugeun-song.camera-switch.policy"
UDEV_RULE = "/etc/udev/rules.d/70-camera-switch.rules"
RUN_DIR = "/run/camera-switch"
RECORD_FILE = RUN_DIR + "/record.json"
LOCK_FILE = RUN_DIR + "/lock"

V4L = "/sys/class/video4linux"
USB_DEVICES = "/sys/bus/usb/devices"
UDEV_DATA = "/run/udev/data"

USB_CLASS_VIDEO = "0e"
USB_SUBCLASS_VIDEOCONTROL = "01"
NOT_A_CAMERA = frozenset({"video_output", "tuner", "radio"})

# (platform device, attribute, off, on). A name ending in ":" is a prefix,
# for ACPI devices numbered per machine. The values are written exactly:
# asus-wmi hands the number to the firmware unchecked. Left out on purpose:
# samsung-galaxybook's block_recording, which takes the microphone with it.
POWER_SWITCHES = (
    ("VPC2004:", "camera_power", "0", "1"),
    ("asus-nb-wmi", "camera", "0", "1"),
    ("eeepc-wmi", "camera", "0", "1"),
    ("eeepc", "camera", "0", "1"),
    ("msi-ec", "webcam", "off", "on"),
)

# How long a platform switch gets to take its camera off the bus, and a camera
# to come back with its driver bound. UVC probing runs a round of control
# requests, which some modules answer slowly.
SWITCH_SETTLE = 3.0
COME_BACK = 8.0
LOCK_WAIT = 30.0
POLL = 0.1

# udev and pkexec both start this with a bare environment.
TOOL_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

USAGE = "usage: camera-switch [status [--json] | off | on | toggle | enforce]"


class Host:
    """The kernel and the state files, as this program sees them. The unit
    tests stand a model of sysfs in its place, under a temporary root."""

    def __init__(self, root=""):
        self.root = root

    def at(self, path):
        return self.root + path

    def read(self, path):
        try:
            with open(self.at(path), encoding="utf-8", errors="replace") as f:
                return f.read().strip()
        except OSError:
            return None

    def write(self, path, value):
        # One write(2) and no O_CREAT: a sysfs attribute takes its value in a
        # single call, and a missing one must fail rather than become a file.
        fd = os.open(self.at(path), os.O_WRONLY | os.O_CLOEXEC)
        try:
            os.write(fd, value.encode())
        finally:
            os.close(fd)

    def listdir(self, path):
        try:
            return sorted(os.listdir(self.at(path)))
        except OSError:
            return []

    def exists(self, path):
        return os.path.exists(self.at(path))

    def owned_by_root(self, path):
        """A regular file only root can change: the only kind pkexec may be
        pointed at without a password."""
        try:
            st = os.stat(self.at(path))
        except OSError:
            return False
        return os.path.isfile(self.at(path)) and st.st_uid == 0 and not st.st_mode & 0o022

    def resolve(self, path):
        real = os.path.realpath(self.at(path))
        if self.root and real.startswith(self.root + "/"):
            return real[len(self.root):]
        return real

    def run(self, argv):
        tool = shutil.which(argv[0], path=TOOL_PATH)
        if tool is None:
            return 127, argv[0] + " is not installed"
        try:
            done = subprocess.run([tool] + argv[1:], stdin=subprocess.DEVNULL,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired) as e:
            return 1, str(e)
        return done.returncode, done.stdout.strip()

    def sleep(self, seconds):
        time.sleep(seconds)

    def now(self):
        return time.monotonic()

    def log(self, message, error=False):
        syslog.syslog(syslog.LOG_ERR if error else syslog.LOG_INFO, message)

    def switch_is_off(self):
        return os.path.exists(self.at(SWITCH_FILE))

    def set_switch(self, off):
        path = self.at(SWITCH_FILE)
        if not off:
            try:
                os.unlink(path)
            except FileNotFoundError:
                return
        else:
            os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_CLOEXEC, 0o644)
            try:
                os.fsync(fd)
            finally:
                os.close(fd)
        # The position has to survive a power cut right after the key press,
        # either way.
        dfd = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)

    def load_record(self):
        try:
            with open(self.at(RECORD_FILE), encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            return []
        if not isinstance(data, dict) or data.get("version") != 1:
            return []
        return [e for e in data.get("done", []) if valid(e)]

    def save_record(self, record):
        path = self.at(RECORD_FILE)
        os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
        tmp = path + ".new"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"version": 1, "done": record}, f, indent=1)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)

    def busy(self):
        """Whether a camera-switch holds the lock now. Read from /proc/locks:
        the lock file is root's 0600, and a user allowed to lock it could
        hold every switch back."""
        try:
            st = os.stat(self.at(LOCK_FILE))
        except OSError:
            return False
        inode = f"{os.major(st.st_dev):02x}:{os.minor(st.st_dev):02x}:{st.st_ino}"
        for line in (self.read("/proc/locks") or "").splitlines():
            fields = line.split()
            if len(fields) > 1 and fields[1] == "->":
                del fields[1]
            if len(fields) > 5 and fields[1] == "FLOCK" and fields[5] == inode:
                return True
        return False

    def lock(self):
        path = self.at(LOCK_FILE)
        os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o600)
        deadline = time.monotonic() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except BlockingIOError:
                if time.monotonic() > deadline:
                    os.close(fd)
                    raise TimeoutError("another camera-switch has held the lock for "
                                       f"{LOCK_WAIT:.0f} s")
                time.sleep(0.05)


class Camera:
    """One camera as one device to switch: the USB device, or for anything
    else the device its capture nodes belong to."""

    def __init__(self, device, bus):
        self.device = device
        self.bus = bus
        self.nodes = []
        self.owners = []
        self.interfaces = []
        self.name = ""
        self.ident = ""
        self.serial = ""


def add_unique(items, item):
    if item not in items:
        items.append(item)


def bus_of(host, device):
    return os.path.basename(host.resolve(device + "/subsystem"))


def owner_of(host, node):
    """The hardware device a video4linux node hangs off, None for a virtual one."""
    if not host.exists(f"{V4L}/{node}/device"):
        return None
    owner = host.resolve(f"{V4L}/{node}/device")
    if owner.startswith("/sys/devices/virtual/"):
        return None
    return owner


def captures(host, node):
    """True if the node captures from a camera, False if it is something else,
    None while udev has not recorded it yet (its own event runs enforce)."""
    if not host.exists(UDEV_DATA):
        # No udev to ask, so the node counts as a camera: turning off a codec
        # by mistake is undone by `on`, missing a camera is not undone at all.
        return True
    dev = host.read(f"{V4L}/{node}/dev")
    data = host.read(f"{UDEV_DATA}/c{dev}") if dev else None
    if data is None:
        return None
    caps = None
    for line in data.splitlines():
        if line.startswith("E:ID_V4L_CAPABILITIES="):
            caps = {word for word in line.split("=", 1)[1].split(":") if word}
    if caps is None:
        return True
    return "capture" in caps and not caps & NOT_A_CAMERA


def under(path, device):
    return path == device or path.startswith(device + "/")


def live_nodes(host, device):
    """Capture nodes below a device. A node udev has not finished with counts
    as live: this is the check that decides whether a camera is off."""
    nodes = []
    for node in host.listdir(V4L):
        if not node.startswith("video"):
            continue
        owner = owner_of(host, node)
        if owner and under(owner, device) and captures(host, node) is not False:
            nodes.append(node)
    return nodes


def describe(host, cam):
    if cam.bus == "usb":
        vendor = host.read(cam.device + "/idVendor")
        product = host.read(cam.device + "/idProduct")
        if vendor and product:
            cam.ident = f"{vendor}:{product}"
        cam.serial = host.read(cam.device + "/serial") or ""
        name = host.read(cam.device + "/product")
        if name:
            return name
        return ("USB camera " + cam.ident).strip()
    for node in cam.nodes:
        name = host.read(f"{V4L}/{node}/name")
        if name:
            return name
    return os.path.basename(cam.device)


def discover(host, record=()):
    found = {}

    def camera(device, bus):
        if device not in found:
            found[device] = Camera(device, bus)
        return found[device]

    for node in host.listdir(V4L):
        if not node.startswith("video"):
            continue
        owner = owner_of(host, node)
        if owner is None or captures(host, node) is not True:
            continue
        if host.exists(owner + "/bInterfaceClass"):
            cam = camera(os.path.dirname(owner), "usb")
            add_unique(cam.interfaces, os.path.basename(owner))
        else:
            cam = camera(owner, bus_of(host, owner))
        cam.nodes.append(node)
        add_unique(cam.owners, owner)

    # Video-class interfaces also find a camera whose driver is not bound
    # (not loaded yet, or turned off here), which has no node to find it by.
    for name in host.listdir(USB_DEVICES):
        if ":" not in name:
            continue
        path = host.resolve(f"{USB_DEVICES}/{name}")
        if host.read(path + "/bInterfaceClass") == USB_CLASS_VIDEO:
            add_unique(camera(os.path.dirname(path), "usb").interfaces, name)

    # A device deauthorized whole has no interfaces left to find it by.
    for entry in record:
        if host.exists(entry["device"]) and same_device(host, entry):
            camera(entry["device"], entry["bus"])

    for cam in found.values():
        cam.name = describe(host, cam)
        # Named while it was on: a camera that is off may have no node to
        # name it by, and older kernels blank a deauthorized device's strings.
        for entry in record:
            if entry["device"] == cam.device and entry.get("name") and same_device(host, entry):
                cam.name = entry["name"]
    return sorted(found.values(), key=lambda c: c.device)


def valid(entry):
    """A record entry this version can act on; anything else is dropped."""
    needs = {"usb-interface": "interfaces", "unbind": "unbound", "module": "modules"}
    if not isinstance(entry, dict) or entry.get("method") not in METHODS:
        return False
    if not isinstance(entry.get("device"), str) or not isinstance(entry.get("bus"), str):
        return False
    key = needs.get(entry["method"])
    return key is None or isinstance(entry.get(key), list)


def same_device(host, entry):
    """Whether the device at a recorded path is still the one turned off there,
    not another plugged into the same port since."""
    if not host.exists(entry["device"]):
        return False
    if entry.get("bus") != "usb":
        return True
    vendor = host.read(entry["device"] + "/idVendor")
    product = host.read(entry["device"] + "/idProduct")
    if entry.get("ident") and f"{vendor}:{product}" != entry["ident"]:
        return False
    serial = host.read(entry["device"] + "/serial") or ""
    return not entry.get("serial") or serial == entry["serial"]


def control_first(host, device, interfaces):
    """UVC's driver binds the video control interface and claims the streaming
    ones from it, so that one goes first, both off and on."""
    def order(name):
        sub = host.read(f"{device}/{name}/bInterfaceSubClass")
        try:
            number = int(host.read(f"{device}/{name}/bInterfaceNumber") or "ff", 16)
        except ValueError:
            number = 255
        return (sub != USB_SUBCLASS_VIDEOCONTROL, number, name)
    return sorted(interfaces, key=order)


def probe(host, bus, name):
    """Asks the bus to find a driver for a device again; loads the module by
    its alias first if the driver is not loaded at all."""
    path = f"/sys/bus/{bus}/devices/{name}"
    try:
        host.write(f"/sys/bus/{bus}/drivers_probe", name)
    except OSError:
        pass
    if host.exists(path + "/driver"):
        return
    alias = host.read(path + "/modalias")
    if alias:
        host.run(["modprobe", "-q", alias])
        try:
            host.write(f"/sys/bus/{bus}/drivers_probe", name)
        except OSError:
            pass


class UsbInterfaces:
    name = "usb-interface"
    done = "USB video interfaces deauthorized"

    def check(self, host, cam, everyone):
        if cam.bus != "usb":
            return "not a USB device"
        if not cam.interfaces:
            return "no video interface"
        for intf in cam.interfaces:
            if not host.exists(f"{cam.device}/{intf}/authorized"):
                return "this kernel has no per-interface authorization"
        return None

    def apply(self, host, cam, everyone):
        for intf in control_first(host, cam.device, cam.interfaces):
            host.write(f"{cam.device}/{intf}/authorized", "0")
        return {"interfaces": list(cam.interfaces)}

    def holds(self, host, entry):
        dev = entry["device"]
        return all(host.read(f"{dev}/{i}/authorized") == "0" and not host.exists(f"{dev}/{i}/driver")
                   for i in entry["interfaces"])

    def undo(self, host, entry):
        dev = entry["device"]
        present = [i for i in entry["interfaces"] if host.exists(f"{dev}/{i}")]
        # All of them before any probe: a driver that claims several
        # interfaces cannot claim one that is still deauthorized.
        for intf in present:
            host.write(f"{dev}/{intf}/authorized", "1")
        for intf in control_first(host, dev, present):
            probe(host, "usb", intf)


class UsbDevice:
    name = "usb-device"
    done = "USB device deauthorized"

    def check(self, host, cam, everyone):
        if cam.bus != "usb":
            return "not a USB device"
        if not host.exists(cam.device + "/authorized"):
            return "the USB device has no authorization switch"
        return None

    def apply(self, host, cam, everyone):
        host.write(cam.device + "/authorized", "0")
        return {}

    def holds(self, host, entry):
        return host.read(entry["device"] + "/authorized") == "0"

    def undo(self, host, entry):
        host.write(entry["device"] + "/authorized", "1")


def bound(host, owners):
    """(device, driver directory) for each owner a driver is bound to."""
    return [(o, host.resolve(o + "/driver")) for o in owners if host.exists(o + "/driver")]


class Unbind:
    name = "unbind"
    done = "driver unbound"

    def check(self, host, cam, everyone):
        pairs = bound(host, cam.owners)
        if not pairs:
            return "no driver is bound"
        for _, driver in pairs:
            if not host.exists(driver + "/unbind"):
                return os.path.basename(driver) + " offers no unbind"
        return None

    def apply(self, host, cam, everyone):
        done = []
        for owner, driver in bound(host, cam.owners):
            host.write(driver + "/unbind", os.path.basename(owner))
            done.append({"device": owner, "bus": bus_of(host, owner),
                         "driver": os.path.basename(driver)})
        return {"unbound": done}

    def holds(self, host, entry):
        return all(not host.exists(u["device"] + "/driver") for u in entry["unbound"])

    def undo(self, host, entry):
        for u in entry["unbound"]:
            if not host.exists(u["device"]) or host.exists(u["device"] + "/driver"):
                continue
            name = os.path.basename(u["device"])
            try:
                host.write(f"/sys/bus/{u['bus']}/drivers/{u['driver']}/bind", name)
            except OSError:
                probe(host, u["bus"], name)


class Module:
    name = "module"
    done = "driver module unloaded"

    def modules(self, host, cam, everyone):
        """{module: [owners]} for this camera, or the reason there is none to unload."""
        mods = {}
        pairs = bound(host, cam.owners)
        if not pairs:
            return "no driver is bound"
        for owner, driver in pairs:
            if not host.exists(driver + "/module"):
                return os.path.basename(driver) + " is built into the kernel"
            mods.setdefault(os.path.basename(host.resolve(driver + "/module")), []).append(owner)
        # A UVC driver is also bound to the streaming interfaces it claimed.
        cameras = {d for c in everyone for d in c.owners + [f"{c.device}/{i}" for i in c.interfaces]}
        for mod in mods:
            refcnt = host.read(f"/sys/module/{mod}/refcnt")
            if refcnt is None:
                return mod + " cannot be unloaded"
            if refcnt != "0":
                return mod + " is in use by an open program"
            holders = host.listdir(f"/sys/module/{mod}/holders")
            if holders:
                return f"{mod} is needed by {holders[0]}"
            for link in host.listdir(f"/sys/module/{mod}/drivers"):
                driver = host.resolve(f"/sys/module/{mod}/drivers/{link}")
                for item in host.listdir(driver):
                    target = host.resolve(f"{driver}/{item}")
                    if target.startswith("/sys/devices/") and item != "module" \
                            and target not in cameras:
                        return f"{mod} also drives {item}"
        return mods

    def check(self, host, cam, everyone):
        mods = self.modules(host, cam, everyone)
        return mods if isinstance(mods, str) else None

    def apply(self, host, cam, everyone):
        mods = self.modules(host, cam, everyone)
        unloaded = []
        for mod, owners in mods.items():
            rc, out = host.run(["rmmod", mod])
            if rc != 0:
                raise OSError(f"rmmod {mod}: {out or rc}")
            unloaded.append({"module": mod, "devices": [
                {"device": o, "bus": bus_of(host, o)} for o in owners]})
        return {"modules": unloaded}

    def holds(self, host, entry):
        return all(not host.exists(f"/sys/module/{m['module']}/refcnt") for m in entry["modules"])

    def undo(self, host, entry):
        for m in entry["modules"]:
            host.run(["modprobe", m["module"]])
            for d in m["devices"]:
                if host.exists(d["device"]) and not host.exists(d["device"] + "/driver"):
                    probe(host, d["bus"], os.path.basename(d["device"]))


METHODS = {m.name: m for m in (UsbInterfaces(), UsbDevice(), Unbind(), Module())}
CHAINS = {"usb": ("usb-interface", "usb-device", "unbind", "module")}
OTHER_CHAIN = ("unbind", "module")


class PowerSwitch:
    def __init__(self, path, off, on):
        self.path = path
        self.off = off
        self.on = on
        self.label = f"Camera power switch ({os.path.basename(os.path.dirname(path))})"

    def word(self, value):
        return "off" if value == self.off else "on" if value == self.on else str(value)


def power_switches(host):
    found = []
    for device in host.listdir("/sys/bus/platform/devices"):
        for name, attribute, off, on in POWER_SWITCHES:
            matches = device.startswith(name) if name.endswith(":") else device == name
            path = f"/sys/bus/platform/devices/{device}/{attribute}"
            # eeepc-laptop creates its attribute on every model and fails
            # the read where the BIOS has no camera control.
            if matches and host.read(path) is not None:
                found.append(PowerSwitch(path, off, on))
    return found


def set_power_switches(host, report, off):
    """Sets every platform switch; True if any changed. A write the read-back
    does not confirm counts as not done: eeepc-laptop reports success when
    the firmware call behind it failed."""
    changed = False
    for sw in power_switches(host):
        want = sw.off if off else sw.on
        if host.read(sw.path) == want:
            report.switches.append((sw.label, sw.word(want), None))
            continue
        try:
            host.write(sw.path, want)
        except OSError as e:
            report.switches.append((sw.label, sw.word(host.read(sw.path)), e.strerror or str(e)))
            continue
        now = host.read(sw.path)
        report.switches.append((sw.label, sw.word(now), None if now == want else "the firmware did not take it"))
        if now == want:
            changed = True
            host.log(f"{sw.path} set to {want}")
    return changed


class Report:
    def __init__(self, verb):
        self.verb = verb
        self.cameras = []
        self.switches = []
        self.notes = []
        self.trouble = False
        # Whether udev turns off what appears later: the summary promises it
        # only then.
        self.enforced = True

    def add(self, cam, state, how):
        self.cameras.append((cam, state, how))

    def failed(self):
        if self.trouble or any(err for _, _, err in self.switches):
            return True
        want = "off" if self.verb == "off" else "on"
        return any(state != want for _, state, _ in self.cameras)


def is_off(host, cam, held):
    """Off: no capture node, and something keeps every driver from binding.
    A USB camera counts by the video interfaces it has now, not by the
    record: one still enumerating has interfaces newer than the record, and
    those would bind and come up live."""
    if live_nodes(host, cam.device):
        return None
    if cam.bus == "usb":
        if host.read(cam.device + "/authorized") == "0":
            return METHODS["usb-device"].done
        if cam.interfaces and all(host.read(f"{cam.device}/{i}/authorized") == "0"
                                  for i in cam.interfaces):
            return METHODS["usb-interface"].done
    for entry in reversed(held):
        if entry["method"] in ("unbind", "module") and METHODS[entry["method"]].holds(host, entry):
            return METHODS[entry["method"]].done
    return None


def turn_off(host, report, record):
    before = len(discover(host, record))
    if set_power_switches(host, report, off=True) and before:
        # The camera the switch controls leaves the bus a moment later; the
        # others are dealt with below either way.
        deadline = host.now() + SWITCH_SETTLE
        while host.now() < deadline and len(discover(host, record)) >= before:
            host.sleep(POLL)

    everyone = discover(host, record)
    for cam in everyone:
        held = [e for e in record if e["device"] == cam.device]
        how = is_off(host, cam, held)
        if how:
            report.add(cam, "off", how)
            continue
        tried = []
        for name in CHAINS.get(cam.bus, OTHER_CHAIN):
            method = METHODS[name]
            reason = method.check(host, cam, everyone)
            if reason:
                tried.append(f"{name}: {reason}")
                continue
            try:
                detail = method.apply(host, cam, everyone)
            except OSError as e:
                tried.append(f"{name}: {e.strerror or e}")
                continue
            entry = {"method": name, "device": cam.device, "bus": cam.bus,
                     "name": cam.name, "ident": cam.ident, "serial": cam.serial}
            entry.update(detail)
            record.append(entry)
            keep_record(host, report, record)
            if not live_nodes(host, cam.device) and method.holds(host, entry):
                host.log(f"{cam.name} ({cam.device}): {name}")
                report.add(cam, "off", method.done)
                break
            tried.append(f"{name}: the camera was still there afterwards")
        else:
            host.log(f"{cam.name} ({cam.device}) is still on: " + "; ".join(tried), error=True)
            report.add(cam, "on", "; ".join(tried) or "nothing can turn it off")


def keep_record(host, report, record):
    """The camera is off either way; without the record, `on` finds only
    deauthorized video interfaces by itself, so the loss is said."""
    try:
        host.save_record(record)
    except OSError as e:
        host.log(f"could not save {RECORD_FILE}: {e}", error=True)
        note = f"What was done could not be recorded ({e.strerror or e}); `on` may miss it"
        if note not in report.notes:
            report.notes.append(note)
            report.trouble = True


def turn_on(host, report, record):
    left = []
    for entry in reversed(record):
        if not same_device(host, entry):
            continue
        try:
            METHODS[entry["method"]].undo(host, entry)
            host.log(f"{entry['name']} ({entry['device']}): {entry['method']} undone")
        except OSError as e:
            host.log(f"{entry['name']} ({entry['device']}): {entry['method']} not undone: {e}", error=True)
            left.insert(0, entry)
    keep_record(host, report, left)

    # Video interfaces deauthorized with no record left of it (/run cleared
    # by hand): `on` means every camera, so they are let go too.
    for cam in discover(host, left):
        stuck = [i for i in cam.interfaces if host.read(f"{cam.device}/{i}/authorized") == "0"]
        if cam.bus == "usb" and stuck and host.read(cam.device + "/authorized") != "0":
            METHODS["usb-interface"].undo(host, {"device": cam.device, "interfaces": stuck})

    present = {c.device for c in discover(host, left)}
    switched = set_power_switches(host, report, off=False)

    # Probing finishes after the writes return, and a camera the platform
    # switch brought back enumerates from scratch, under a new device.
    waited = {e["device"] for e in record if host.exists(e["device"])}
    deadline = host.now() + COME_BACK
    while True:
        cams = discover(host, left)
        missing = [c for c in cams if c.device in waited and not c.nodes]
        returned = any(c.nodes and c.device not in present for c in cams)
        if (not missing and (returned or not switched)) or host.now() >= deadline:
            break
        host.sleep(POLL)
    for cam in cams:
        if cam.nodes:
            report.add(cam, "on", ", ".join(cam.nodes))
        elif any(e["device"] == cam.device for e in left):
            report.add(cam, "off", "could not be undone; see journalctl -t camera-switch")
        elif cam.device in waited:
            report.add(cam, "off", f"no capture node within {COME_BACK:.0f} s")
        else:
            report.add(cam, "on", "no driver is bound")


def label(cam):
    kind = "USB " + cam.ident if cam.bus == "usb" and cam.ident else cam.bus
    return f"{cam.name} ({kind})"


def summary(report):
    """A headline and one line per camera, the shape a notification takes."""
    want = "off" if report.verb == "off" else "on"
    wrong = [c for c, state, _ in report.cameras if state != want]
    if not report.cameras:
        head = "Cameras " + want
        lines = [] if report.switches else [
            "No camera found" + ("; one that appears is turned off"
                                 if want == "off" and report.enforced else "")]
    elif wrong:
        n = len(wrong)
        head = f"{n} camera{'s' if n > 1 else ''} still {'on' if want == 'off' else 'off'}"
        lines = []
    else:
        head = "Cameras " + want
        lines = []
    for cam, state, how in report.cameras:
        if state == want and want == "on":
            lines.append(f"{label(cam)}: on")
        elif state == want:
            lines.append(f"{label(cam)}: off, {how}")
        else:
            lines.append(f"{label(cam)}: still {state}, {how}")
    # The firmware switch is how the camera went: it left the bus with it.
    for name, state, err in report.switches:
        lines.append(f"{name}: {err}" if err else f"{name}: {state}")
    return "\n".join([head] + lines + report.notes)


def missing_setup(host):
    """What install.sh's root step has not put in place, and what each gap
    costs. Everything still works without them, with these costs."""
    gaps = []
    if not host.owned_by_root(SYSTEM_COPY):
        gaps.append(f"{SYSTEM_COPY} is not installed (root's), so turning cameras off or on "
                    "asks for an administrator password")
    elif not host.exists(POLKIT_ACTION):
        gaps.append("the polkit action is not installed, so turning cameras off or on asks "
                    "for an administrator password")
    if not host.exists(UDEV_RULE):
        gaps.append("the udev rule is not installed, so a camera that appears later or at boot "
                    "stays on until the switch is pressed")
    return gaps


def status(host, as_json):
    record = host.load_record()
    off = host.switch_is_off()
    cams = []
    for cam in discover(host, record):
        held = [e for e in record if e["device"] == cam.device]
        how = is_off(host, cam, held)
        cams.append({"name": cam.name, "bus": cam.bus, "id": cam.ident, "device": cam.device,
                     "state": "off" if how else "on", "how": how or ", ".join(cam.nodes) or "no driver bound",
                     "nodes": cam.nodes})
    switches = [{"path": sw.path, "name": sw.label,
                 "state": "off" if host.read(sw.path) == sw.off else "on"}
                for sw in power_switches(host)]
    gaps = missing_setup(host)
    # Mid-action readings mix the new switch position with the old devices;
    # the bar waits for busy to clear before it believes one.
    busy = host.busy()
    if as_json:
        print(json.dumps({"switch": "off" if off else "on", "busy": busy, "cameras": cams,
                          "power_switches": switches, "missing": gaps}))
        return 0
    if not off:
        print("switch   on")
    elif host.exists(UDEV_RULE):
        print("switch   off; a camera that appears is turned off too")
    else:
        print("switch   off")
    if busy:
        print("busy     a camera-switch is turning cameras off or on right now")
    for gap in gaps:
        print("setup    " + gap)
    for sw in switches:
        print(f"power    {sw['path']}: {sw['state']}")
    for c in cams:
        kind = "USB " + c["id"] if c["bus"] == "usb" and c["id"] else c["bus"]
        print(f"{c['state']:<8} {c['name']} ({kind}): {c['how']}")
    if not cams:
        print("no camera found")
    return 0


def elevate(verb):
    """Runs the verb again as root. pkexec goes into the installed copy, which
    its polkit action lets the seat's session run without a password; with
    none installed, into this copy, which polkit runs only for an
    administrator's password. Without pkexec, sudo: asking on a terminal,
    and from a key only if it needs no password."""
    target = SYSTEM_COPY if Host().owned_by_root(SYSTEM_COPY) else os.path.realpath(__file__)
    pkexec = shutil.which("pkexec", path=TOOL_PATH)
    if pkexec:
        # pkexec's complaint is held back: printed before the headline, it
        # became the notification's title.
        done = subprocess.run([pkexec, target, verb], stderr=subprocess.PIPE, text=True)
        said = [line.strip() for line in (done.stderr or "").splitlines() if line.strip()]
        reason = said[0].replace("Error executing command as another user: ", "") if said else ""
        if done.returncode == 126:
            print("Camera switch cancelled\nThe password dialog was dismissed; nothing changed")
        elif done.returncode == 127:
            print("Camera switch not allowed\n" + (f"polkit: {reason}" if reason else
                  "polkit refused, or no authentication agent was there to ask"))
        elif said:
            print("\n".join(said), file=sys.stderr)
        return done.returncode
    sudo = shutil.which("sudo", path=TOOL_PATH)
    if sudo and sys.stdin.isatty():
        return subprocess.run([sudo, target, verb]).returncode
    if sudo and subprocess.run([sudo, "-n", "true"], stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return subprocess.run([sudo, "-n", target, verb], stdin=subprocess.DEVNULL).returncode
    print("Camera switch needs root\nNo pkexec, and no sudo that works without a password here")
    return 3


def act(host, verb, requested=None):
    """off, on, toggle or enforce, as root: (exit status, what to show)."""
    try:
        lock = host.lock()
    except TimeoutError as e:
        return 1, f"Camera switch is busy\n{e}"
    except OSError as e:
        return 1, f"Camera switch failed\n{RUN_DIR}: {e.strerror or e}"
    try:
        if verb == "enforce":
            # Read under the lock: an `on` that was running when udev queued
            # this has taken the switch back by now.
            if not host.switch_is_off():
                return 0, None
            report = Report("off")
            turn_off(host, report, host.load_record())
            return (1 if report.failed() else 0), None
        record = host.load_record()
        if verb == "toggle":
            verb = "on" if host.switch_is_off() else "off"
            # Without the udev rule, nothing turned off a camera that came up
            # since the switch was set (a reboot, a hotplug), so the switch
            # file no longer says what is on: the key goes by what is live.
            if verb == "on" and not host.exists(UDEV_RULE) \
                    and any(c.nodes for c in discover(host, record)):
                verb = "off"
        host.log(f"turning cameras {verb}" + (f" for uid {requested}" if requested else ""))
        report = Report(verb)
        # The position first: a camera that appears meanwhile meets the new one.
        try:
            host.set_switch(verb == "off")
        except OSError as e:
            host.log(f"could not set {SWITCH_FILE}: {e}", error=True)
            report.notes.append(f"The switch position could not be kept ({e.strerror or e}); "
                                "the cameras were switched all the same")
            report.trouble = True
        if verb == "off":
            report.enforced = host.exists(UDEV_RULE)
            turn_off(host, report, record)
            if not report.enforced:
                report.notes.append("A camera that appears later stays on: the udev rule is not installed")
        else:
            turn_on(host, report, record)
        return (1 if report.failed() else 0), summary(report)
    finally:
        os.close(lock)


def main(argv):
    args = [a for a in argv if a != "--json"]
    as_json = len(args) != len(argv)
    if len(args) > 1 or (args and args[0] not in ("status", "off", "on", "toggle", "enforce")):
        print(USAGE, file=sys.stderr)
        return 2
    verb = args[0] if args else "status"
    if as_json and verb != "status":
        print(USAGE, file=sys.stderr)
        return 2
    host = Host()
    if verb == "status":
        return status(host, as_json)
    if os.geteuid() != 0:
        if verb == "enforce":
            print("camera-switch: enforce is run by udev, as root", file=sys.stderr)
            return 2
        return elevate(verb)
    syslog.openlog("camera-switch", 0, syslog.LOG_DAEMON)
    code, text = act(host, verb, os.environ.get("PKEXEC_UID") or os.environ.get("SUDO_UID"))
    if text:
        print(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
