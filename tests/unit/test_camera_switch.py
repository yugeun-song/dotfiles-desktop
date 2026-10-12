"""Tests for camera/camera-switch.py against a model of the kernel's sysfs.

No real device is touched: every path lives under a temporary root, and a
write the kernel would act on (authorized, bind, unbind, drivers_probe, a
platform switch, rmmod, modprobe) is acted on by the model instead. The model
follows what the kernel does; tests/vm/camera.sh checks the same flows
against a real kernel in a virtual machine.

Each hardware layout here is one the switch has to handle without knowing it
in advance: this laptop's composite webcam, an external one with a
microphone, a vendor-class USB camera, a MIPI camera behind an ISP, a driver
that cannot be unbound, a laptop with a firmware camera switch, and devices
that look like cameras but are not.
"""

import contextlib
import importlib.util
import io
import os
import pathlib
import shutil
import sys
import tempfile
import unittest
from unittest import mock

# The script is imported from the tree install.sh copies, and a bytecode
# cache written beside it would go out with the next install.
sys.dont_write_bytecode = True

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "camera/camera-switch.py"


def load():
    spec = importlib.util.spec_from_file_location("camera_switch", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cs = load()

XHCI = "/sys/devices/pci0000:00/0000:00:14.0/usb3"
WEBCAM = XHCI + "/3-5"


class Dev:
    def __init__(self, path, bus, driver, nodes, claims):
        self.path = path
        self.bus = bus
        self.driver = driver
        self.nodes = list(nodes)
        self.claims = list(claims)
        self.made = []
        self.claimer = None


class Kernel(cs.Host):
    """sysfs under a temporary root, and the parts of the kernel that act on
    writes to it."""

    def __init__(self, interface_auth=True, interfaces_obey=True):
        self.tmp = tempfile.mkdtemp(prefix="camera-switch-test-")
        super().__init__(self.tmp)
        self.interface_auth = interface_auth
        self.interfaces_obey = interfaces_obey
        # install.sh's root step, done: the udev rule and the polkit action
        # in the tree, and the system copy taken for root's.
        self.installed = True
        self.put(cs.UDEV_RULE, "# rule")
        self.put(cs.POLKIT_ACTION, "<policyconfig/>")
        self.clock = 0.0
        self.logs = []
        self.ran = []
        self.devs = {}
        self.drivers = {}
        self.loaded = set()
        self.usb_specs = {}
        self.switches = {}
        self.later = []
        self.minor = 0
        for d in ("/sys/class/video4linux", "/run/udev/data", "/sys/module",
                  "/sys/devices/virtual/video4linux", "/sys/devices/platform"):
            self.mk(d)
        for bus in ("usb", "pci", "platform", "i2c", "auxiliary"):
            self.mk(f"/sys/bus/{bus}/devices")
            self.mk(f"/sys/bus/{bus}/drivers")
            self.put(f"/sys/bus/{bus}/drivers_probe", "")

    def cleanup(self):
        shutil.rmtree(self.tmp)

    # Files.

    def mk(self, path):
        os.makedirs(self.at(path), exist_ok=True)

    def put(self, path, value):
        os.makedirs(os.path.dirname(self.at(path)), exist_ok=True)
        with open(self.at(path), "w") as f:
            f.write(value + "\n" if value else "")

    def link(self, path, target):
        os.makedirs(os.path.dirname(self.at(path)), exist_ok=True)
        if os.path.lexists(self.at(path)):
            os.unlink(self.at(path))
        os.symlink(os.path.relpath(self.at(target), os.path.dirname(self.at(path))), self.at(path))

    def rm(self, path):
        p = self.at(path)
        if os.path.islink(p) or os.path.isfile(p):
            os.unlink(p)
        elif os.path.isdir(p):
            shutil.rmtree(p)

    # What the program asks of the host besides files.

    def owned_by_root(self, path):
        return self.installed and path == cs.SYSTEM_COPY

    def now(self):
        return self.clock

    def sleep(self, seconds):
        self.clock += seconds
        due = [job for job in self.later if job[0] <= self.clock]
        self.later = [job for job in self.later if job[0] > self.clock]
        for _, job in due:
            job()

    def log(self, message, error=False):
        self.logs.append(("ERR " if error else "") + message)

    def run(self, argv):
        self.ran.append(list(argv))
        tool, args = argv[0], [a for a in argv[1:] if not a.startswith("-")]
        if tool == "rmmod":
            mod = args[0]
            if mod not in self.loaded:
                return 1, f"rmmod: ERROR: Module {mod} is not currently loaded"
            if self.read(f"/sys/module/{mod}/refcnt") != "0":
                return 1, f"rmmod: ERROR: Module {mod} is in use"
            self.unload(mod)
            return 0, ""
        if tool == "modprobe":
            mod = args[0]
            if mod.startswith("usb:"):
                mods = [self.drivers[(d.bus, d.driver)]["module"] for d in self.devs.values()
                        if d.driver and self.read(d.path + "/modalias") == mod]
                if not mods:
                    return 1, ""
                mod = mods[0]
            self.load(mod)
            return 0, ""
        return 127, tool + " is not installed"

    # Drivers and modules.

    def driver(self, bus, name, module=None, unbind=True):
        self.drivers[(bus, name)] = {"module": module, "unbind": unbind}
        if module is None or module in self.loaded:
            self.driver_dir(bus, name)
        else:
            self.load(module)

    def driver_dir(self, bus, name):
        info = self.drivers[(bus, name)]
        d = f"/sys/bus/{bus}/drivers/{name}"
        self.put(d + "/bind", "")
        self.put(d + "/uevent", "")
        if info["unbind"]:
            self.put(d + "/unbind", "")
        if info["module"]:
            self.link(d + "/module", f"/sys/module/{info['module']}")
            self.link(f"/sys/module/{info['module']}/drivers/{bus}:{name}", d)

    def load(self, mod):
        if mod in self.loaded:
            return
        self.loaded.add(mod)
        self.put(f"/sys/module/{mod}/refcnt", "0")
        self.mk(f"/sys/module/{mod}/holders")
        for (bus, name), info in self.drivers.items():
            if info["module"] == mod:
                self.driver_dir(bus, name)
        for d in list(self.devs.values()):
            if d.driver and self.drivers[(d.bus, d.driver)]["module"] == mod:
                self.bind(d.path)

    def unload(self, mod):
        for (bus, name), info in self.drivers.items():
            if info["module"] != mod:
                continue
            for d in list(self.devs.values()):
                if d.bus == bus and self.exists(d.path + "/driver") \
                        and os.path.basename(self.resolve(d.path + "/driver")) == name:
                    self.unbind(d.path)
            self.rm(f"/sys/bus/{bus}/drivers/{name}")
        self.loaded.discard(mod)
        self.rm(f"/sys/module/{mod}")

    def ready(self, bus, name):
        info = self.drivers.get((bus, name))
        return info is not None and (info["module"] is None or info["module"] in self.loaded)

    # Devices.

    def device(self, path, bus, attrs=None, driver=None, nodes=(), claims=()):
        self.mk(path)
        for key, value in (attrs or {}).items():
            self.put(f"{path}/{key}", value)
        self.link(path + "/subsystem", f"/sys/bus/{bus}")
        self.link(f"/sys/bus/{bus}/devices/{os.path.basename(path)}", path)
        self.devs[path] = Dev(path, bus, driver, nodes, claims)
        return path

    def remove(self, path):
        for p in sorted((p for p in self.devs if cs.under(p, path)), reverse=True):
            self.unbind(p)
            d = self.devs.pop(p)
            self.rm(f"/sys/bus/{d.bus}/devices/{os.path.basename(p)}")
        self.rm(path)

    def bind(self, path):
        d = self.devs[path]
        if d.driver is None or self.exists(path + "/driver") or not self.ready(d.bus, d.driver):
            return False
        if self.read(path + "/authorized") == "0":
            return False
        drv = f"/sys/bus/{d.bus}/drivers/{d.driver}"
        self.link(path + "/driver", drv)
        self.link(f"{drv}/{os.path.basename(path)}", path)
        for label, caps in d.nodes:
            d.made.append(self.node(path, label, caps))
        for c in d.claims:
            if c in self.devs and not self.exists(c + "/driver") and self.read(c + "/authorized") != "0":
                self.link(c + "/driver", drv)
                self.link(f"{drv}/{os.path.basename(c)}", c)
                self.devs[c].claimer = path
        return True

    def unbind(self, path):
        d = self.devs.get(path)
        if d is None or not self.exists(path + "/driver"):
            return
        drv = self.resolve(path + "/driver")
        self.rm(path + "/driver")
        self.rm(f"{drv}/{os.path.basename(path)}")
        if d.claimer:
            # A claimed streaming interface lets go; the nodes are its claimer's.
            d.claimer = None
            return
        for name in d.made:
            self.drop_node(name)
        d.made = []
        for c in d.claims:
            if c in self.devs and self.devs[c].claimer == path:
                self.unbind(c)

    def node(self, owner, label, caps):
        """caps None: udev has no record of the node yet; False: a record
        without capabilities, as when v4l_id could not ask."""
        n = self.minor
        self.minor += 1
        name = f"video{n}"
        d = f"{owner}/video4linux/{name}"
        self.put(d + "/dev", f"81:{n}")
        self.put(d + "/name", label)
        self.link(d + "/device", owner)
        self.link(f"/sys/class/video4linux/{name}", d)
        if caps is False:
            self.put(f"/run/udev/data/c81:{n}", "E:ID_PATH=platform-unknown")
        elif caps is not None:
            self.put(f"/run/udev/data/c81:{n}", f"E:ID_V4L_CAPABILITIES={caps}")
        return name

    def drop_node(self, name):
        target = self.resolve(f"/sys/class/video4linux/{name}")
        self.rm(f"/sys/class/video4linux/{name}")
        self.rm(target)
        self.rm(f"/run/udev/data/c81:{name[len('video'):]}")

    def virtual_node(self, label, caps):
        n = self.minor
        self.minor += 1
        d = f"/sys/devices/virtual/video4linux/video{n}"
        self.put(d + "/dev", f"81:{n}")
        self.put(d + "/name", label)
        self.link(f"/sys/class/video4linux/video{n}", d)
        self.put(f"/run/udev/data/c81:{n}", f"E:ID_V4L_CAPABILITIES={caps}")

    def subdev(self, owner, n):
        d = f"{owner}/video4linux/v4l-subdev{n}"
        self.put(d + "/name", "sensor")
        self.link(d + "/device", owner)
        self.link(f"/sys/class/video4linux/v4l-subdev{n}", d)

    # USB.

    def usb(self, port, vid, pid, product, interfaces, serial=""):
        """interfaces: (class, subclass, driver, nodes, numbers claimed on bind)."""
        path = f"{XHCI}/{port}"
        self.device(path, "usb", {"idVendor": vid, "idProduct": pid, "product": product,
                                  "serial": serial, "authorized": "1", "bDeviceClass": "ef"})
        self.usb_specs[path] = (vid, pid, interfaces)
        self.configure(path)
        return path

    def configure(self, path):
        port = os.path.basename(path)
        vid, pid, interfaces = self.usb_specs[path]
        made = []
        for number, (cls, sub, driver, nodes, claims) in enumerate(interfaces):
            attrs = {"bInterfaceClass": cls, "bInterfaceSubClass": sub,
                     "bInterfaceNumber": f"{number:02x}",
                     "modalias": f"usb:v{vid.upper()}p{pid.upper()}ic{cls.upper()}isc{sub.upper()}"}
            if self.interface_auth:
                attrs["authorized"] = "1"
            made.append(self.device(f"{path}/{port}:1.{number}", "usb", attrs, driver, nodes,
                                    [f"{path}/{port}:1.{c}" for c in claims]))
        for p in made:
            self.bind(p)

    def unconfigure(self, path):
        for p in [p for p in self.devs if p.startswith(path + "/")]:
            if p in self.devs:
                self.remove(p)

    def write(self, path, value):
        if not self.exists(path):
            raise FileNotFoundError(2, "No such file or directory", path)
        # The same attribute is reached through /sys/bus/*/devices links.
        parent, leaf = self.resolve(os.path.dirname(path)), os.path.basename(path)
        path = f"{parent}/{leaf}"
        if leaf == "authorized" and parent in self.devs:
            if self.exists(parent + "/bInterfaceClass"):
                self.put(path, value)
                if value == "0" and self.interfaces_obey:
                    self.unbind(parent)
                return
            old = self.read(path)
            self.put(path, value)
            if value == "0" and old != "0":
                self.unconfigure(parent)
            elif value == "1" and old == "0":
                self.configure(parent)
            return
        if leaf == "drivers_probe":
            bus = parent.split("/")[3]
            dev = self.by_name(bus, value)
            if dev is None:
                raise OSError(19, "No such device")
            self.bind(dev.path)
            return
        if leaf in ("bind", "unbind") and "/drivers/" in parent:
            dev = self.by_name(parent.split("/")[3], value)
            if dev is None:
                raise OSError(19, "No such device")
            if leaf == "unbind":
                self.unbind(dev.path)
            elif dev.driver != os.path.basename(parent) or not self.bind(dev.path):
                raise OSError(19, "No such device")
            return
        if path in self.switches:
            self.flip(path, value)
            return
        self.put(path, value)

    def by_name(self, bus, name):
        for d in self.devs.values():
            if d.bus == bus and os.path.basename(d.path) == name:
                return d
        return None

    # Platform switches.

    def platform_switch(self, device, attribute, camera, off="0", on="1", works=True, takes=True):
        """camera: a function that plugs in the camera the switch controls.
        works: the camera leaves the bus when it is off; takes: the value
        written reads back (eeepc-laptop's write succeeds when the firmware
        call behind it failed)."""
        path = self.device(f"/sys/devices/platform/{device}", "platform", {attribute: on})
        attr = f"{path}/{attribute}"
        self.switches[attr] = {"camera": camera, "off": off, "on": on, "works": works,
                               "takes": takes, "path": camera()}
        return attr

    def flip(self, attr, value):
        sw = self.switches[attr]
        if not sw["takes"]:
            return
        self.put(attr, value)
        if not sw["works"]:
            return
        # The module leaves the bus a moment after the firmware cuts it, and
        # comes back after a full enumeration.
        if value == sw["off"]:
            self.later.append((self.clock + 0.3, lambda: self.remove(sw["path"])))
        else:
            self.later.append((self.clock + 1.0, lambda: sw.__setitem__("path", sw["camera"]())))


def laptop_webcam(k):
    """This laptop's module: an RGB and an IR camera, each a control and a
    streaming interface, then a HID presence sensor and a firmware updater."""
    k.driver("usb", "uvcvideo", "uvcvideo")
    k.driver("usb", "usbhid", "usbhid")
    return k.usb("3-5", "3277", "0059", "ASUS FHD webcam", [
        ("0e", "01", "uvcvideo", [("ASUS FHD webcam: ASUS FHD webca", ":capture:"),
                                  ("ASUS FHD webcam: ASUS FHD webca", ":")], [1]),
        ("0e", "02", None, [], []),
        ("0e", "01", "uvcvideo", [("ASUS FHD webcam: ASUS IR camera", ":capture:"),
                                  ("ASUS FHD webcam: ASUS IR camera", ":")], [3]),
        ("0e", "02", None, [], []),
        ("03", "00", "usbhid", [], []),
        ("fe", "01", None, [], []),
    ], serial="200901010001")


def external_webcam(k, port="3-2"):
    k.driver("usb", "uvcvideo", "uvcvideo")
    k.driver("usb", "snd-usb-audio", "snd_usb_audio")
    return k.usb(port, "046d", "085e", "Logitech BRIO", [
        ("0e", "01", "uvcvideo", [("Logitech BRIO", ":capture:"), ("Logitech BRIO", ":")], [1]),
        ("0e", "02", None, [], []),
        ("01", "01", "snd-usb-audio", [], [3]),
        ("01", "02", None, [], []),
    ])


def mipi_camera(k):
    """An Intel IPU6: capture nodes on the ISYS auxiliary device, the sensor
    on I2C with only a subdevice node."""
    k.driver("pci", "intel-ipu6", "intel_ipu6")
    k.driver("auxiliary", "intel_ipu6.isys", "intel_ipu6_isys")
    k.driver("i2c", "ov02c10", "ov02c10")
    pci = k.device("/sys/devices/pci0000:00/0000:00:05.0", "pci", {"vendor": "0x8086"}, "intel-ipu6")
    k.bind(pci)
    isys = k.device(pci + "/intel_ipu6.isys.40", "auxiliary", {}, "intel_ipu6.isys",
                    [("Intel IPU6 ISYS Capture 0", ":capture:"), ("Intel IPU6 ISYS Capture 1", ":capture:")])
    k.bind(isys)
    sensor = k.device("/sys/devices/pci0000:00/0000:00:15.1/i2c_designware.1/i2c-1/i2c-OVTI02C1:00",
                      "i2c", {}, "ov02c10")
    k.bind(sensor)
    k.subdev(sensor, 0)
    return isys


class Case(unittest.TestCase):
    def setUp(self):
        self.k = Kernel()
        self.addCleanup(self.k.cleanup)

    def act(self, verb, k=None):
        return cs.act(k or self.k, verb)

    def capture_nodes(self, k=None):
        k = k or self.k
        return [n for n in k.listdir(cs.V4L) if n.startswith("video") and cs.captures(k, n)]

    def auth(self, path, k=None):
        return (k or self.k).read(path + "/authorized")

    def driver_of(self, path, k=None):
        k = k or self.k
        return os.path.basename(k.resolve(path + "/driver")) if k.exists(path + "/driver") else None


class Discovery(Case):
    def test_laptop_webcam_is_one_camera_with_two_capture_nodes(self):
        laptop_webcam(self.k)
        cams = cs.discover(self.k)
        self.assertEqual([c.device for c in cams], [WEBCAM])
        self.assertEqual(cams[0].name, "ASUS FHD webcam")
        self.assertEqual(cams[0].ident, "3277:0059")
        self.assertEqual(cams[0].nodes, ["video0", "video2"])
        self.assertEqual(cams[0].interfaces, ["3-5:1.0", "3-5:1.2", "3-5:1.1", "3-5:1.3"])

    def test_what_is_not_a_camera(self):
        self.k.virtual_node("Dummy video device (0x0000)", ":capture:video_output:")
        self.k.driver("platform", "rkvdec")
        self.k.bind(self.k.device("/sys/devices/platform/rkvdec", "platform", {}, "rkvdec", [("rkvdec", ":")]))
        self.k.driver("pci", "cx23885")
        self.k.bind(self.k.device("/sys/devices/pci0000:00/0000:00:1c.0/0000:03:00.0", "pci", {}, "cx23885",
                                  [("Hauppauge WinTV", ":capture:tuner:audio:")]))
        self.k.driver("platform", "uvc-gadget")
        self.k.bind(self.k.device("/sys/devices/platform/gadget.0", "platform", {}, "uvc-gadget",
                                  [("uvc gadget", ":video_output:")]))
        self.assertEqual(cs.discover(self.k), [])

    def test_mipi_camera_is_the_isp_not_the_sensor(self):
        isys = mipi_camera(self.k)
        cams = cs.discover(self.k)
        self.assertEqual([(c.device, c.bus) for c in cams], [(isys, "auxiliary")])
        self.assertEqual(cams[0].name, "Intel IPU6 ISYS Capture 0")

    def test_capabilities_v4l_id_could_not_read_count_as_a_camera(self):
        self.k.driver("platform", "mystery")
        dev = self.k.device("/sys/devices/platform/mystery.0", "platform", {}, "mystery", [("Mystery", False)])
        self.k.bind(dev)
        self.assertEqual([c.device for c in cs.discover(self.k)], [dev])

    def test_node_udev_has_not_recorded_waits_for_its_own_event(self):
        self.k.driver("platform", "late")
        dev = self.k.device("/sys/devices/platform/late.0", "platform", {}, "late", [("Late", None)])
        self.k.bind(dev)
        self.assertEqual(cs.discover(self.k), [])
        # Yet it keeps a camera from counting as off.
        self.assertEqual(cs.live_nodes(self.k, dev), ["video0"])

    def test_without_udev_every_capture_node_counts(self):
        self.k.driver("platform", "rkvdec")
        self.k.bind(self.k.device("/sys/devices/platform/rkvdec", "platform", {}, "rkvdec", [("rkvdec", ":")]))
        self.k.rm("/run/udev/data")
        self.assertEqual(len(cs.discover(self.k)), 1)

    def test_camera_without_driver_is_found_by_its_interfaces(self):
        external_webcam(self.k)
        self.k.run(["rmmod", "uvcvideo"])
        cams = cs.discover(self.k)
        self.assertEqual(len(cams), 1)
        self.assertEqual(cams[0].nodes, [])
        self.assertEqual(sorted(cams[0].interfaces), ["3-2:1.0", "3-2:1.1"])


class LaptopWebcam(Case):
    def setUp(self):
        super().setUp()
        laptop_webcam(self.k)

    def test_off_deauthorizes_only_the_video_interfaces(self):
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertEqual(text.splitlines()[0], "Cameras off")
        self.assertIn("ASUS FHD webcam (USB 3277:0059): off, USB video interfaces deauthorized", text)
        for n in range(4):
            self.assertEqual(self.auth(f"{WEBCAM}/3-5:1.{n}"), "0")
            self.assertIsNone(self.driver_of(f"{WEBCAM}/3-5:1.{n}"))
        # The presence sensor and the firmware interface are not cameras.
        self.assertEqual(self.auth(f"{WEBCAM}/3-5:1.4"), "1")
        self.assertEqual(self.driver_of(f"{WEBCAM}/3-5:1.4"), "usbhid")
        self.assertEqual(self.auth(WEBCAM), "1")
        self.assertEqual(self.capture_nodes(), [])
        self.assertTrue(self.k.switch_is_off())
        self.assertEqual([e["method"] for e in self.k.load_record()], ["usb-interface"])

    def test_control_interfaces_go_first(self):
        order = []
        real = self.k.write

        def spy(path, value):
            if path.endswith("/authorized"):
                order.append(os.path.basename(os.path.dirname(path)))
            real(path, value)

        self.k.write = spy
        self.act("off")
        self.assertEqual(order, ["3-5:1.0", "3-5:1.2", "3-5:1.1", "3-5:1.3"])

    def test_on_brings_both_cameras_back(self):
        self.act("off")
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(text, "Cameras on\nASUS FHD webcam (USB 3277:0059): on")
        for n in range(4):
            self.assertEqual(self.auth(f"{WEBCAM}/3-5:1.{n}"), "1")
        self.assertEqual(self.driver_of(f"{WEBCAM}/3-5:1.0"), "uvcvideo")
        self.assertEqual(self.driver_of(f"{WEBCAM}/3-5:1.1"), "uvcvideo")
        self.assertEqual(len(self.capture_nodes()), 2)
        self.assertFalse(self.k.switch_is_off())
        self.assertEqual(self.k.load_record(), [])

    def test_toggle_follows_the_switch(self):
        self.assertEqual(self.act("toggle")[1].splitlines()[0], "Cameras off")
        self.assertEqual(self.act("toggle")[1].splitlines()[0], "Cameras on")
        self.assertEqual(self.act("toggle")[1].splitlines()[0], "Cameras off")

    def test_off_twice_changes_nothing_more(self):
        self.act("off")
        writes = []
        real = self.k.write
        self.k.write = lambda p, v: (writes.append(p), real(p, v))
        code, text = self.act("off")
        self.assertEqual(code, 0)
        self.assertEqual(writes, [])
        self.assertEqual(len(self.k.load_record()), 1)

    def test_status_reports_how_it_is_held(self):
        self.act("off")
        with mock.patch.object(cs, "Host", lambda: self.k), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cs.main(["status"]), 0)
        self.assertEqual(out.getvalue().splitlines(), [
            "switch   off; a camera that appears is turned off too",
            "off      ASUS FHD webcam (USB 3277:0059): USB video interfaces deauthorized",
        ])

    def test_lost_record_still_lets_on_find_the_interfaces(self):
        self.act("off")
        self.k.rm(cs.RECORD_FILE)
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(len(self.capture_nodes()), 2)


