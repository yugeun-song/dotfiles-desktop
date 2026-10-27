"""Tests for quickshell/bar/scripts/share-apps.py, which names the programs
sharing the screen from PipeWire's graph: graphs written here in pw-dump's
shape, and the script run whole against stand-ins for pw-dump and hyprctl
put first on PATH. Nothing here reads the machine's PipeWire or Hyprland.
"""

import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = REPO / "quickshell/bar/scripts/share-apps.py"
# No cache beside the scripts loaded here: install.sh mirrors their directory
# whole.
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("share_apps", SCRIPT)
share_apps = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(share_apps)


def client(cid, name, binary, pid):
    return {"id": cid, "type": "PipeWire:Interface:Client", "info": {"props": {
        "application.name": name, "application.process.binary": binary, "application.process.id": pid}}}


def node(nid, media_class, client_id, **extra):
    props = {"media.class": media_class, "client.id": client_id}
    props.update({k.replace("_", "."): v for k, v in extra.items()})
    return {"id": nid, "type": "PipeWire:Interface:Node", "info": {"props": props}}


def link(lid, out, into):
    return {"id": lid, "type": "PipeWire:Interface:Link", "info": {"output-node-id": out, "input-node-id": into}}


# The portal's screen (100) and the camera (102); the browser takes the
# screen, Zoom the camera.
GRAPH = [
    client(40, "Google Chrome", "chrome", 2001),
    client(41, "xdg-desktop-portal-hyprland", "xdg-desktop-portal-hyprland", 900),
    client(43, "WirePlumber", "wireplumber", 800),
    client(44, "zoom", "zoom", 3001),
    node(100, "Video/Source", 41, node_name="xdph-streaming-1"),
    node(101, "Stream/Input/Video", 40),
    node(102, "Video/Source", 43, device_id=50, node_name="v4l2_input.camera"),
    node(103, "Stream/Input/Video", 44),
    link(200, 100, 101),
    link(201, 102, 103),
]


# A call: the microphone (110, a device) into Zoom (111); cava (113) records
# the sink's monitor, a port of the sink (112), which is no source.
CALL_GRAPH = [
    client(44, "ZOOM VoiceEngine", "zoom", 3001),
    client(45, "cava", "cava", 3100),
    client(43, "WirePlumber", "wireplumber", 800),
    node(110, "Audio/Source", 43, device_id=60, node_name="alsa_input.mic"),
    node(111, "Stream/Input/Audio", 44),
    node(112, "Audio/Sink", 43, device_id=61, node_name="alsa_output.speakers"),
    node(113, "Stream/Input/Audio", 45),
    link(210, 110, 111),
    link(211, 112, 113),
]


