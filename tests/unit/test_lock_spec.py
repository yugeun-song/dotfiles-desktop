"""Tests for hypr/scripts/lock-spec.py, which hands the Quickshell lock
(quickshell/bar/lock.qml) what hyprlock would draw on each screen: read from
lock-fit.sh's copy of hyprlock.conf, here both a small copy written out and
the repository's hyprlock.conf fitted by lock-fit.sh with a stand-in hyprctl,
so a change to the design that the lock could not read shows here.
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
sys.dont_write_bytecode = True


def load():
    spec = importlib.util.spec_from_file_location("lock_spec", REPO / "hypr/scripts/lock-spec.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


lock_spec = load()

SMALL = """# Written by lock-fit.sh from x at every lock; edit that file instead.
# eDP-1 2880x1800 fit 0.854 wide 0.854
# HDMI-A-1 no mode fit 1.000 wide 1.000

$fit_reference = 2880x1800
$fit_scale = 0.854

background {
    monitor = eDP-1
    path = ~/Pictures/w.png
    blur_passes = 3 # a comment
    brightness = 0.60
}

label {
    monitor = eDP-1
    text = cmd[update:60000] date +"%a, %-d %b"
    color = rgba(ecf0c1ff)
    font_size = 32
    shadow_passes = 3
    shadow_color = rgba(000000a6)
    position = 0, 325
}

label {
    monitor = eDP-1
    text = $TIME
    color = rgba(282c4280)
    font_size = 107
    position = 0, 233
}

image {
    monitor = eDP-1
    # fit: even
    reload_cmd = $media card 282c42,ffffff1a,ffffff33
    size = 221
    position = 0, -61
}

input-field {
    monitor = eDP-1
    size = 444, 82
    font_color = rgba(ecf0c1ff)
    placeholder_text = <span foreground="##ecf0c1">Press to unlock</span>
    position = 0, -275
}

label {
    monitor = HDMI-A-1
    text = $TIME
    font_size = 125
    position = 0, 273
}
"""


class Small(unittest.TestCase):
    def setUp(self):
        self.got = lock_spec.spec(SMALL)
        self.panel = self.got["outputs"]["eDP-1"]

    def test_outputs_and_factors(self):
        self.assertEqual(self.got["reference"], [2880, 1800])
        self.assertEqual(self.got["scale"], 0.854)
        self.assertEqual(self.panel["mode"], [2880, 1800])
        self.assertIsNone(self.got["outputs"]["HDMI-A-1"]["mode"])
        self.assertEqual(self.got["outputs"]["HDMI-A-1"]["time"]["font_size"], 125)

    def test_colours_as_qml_reads_them(self):
        self.assertEqual(self.panel["date"]["color"], "#ffecf0c1")
        self.assertEqual(self.panel["time"]["color"], "#80282c42")
        self.assertEqual(self.panel["date"]["glow"], "#a6000000")
        self.assertEqual(self.panel["date"]["halo"], 3)

    def test_the_parts(self):
        self.assertEqual(self.panel["date"]["format"], "ddd, d MMM")
        self.assertEqual(self.panel["background"]["blur_passes"], 3)
        self.assertEqual(self.panel["background"]["brightness"], 0.6)
        self.assertEqual(self.panel["background"]["path"], os.path.expanduser("~/Pictures/w.png"))
        self.assertEqual(self.panel["card"]["paint"], ["282c42", "ffffff1a", "ffffff33"])
        self.assertTrue(self.panel["card"]["even"])
        self.assertFalse(self.panel["time"]["even"])
        self.assertEqual(self.panel["field"]["placeholder"], "Press to unlock")
        self.assertEqual(self.panel["field"]["size"], [444, 82])
        self.assertEqual(self.panel["time"]["position"], [0, 233])


class Video(unittest.TestCase):
    """A picture with a .video link beside it (wallpaper.sh's) names that
    video; a dangling link or none names nothing."""

    def test_the_link_beside(self):
        with tempfile.TemporaryDirectory() as tmp:
            picture = pathlib.Path(tmp, "current.png")
            picture.write_bytes(b"")
            self.assertEqual(lock_spec.video_beside(str(picture)), "")
            clip = pathlib.Path(tmp, "clip.mp4")
            clip.write_bytes(b"x")
            pathlib.Path(tmp, "current.video").symlink_to(clip)
            self.assertEqual(lock_spec.video_beside(str(picture)), str(clip.resolve()))
            got = lock_spec.spec(SMALL.replace("~/Pictures/w.png", str(picture)))
            self.assertEqual(got["outputs"]["eDP-1"]["background"]["video"], str(clip.resolve()))
            clip.unlink()
            self.assertEqual(lock_spec.video_beside(str(picture)), "")


class Fitted(unittest.TestCase):
    """The repository's design, fitted as lock.sh fits it: every part the
    lock draws is there for a screen with a mode."""

    def test_every_part(self):
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = pathlib.Path(tmp, "bin")
            bin_dir.mkdir()
            hyprctl = bin_dir / "hyprctl"
            hyprctl.write_text('#!/bin/sh\n[ "$*" = "-j monitors all" ] && '
                               "echo '[{\"name\": \"eDP-1\", \"width\": 2880, \"height\": 1800, \"disabled\": false}]'\n")
            hyprctl.chmod(0o755)
            out = pathlib.Path(tmp, "fit.conf")
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ.get('PATH', '/usr/bin')}",
                       FIT_INK_CACHE=str(pathlib.Path(tmp, "fit.ink")), XDG_RUNTIME_DIR=tmp)
            subprocess.run(["bash", str(REPO / "hypr/scripts/lock-fit.sh"), str(REPO / "hypr/hyprlock.conf"), str(out)],
                           env=env, check=True, capture_output=True, timeout=30)
            got = json.loads(subprocess.run([sys.executable, "-I", str(REPO / "hypr/scripts/lock-spec.py"), str(out)],
                                            check=True, capture_output=True, text=True).stdout)
        panel = got["outputs"]["eDP-1"]
        for part in ("background", "island", "lead", "trail", "mark", "date", "time", "weather", "card", "field"):
            self.assertIn(part, panel, part)
        self.assertEqual(panel["mode"], [2880, 1800])
        self.assertTrue(any(o["mode"] is None for o in got["outputs"].values()) or len(got["outputs"]) == 1)


if __name__ == "__main__":
    unittest.main()