class Fallbacks(Case):
    def test_old_kernel_deauthorizes_the_whole_device(self):
        k = Kernel(interface_auth=False)
        self.addCleanup(k.cleanup)
        laptop_webcam(k)
        code, text = self.act("off", k)
        self.assertEqual(code, 0, text)
        self.assertIn("USB device deauthorized", text)
        self.assertEqual(self.auth(WEBCAM, k), "0")
        self.assertFalse(k.exists(WEBCAM + "/3-5:1.0"))
        self.assertEqual(self.capture_nodes(k), [])
        # Named from the record while it has no interfaces left to name it by.
        self.assertEqual(cs.discover(k, k.load_record())[0].name, "ASUS FHD webcam")
        code, text = self.act("on", k)
        self.assertEqual(code, 0, text)
        self.assertEqual(self.auth(WEBCAM, k), "1")
        self.assertEqual(len(self.capture_nodes(k)), 2)

    def test_interfaces_that_do_not_let_go_escalate_to_the_device(self):
        k = Kernel(interfaces_obey=False)
        self.addCleanup(k.cleanup)
        laptop_webcam(k)
        code, text = self.act("off", k)
        self.assertEqual(code, 0, text)
        self.assertEqual([e["method"] for e in k.load_record()], ["usb-interface", "usb-device"])
        self.assertEqual(self.capture_nodes(k), [])
        code, text = self.act("on", k)
        self.assertEqual(code, 0, text)
        self.assertEqual(len(self.capture_nodes(k)), 2)
        self.assertEqual(k.load_record(), [])

    def test_external_webcam_keeps_its_microphone(self):
        cam = external_webcam(self.k)
        self.act("off")
        self.assertEqual(self.auth(cam + "/3-2:1.0"), "0")
        self.assertEqual(self.auth(cam + "/3-2:1.2"), "1")
        self.assertEqual(self.driver_of(cam + "/3-2:1.2"), "snd-usb-audio")
        self.assertEqual(self.driver_of(cam + "/3-2:1.3"), "snd-usb-audio")

    def test_vendor_class_camera_found_by_its_node(self):
        self.k.driver("usb", "sonixj", "gspca_sonixj")
        cam = self.k.usb("3-3", "0c45", "6128", "USB camera", [
            ("ff", "ff", "sonixj", [("USB camera", ":capture:")], [])])
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.auth(cam + "/3-3:1.0"), "0")
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.driver_of(cam + "/3-3:1.0"), "sonixj")

    def test_mipi_camera_is_unbound_and_bound_again(self):
        isys = mipi_camera(self.k)
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertIn("Intel IPU6 ISYS Capture 0 (auxiliary): off, driver unbound", text)
        self.assertIsNone(self.driver_of(isys))
        self.assertEqual(self.driver_of("/sys/devices/pci0000:00/0000:00:05.0"), "intel-ipu6")
        self.assertEqual(self.capture_nodes(), [])
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.driver_of(isys), "intel_ipu6.isys")
        self.assertEqual(len(self.capture_nodes()), 2)

    def test_driver_without_unbind_has_its_module_unloaded(self):
        self.k.driver("platform", "socam", "socam", unbind=False)
        dev = self.k.device("/sys/devices/platform/socam.0", "platform", {}, "socam", [("SoC camera", ":capture:")])
        self.k.bind(dev)
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertIn("driver module unloaded", text)
        self.assertIn(["rmmod", "socam"], self.k.ran)
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.driver_of(dev), "socam")

    def test_module_in_use_leaves_the_camera_reported_on(self):
        self.k.driver("platform", "socam", "socam", unbind=False)
        dev = self.k.device("/sys/devices/platform/socam.0", "platform", {}, "socam", [("SoC camera", ":capture:")])
        self.k.bind(dev)
        self.k.put("/sys/module/socam/refcnt", "1")
        code, text = self.act("off")
        self.assertEqual(code, 1)
        self.assertEqual(text.splitlines(), [
            "1 camera still on",
            "SoC camera (platform): still on, unbind: socam offers no unbind; "
            "module: socam is in use by an open program",
        ])
        self.assertTrue(any(line.startswith("ERR SoC camera") for line in self.k.logs))

    def test_module_that_drives_something_else_stays(self):
        self.k.driver("platform", "socam", "socam", unbind=False)
        dev = self.k.device("/sys/devices/platform/socam.0", "platform", {}, "socam", [("SoC camera", ":capture:")])
        self.k.bind(dev)
        self.k.bind(self.k.device("/sys/devices/platform/socam-codec", "platform", {}, "socam", [("codec", ":")]))
        code, text = self.act("off")
        self.assertEqual(code, 1)
        self.assertIn("module: socam also drives socam-codec", text)

    def test_replaced_device_is_not_touched_by_on(self):
        k = Kernel(interface_auth=False)
        self.addCleanup(k.cleanup)
        laptop_webcam(k)
        self.act("off", k)
        k.remove(WEBCAM)
        k.usb("3-5", "1234", "5678", "Other device", [("08", "06", None, [], [])])
        k.write(WEBCAM + "/authorized", "0")
        self.act("on", k)
        self.assertEqual(self.auth(WEBCAM, k), "0")