class ShareAppsTest(unittest.TestCase):
    def test_the_program_at_the_microphone_s_far_end(self):
        found = share_apps.sharers(CALL_GRAPH, {3001: "Zoom"}, streams=share_apps.mic_streams)
        self.assertEqual(found, [{"class": "Zoom", "binary": "zoom", "name": "ZOOM VoiceEngine"}])

    def test_a_sink_s_monitor_is_no_microphone(self):
        graph = [o for o in CALL_GRAPH if o["id"] not in (110, 111, 210)]
        self.assertEqual(share_apps.sharers(graph, {}, streams=share_apps.mic_streams), [])

    def test_a_virtual_source_is_a_microphone(self):
        graph = [o for o in CALL_GRAPH if o["id"] != 110] + [node(110, "Audio/Source/Virtual", 43)]
        self.assertEqual(len(share_apps.sharers(graph, {}, streams=share_apps.mic_streams)), 1)

    def test_a_microphone_is_no_screen_nor_a_screen_a_microphone(self):
        self.assertEqual(share_apps.sharers(CALL_GRAPH, {}), [])
        self.assertEqual(share_apps.sharers(GRAPH, {}, streams=share_apps.mic_streams), [])

    def test_the_program_at_the_screen_s_far_end(self):
        found = share_apps.sharers(GRAPH, {1999: "google-chrome"}, {2001: 1999}.get)
        self.assertEqual(found, [{"class": "google-chrome", "binary": "chrome", "name": "Google Chrome"}])

    def test_a_camera_is_no_screen(self):
        graph = [o for o in GRAPH if o["id"] != 200]
        self.assertEqual(share_apps.sharers(graph, {3001: "zoom"}), [])

    def test_the_node_s_own_name_wins_over_its_client_s(self):
        graph = [o for o in GRAPH if o["id"] != 101] + [
            node(101, "Stream/Input/Video", 40, application_name="Discord")]
        found = share_apps.sharers(graph, {})
        self.assertEqual([f["name"] for f in found], ["Discord"])
        self.assertEqual([f["binary"] for f in found], ["chrome"])

    def test_a_program_with_several_streams_named_once(self):
        graph = GRAPH + [node(104, "Stream/Input/Video", 40), link(202, 100, 104)]
        found = share_apps.sharers(graph, {2001: "google-chrome"})
        self.assertEqual([f["class"] for f in found], ["google-chrome"])

    def test_two_programs_sharing_both_named(self):
        graph = GRAPH + [node(105, "Stream/Input/Video", 44), link(203, 100, 105)]
        found = share_apps.sharers(graph, {2001: "google-chrome", 3001: "zoom"})
        self.assertEqual(sorted(f["class"] for f in found), ["google-chrome", "zoom"])

    def test_no_window_in_the_process_line(self):
        found = share_apps.sharers(GRAPH, {}, {2001: 1}.get)
        self.assertEqual(found, [{"class": "", "binary": "chrome", "name": "Google Chrome"}])

    def test_a_loop_in_the_process_line_ends(self):
        self.assertEqual(share_apps.window_class(10, {}, {10: 11, 11: 10}.get), "")

    def test_a_long_process_line_ends(self):
        self.assertEqual(share_apps.window_class(1000, {900: "far"}, lambda pid: pid - 1), "")
        self.assertEqual(share_apps.window_class(1000, {990: "near"}, lambda pid: pid - 1), "near")

    def test_a_link_to_a_node_that_went(self):
        graph = GRAPH + [link(204, 100, 999)]
        self.assertEqual(len(share_apps.sharers(graph, {})), 1)

    def test_an_unreadable_pid(self):
        graph = [o for o in GRAPH if o["id"] != 40] + [client(40, "Firefox", "firefox", "x")]
        self.assertEqual(share_apps.sharers(graph, {}), [{"class": "", "binary": "firefox", "name": "Firefox"}])

    def test_the_parent_after_a_name_with_brackets(self):
        self.assertEqual(share_apps.ppid_in("4242 (a) b) (c) S 77 4242 4242 0 -1"), 77)
        self.assertEqual(share_apps.ppid_in("garbage"), 0)

    def test_this_process_s_parent(self):
        self.assertEqual(share_apps.parent_of(os.getpid()), os.getppid())


class ShareAppsRunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = pathlib.Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    # Python stand-ins, since PATH holds nothing else: the real pw-dump
    # must not be found when its stand-in is left out.
    def stub(self, name, output):
        path = self.bin / name
        data = self.bin / f"{name}.json"
        data.write_text(output)
        path.write_text(f"#!{sys.executable}\nimport sys\nsys.stdout.write(open({str(data)!r}).read())\n")
        path.chmod(0o755)

    def run_script(self, *args):
        env = dict(os.environ, PATH=str(self.bin))
        done = subprocess.run([sys.executable, "-I", "-S", str(SCRIPT), *args], env=env, capture_output=True,
                              text=True, timeout=10, check=False)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    # The stream is this test's process, the window its parent's: the
    # script walks the real /proc from one to the other.
    def browser(self, title):
        graph = [o for o in GRAPH if o["id"] != 40] + [client(40, "Google Chrome", "chrome", os.getpid())]
        self.stub("pw-dump", json.dumps(graph))
        self.stub("hyprctl", json.dumps([{"pid": os.getppid(), "class": "google-chrome", "title": title}]))

    def test_one_line_of_programs(self):
        self.browser("a page")
        self.assertEqual(self.run_script(), [{"class": "google-chrome", "binary": "chrome", "name": "Google Chrome"}])

    def test_titles_are_never_printed(self):
        self.browser("a secret title")
        self.assertNotIn("secret", json.dumps(self.run_script()))

    def test_the_microphone_s_programs_by_flag(self):
        graph = [o for o in CALL_GRAPH if o["id"] != 44] + [client(44, "ZOOM VoiceEngine", "zoom", os.getpid())]
        self.stub("pw-dump", json.dumps(graph))
        self.stub("hyprctl", json.dumps([{"pid": os.getppid(), "class": "Zoom", "title": "Zoom Meeting"}]))
        self.assertEqual(self.run_script("--mic"), [{"class": "Zoom", "binary": "zoom", "name": "ZOOM VoiceEngine"}])
        self.assertEqual(self.run_script(), [])

    def test_nothing_without_pipewire(self):
        self.stub("hyprctl", "[]")
        self.assertEqual(self.run_script(), [])

    def test_nothing_from_garbage(self):
        self.stub("pw-dump", "not json")
        self.stub("hyprctl", "{")
        self.assertEqual(self.run_script(), [])


if __name__ == "__main__":
    unittest.main()
