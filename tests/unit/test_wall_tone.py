"""Tests for quickshell/bar/scripts/wall-tone.py, which reads the desktop's
wallpaper for the bar's tones (services/Appearance.qml): the tone a picture
asks for, the island's fill below the bar, the palettes and the picture's own
colours. The pictures are drawn here; nothing reads the machine's wallpaper.
"""

import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = REPO / "quickshell/bar/scripts/wall-tone.py"
sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("wall_tone", SCRIPT)
wall_tone = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wall_tone)

try:
    from PIL import Image
except ImportError:
    Image = None

SCREENS = ["PANEL:1920:1200:37", "DESK:2560:1440:37"]


@unittest.skipIf(Image is None, "python3-pillow is not installed")
class WallToneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def picture(self, name, colour, below=None, split=0.6):
        im = Image.new("RGB", (2560, 1440), colour)
        if below is not None:
            im.paste(below, (0, round(1440 * split), 2560, 1440))
        path = self.root / name
        im.save(path)
        return path

    def read(self, path, *screens):
        done = subprocess.run([sys.executable, "-I", str(SCRIPT), str(path), *(screens or SCREENS)],
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_a_dark_picture_asks_for_the_black_tone_and_turns_the_island_cream(self):
        got = self.read(self.picture("black.png", (8, 8, 10)))
        self.assertEqual(got["tone"], "dark")
        self.assertEqual({s["island"] for s in got["screens"].values()}, {"#ecf0c1"})

    def test_a_light_picture_asks_for_white_and_keeps_the_island_black(self):
        got = self.read(self.picture("light.png", (236, 232, 224)))
        self.assertEqual(got["tone"], "light")
        self.assertEqual({s["island"] for s in got["screens"].values()}, {"#000000"})

    # The tone is the bar's ground, not the picture's whole: a light sky
    # over a dark field is a light bar.
    def test_the_bars_strip_decides_the_tone(self):
        got = self.read(self.picture("sky.png", (230, 226, 216), below=(12, 12, 16), split=0.5))
        self.assertEqual(got["tone"], "light")
        got = self.read(self.picture("night.png", (12, 12, 16), below=(230, 226, 216), split=0.5))
        self.assertEqual(got["tone"], "dark")

    def test_the_palettes_read_and_take_the_pictures_hue(self):
        got = self.read(self.picture("blue.png", (30, 60, 140), below=(240, 160, 40)))
        for rule in ("match", "opposite"):
            p = got["palettes"][rule]
            bg, fg = wall_tone.lin_of(p["bg"]), wall_tone.lin_of(p["fg"])
            self.assertGreaterEqual(wall_tone.contrast(wall_tone.luminance(bg), wall_tone.luminance(fg)), 7.0, p)
            self.assertRegex(p["accent"], r"^#[0-9a-f]{6}$")
            self.assertGreaterEqual(
                wall_tone.contrast(wall_tone.luminance(wall_tone.lin_of(p["accent"])), wall_tone.luminance(bg)), 3.0, p)
        # The match is the bar's own tone, dark under a dark blue strip.
        self.assertLess(wall_tone.luminance(wall_tone.lin_of(got["palettes"]["match"]["bg"])), wall_tone.CROSSOVER)
        # The accent is the sunset's orange, not the sky's own blue again.
        _, a, b = wall_tone.oklab(wall_tone.lin_of(got["palettes"]["match"]["accent"]))
        self.assertGreater(a, 0)
        self.assertGreater(b, 0)

    def test_a_grey_picture_leaves_the_bars_own_colours(self):
        got = self.read(self.picture("grey.png", (20, 20, 20)))
        self.assertEqual(got["palettes"]["match"], {"bg": "#0f111b", "fg": "#ecf0c1", "accent": ""})
        self.assertEqual(got["palettes"]["opposite"]["bg"], "#f4f4f0")

    def test_the_swatches_are_the_pictures_colours_most_first(self):
        got = self.read(self.picture("two.png", (30, 60, 140), below=(240, 160, 40)))
        self.assertGreaterEqual(len(got["swatches"]), 2)
        self.assertTrue(all(re.fullmatch(r"#[0-9a-f]{6}", s) for s in got["swatches"]))
        blue = wall_tone.oklab(wall_tone.lin_of(got["swatches"][0]))
        self.assertLess(blue[2], 0, got["swatches"])

    def test_the_island_reads_only_its_own_ground(self):
        # Dark under the bar's middle, light at its ends: lifted.
        im = Image.new("RGB", (2560, 1440), (236, 232, 224))
        im.paste((5, 5, 6), (900, 0, 1660, 700))
        im.save(self.root / "notch.png")
        got = self.read(self.root / "notch.png", "DESK:2560:1440:37")
        self.assertEqual(got["screens"]["DESK"]["island"], "#ecf0c1")

    def test_an_unreadable_picture_fails_and_says_nothing_on_stdout(self):
        bad = self.root / "bad.png"
        bad.write_text("not a picture")
        done = subprocess.run([sys.executable, "-I", str(SCRIPT), str(bad), *SCREENS],
                              capture_output=True, text=True, timeout=30)
        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(done.stdout, "")

    # The fill rule is lock-colours.py's for the lock's notch: keep in step.
    def test_the_fill_rule_is_the_locks(self):
        spec = importlib.util.spec_from_file_location("lock_colours", REPO / "hypr/scripts/lock-colours.py")
        lock = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(lock)
        self.assertEqual(wall_tone.FILL_READS, lock.FILL_READS)
        self.assertEqual(wall_tone.CREAM[1:], lock.BEIGE)
        for ground in (0.0, 0.01, 0.03, 0.2):
            self.assertEqual(wall_tone.island_fill(ground)[1:], lock.fill_of(ground))


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