class PowerSwitches(Case):
    def test_firmware_switch_takes_the_camera_off_the_bus(self):
        attr = self.k.platform_switch("VPC2004:00", "camera_power", lambda: laptop_webcam(self.k))
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.k.read(attr), "0")
        self.assertFalse(self.k.exists(WEBCAM))
        self.assertEqual(self.k.load_record(), [])
        self.assertEqual(text, "Cameras off\nNo camera found; one that appears is turned off")
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.k.read(attr), "1")
        self.assertEqual(text, "Cameras on\nASUS FHD webcam (USB 3277:0059): on")

    def test_switch_that_does_nothing_is_backed_by_the_interfaces(self):
        attr = self.k.platform_switch("asus-nb-wmi", "camera", lambda: laptop_webcam(self.k), works=False)
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.k.read(attr), "0")
        self.assertEqual([e["method"] for e in self.k.load_record()], ["usb-interface"])
        self.assertLessEqual(self.k.clock, cs.SWITCH_SETTLE + cs.POLL)
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(self.k.read(attr), "1")
        self.assertEqual(len(self.capture_nodes()), 2)

    def test_switch_the_firmware_ignores_is_reported(self):
        self.k.platform_switch("eeepc", "camera", lambda: laptop_webcam(self.k), takes=False)
        code, text = self.act("off")
        self.assertEqual(code, 1)
        self.assertIn("/sys/bus/platform/devices/eeepc/camera: the firmware did not take it", text)
        # The camera itself is still turned off.
        self.assertEqual(self.capture_nodes(), [])

    def test_strings_are_written_as_the_driver_reads_them(self):
        attr = self.k.platform_switch("msi-ec", "webcam", lambda: laptop_webcam(self.k), off="off", on="on")
        self.act("off")
        self.assertEqual(self.k.read(attr), "off")
        self.act("on")
        self.assertEqual(self.k.read(attr), "on")

    def test_unrelated_attributes_are_left_alone(self):
        self.k.device("/sys/devices/platform/thinkpad_acpi", "platform", {"camera": "1"})
        self.assertEqual(cs.power_switches(self.k), [])


class Enforce(Case):
    def test_nothing_while_the_switch_is_on(self):
        laptop_webcam(self.k)
        self.assertEqual(self.act("enforce"), (0, None))
        self.assertEqual(len(self.capture_nodes()), 2)

    def test_camera_plugged_in_while_off_goes_off(self):
        laptop_webcam(self.k)
        self.act("off")
        cam = external_webcam(self.k)
        self.assertEqual(len(self.capture_nodes()), 1)
        self.assertEqual(self.act("enforce"), (0, None))
        self.assertEqual(self.capture_nodes(), [])
        self.assertEqual(self.auth(cam + "/3-2:1.0"), "0")
        code, text = self.act("on")
        self.assertEqual(code, 0, text)
        self.assertEqual(len(self.capture_nodes()), 3)

    def test_no_camera(self):
        self.assertEqual(self.act("off"), (0, "Cameras off\nNo camera found; one that appears is turned off"))
        self.assertEqual(self.act("on"), (0, "Cameras on\nNo camera found"))


class WithoutTheRootStep(Case):
    """install.sh's root step not done, or not all of it: the switch still
    works, and says what each missing part costs."""

    def test_status_names_what_is_missing(self):
        laptop_webcam(self.k)
        self.k.installed = False
        self.k.rm(cs.UDEV_RULE)
        gaps = cs.missing_setup(self.k)
        self.assertEqual(len(gaps), 2)
        self.assertIn("asks for an administrator password", gaps[0])
        self.assertIn("udev rule is not installed", gaps[1])

    def test_installed_copy_without_the_action_asks_for_a_password(self):
        self.k.rm(cs.POLKIT_ACTION)
        self.assertEqual(cs.missing_setup(self.k),
                         ["the polkit action is not installed, so turning cameras off or on asks "
                          "for an administrator password"])

    def test_nothing_missing(self):
        self.assertEqual(cs.missing_setup(self.k), [])

    def test_off_says_a_camera_appearing_later_stays_on(self):
        self.k.rm(cs.UDEV_RULE)
        laptop_webcam(self.k)
        code, text = self.act("off")
        self.assertEqual(code, 0, text)
        self.assertEqual(text.splitlines()[-1], "A camera that appears later stays on: the udev rule is not installed")
        self.assertEqual(self.capture_nodes(), [])

    def test_no_camera_promises_nothing_without_the_rule(self):
        self.k.rm(cs.UDEV_RULE)
        self.assertEqual(self.act("off")[1].splitlines()[:2],
                         ["Cameras off", "No camera found"])

    def test_toggle_goes_by_what_is_live_without_the_rule(self):
        # A reboot left the switch off, and with no rule the webcam came up on.
        self.k.rm(cs.UDEV_RULE)
        self.k.set_switch(True)
        laptop_webcam(self.k)
        code, text = self.act("toggle")
        self.assertEqual(text.splitlines()[0], "Cameras off")
        self.assertEqual(self.capture_nodes(), [])
        self.assertEqual(self.act("toggle")[1].splitlines()[0], "Cameras on")

    def test_toggle_flips_the_switch_with_the_rule(self):
        # With the rule, a live camera under an off switch is one nothing
        # reaches; the key must still turn the switch, and the rest, on.
        self.k.set_switch(True)
        laptop_webcam(self.k)
        self.assertEqual(self.act("toggle")[1].splitlines()[0], "Cameras on")

    def test_switch_file_that_cannot_be_written(self):
        laptop_webcam(self.k)
        self.k.put("/var/lib/camera-switch", "a file where the directory should be")
        code, text = self.act("off")
        self.assertEqual(code, 1)
        self.assertEqual(self.capture_nodes(), [])
        self.assertIn("The switch position could not be kept", text)

    def test_record_that_cannot_be_written(self):
        laptop_webcam(self.k)
        real = self.k.save_record

        def broken(record):
            raise PermissionError(13, "Permission denied")

        self.k.save_record = broken
        code, text = self.act("off")
        self.assertEqual(code, 1)
        self.assertEqual(self.capture_nodes(), [])
        self.assertIn("What was done could not be recorded (Permission denied)", text)
        # Interfaces turned off are found again without the record.
        self.k.save_record = real
        self.assertEqual(self.act("on")[0], 0)
        self.assertEqual(len(self.capture_nodes()), 2)


class CommandLine(Case):
    def main(self, argv, euid=1000):
        with mock.patch.object(cs, "Host", lambda: self.k), \
                mock.patch.object(cs.os, "geteuid", return_value=euid), \
                mock.patch.object(cs.syslog, "openlog"), \
                contextlib.redirect_stdout(io.StringIO()) as out, \
                contextlib.redirect_stderr(io.StringIO()) as err:
            code = cs.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_usage(self):
        for argv in (["bogus"], ["off", "on"], ["off", "--json"], ["--json", "toggle"]):
            self.assertEqual(self.main(argv)[0], 2, argv)

    def test_status_is_the_default_and_needs_no_root(self):
        laptop_webcam(self.k)
        code, out, _ = self.main([])
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[1], "on       ASUS FHD webcam (USB 3277:0059): video0, video2")

    def test_status_json(self):
        laptop_webcam(self.k)
        _, out, _ = self.main(["status", "--json"])
        self.assertIn('"state": "on"', out)
        self.assertIn('"switch": "on"', out)

    def elevated(self, argv, tools, results=(0,), tty=False):
        """main() as the user, with only `tools` installed and each command
        run returning the next of `results`."""
        codes = list(results)

        def run(cmd, **kwargs):
            done = mock.Mock()
            done.returncode = codes.pop(0) if codes else 0
            return done

        which = lambda name, path=None: tools.get(name)
        with mock.patch.object(cs.shutil, "which", side_effect=which), \
                mock.patch.object(cs.subprocess, "run", side_effect=run) as ran, \
                mock.patch.object(cs.sys.stdin, "isatty", return_value=tty):
            code, out, _ = self.main(argv)
        return code, out, [c.args[0] for c in ran.call_args_list]

    def test_pkexec_goes_into_the_installed_copy(self):
        code, _, ran = self.elevated(["toggle"], {"pkexec": "/usr/bin/pkexec"})
        self.assertEqual(code, 0)
        self.assertEqual(ran, [["/usr/bin/pkexec", cs.SYSTEM_COPY, "toggle"]])

    def test_without_the_installed_copy_pkexec_runs_this_one(self):
        self.k.installed = False
        _, _, ran = self.elevated(["off"], {"pkexec": "/usr/bin/pkexec"})
        self.assertEqual(ran, [["/usr/bin/pkexec", str(SCRIPT), "off"]])

    def test_dialog_dismissed(self):
        code, out, _ = self.elevated(["off"], {"pkexec": "/usr/bin/pkexec"}, results=(126,))
        self.assertEqual(code, 126)
        self.assertEqual(out.splitlines()[0], "Camera switch cancelled")

    def test_refused_by_polkit(self):
        code, out, _ = self.elevated(["off"], {"pkexec": "/usr/bin/pkexec"}, results=(127,))
        self.assertEqual(code, 127)
        self.assertEqual(out.splitlines()[0], "Camera switch not allowed")

    def test_without_pkexec_sudo_asks_on_a_terminal(self):
        _, _, ran = self.elevated(["on"], {"sudo": "/usr/bin/sudo"}, tty=True)
        self.assertEqual(ran, [["/usr/bin/sudo", cs.SYSTEM_COPY, "on"]])

    def test_without_pkexec_a_key_uses_sudo_only_without_a_password(self):
        _, _, ran = self.elevated(["on"], {"sudo": "/usr/bin/sudo"}, results=(0, 0))
        self.assertEqual(ran, [["/usr/bin/sudo", "-n", "true"], ["/usr/bin/sudo", "-n", cs.SYSTEM_COPY, "on"]])
        code, out, ran = self.elevated(["on"], {"sudo": "/usr/bin/sudo"}, results=(1,))
        self.assertEqual(code, 3)
        self.assertEqual(ran, [["/usr/bin/sudo", "-n", "true"]])
        self.assertEqual(out.splitlines()[0], "Camera switch needs root")

    def test_without_pkexec_or_sudo(self):
        code, out, _ = self.elevated(["off"], {})
        self.assertEqual(code, 3)
        self.assertEqual(out.splitlines()[0], "Camera switch needs root")

    def test_enforce_is_not_elevated(self):
        self.assertEqual(self.main(["enforce"])[0], 2)

    def test_root_prints_the_summary(self):
        laptop_webcam(self.k)
        code, out, _ = self.main(["off"], euid=0)
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[0], "Cameras off")

    def test_unreadable_record_is_ignored(self):
        self.k.put(cs.RECORD_FILE, "{not json")
        self.assertEqual(self.k.load_record(), [])
        self.k.put(cs.RECORD_FILE, '{"version": 1, "done": [{"method": "usb-interface", "device": "/x", "bus": "usb"}]}')
        self.assertEqual(self.k.load_record(), [])


if __name__ == "__main__":
    unittest.main()
