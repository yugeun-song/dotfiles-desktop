"""Tests for hypr/scripts/lock-colours.py, the lock screen's colours chosen
from the wallpaper, and for hypr/scripts/lock-fit.sh, which sizes the lock's
copy per screen and runs it. The wallpapers are drawn here and hyprctl is a
stand-in first on PATH: nothing reads the machine's wallpaper, its outputs
or its runtime directory.
"""

import importlib.util
import math
import os
import pathlib
import re
import stat
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
# No cache beside the scripts loaded here: install.sh mirrors their directory
# whole.
sys.dont_write_bytecode = True


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, REPO / "hypr/scripts" / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


lock_colours = load("lock_colours", "lock-colours.py")
lock_media = load("lock_media", "lock-media.py")

try:
    from PIL import Image
except ImportError:
    Image = None

BEIGE = "rgba(ecf0c1ff)"


def blocks(text, monitor):
    """Every widget block of the copy for that monitor, as its keys."""
    out, current = [], None
    for line in text.splitlines():
        s = line.strip()
        if s.endswith("{") and "=" not in s:
            current = {"type": s[:-1].strip()}
        elif s == "}" and current is not None:
            if current.get("monitor") == monitor:
                out.append(current)
            current = None
        elif current is not None and "=" in s and not s.startswith("#"):
            key, value = s.split("=", 1)
            current[key.strip()] = value.strip()
    return out


def widget(copy, monitor, **match):
    found = [b for b in blocks(copy, monitor) if all(b.get(k) == v for k, v in match.items())]
    if len(found) != 1:
        raise AssertionError(f"{len(found)} blocks on {monitor} match {match}")
    return found[0]


def card(copy, monitor):
    """The card's picture, not one of its controls' over it."""
    return widget(copy, monitor, type="image", reload_time="1")


def hue(hex6):
    _, a, b = lock_colours.oklab(lock_colours.rgb_of(hex6))
    return math.degrees(math.atan2(b, a)) % 360


def ink_of(rgba):
    return re.fullmatch(r"rgba\(([0-9a-f]{6})[0-9a-f]{2}\)", rgba).group(1)


@unittest.skipIf(Image is None, "python3-pillow is not installed")
class LockColoursTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.screens([("TEST-A", 2560, 1440), ("TEST-B", 2880, 1800)])
        self.conf = self.root / "hyprlock.conf"
        self.out = self.root / "fit.conf"

    def tearDown(self):
        self.tmp.cleanup()

    def screens(self, outputs):
        rows = ",".join(f'{{"name": "{n}", "width": {w}, "height": {h}, "disabled": false, '
                        f'"availableModes": ["{w}x{h}@60.00Hz"]}}' for n, w, h in outputs)
        stub = self.bin / "hyprctl"
        stub.write_text(f"#!/bin/sh\necho '[{rows}]'\n")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

    def wallpaper(self, name, size, *bands):
        """A picture of horizontal bands, each (share of the height, colour)."""
        im = Image.new("RGB", size)
        top = 0
        for share, colour in bands:
            bottom = top + round(size[1] * share)
            im.paste(colour, (0, top, size[0], bottom))
            top = bottom
        path = self.root / name
        im.save(path)
        return path

    def fit(self, wallpaper):
        text = (REPO / "hypr/hyprlock.conf").read_text(encoding="utf-8")
        text = re.sub(r"(?m)^(background \{.*?^    path = ).*?$", lambda m: m.group(1) + str(wallpaper),
                      text, count=1, flags=re.S)
        self.conf.write_text(text, encoding="utf-8")
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}")
        done = subprocess.run(["bash", str(REPO / "hypr/scripts/lock-fit.sh"), str(self.conf), str(self.out)],
                              env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), str(self.out))
        return self.out.read_text(encoding="utf-8")

    def dark(self):
        return self.wallpaper("dark.png", (1600, 900), (1, (20, 22, 30)))

    # The user's calls: the panel's proportions on every screen, wider on a
    # wider one rather than larger (2026-10-24); the card and its controls
    # at the bar's grown island's proportions on every one (2026-10-26).
    def test_every_screen_gets_the_panels_proportions(self):
        text = self.fit(self.dark())
        self.assertEqual(widget(text, "TEST-B", text="$TIME")["font_size"], "107")
        self.assertEqual(widget(text, "TEST-A", text="$TIME")["font_size"], "85")
        self.assertEqual(widget(text, "TEST-B", type="shape")["size"], "214, 51")
        self.assertEqual(widget(text, "TEST-A", type="shape")["size"], "190, 41")
        self.assertEqual(card(text, "TEST-A")["size"], "177")
        # Unstretched as the card, where the shape above is 1.111 wider.
        shuffle = {"onclick": "$media click shuffle"}
        self.assertEqual(widget(text, "TEST-A", **shuffle)["position"], "-111, -72")
        self.assertEqual(widget(text, "TEST-B", **shuffle)["position"], "-139, -91")

    def test_an_ultrawide_stretches_no_further_than_the_cap(self):
        self.screens([("TEST-W", 3440, 1440)])
        text = self.fit(self.dark())
        self.assertEqual(widget(text, "TEST-W", type="shape")["size"], "214, 41")
        self.assertEqual(widget(text, "TEST-W", onclick="$media click loop")["position"], "111, -72")

    def test_a_narrower_screen_scales_by_its_width(self):
        self.screens([("TEST-P", 1440, 2560)])
        text = self.fit(self.dark())
        self.assertEqual(widget(text, "TEST-P", text="$TIME")["font_size"], "53")

    def test_a_dark_wallpaper_keeps_the_bars_beige(self):
        text = self.fit(self.dark())
        for name in ("TEST-A", "TEST-B"):
            self.assertEqual(widget(text, name, text="$TIME")["color"], BEIGE)
            self.assertEqual(widget(text, name, text="$TIME")["shadow_passes"], "0")
            self.assertEqual(widget(text, name, type="input-field")["font_color"], BEIGE)
            # The design's faint pane.
            self.assertTrue(card(text, name)["reload_cmd"].endswith(" card ecf0c1,ffffff1a,ffffff33"))

    def test_a_white_wallpaper_takes_a_dark_of_the_bars_hue(self):
        text = self.fit(self.wallpaper("white.png", (1600, 900), (1, (255, 255, 255))))
        clock = ink_of(widget(text, "TEST-A", text="$TIME")["color"])
        # Against the wallpaper as hyprlock dims it (0.85).
        behind = lock_colours.LIN[round(255 * 0.85)]
        self.assertGreaterEqual(lock_colours.contrast(lock_colours.luminance(lock_colours.rgb_of(clock)), behind),
                                lock_colours.TARGET)
        self.assertLess(abs(hue(clock) - hue(lock_colours.BAR_BG)), 25)
        field = widget(text, "TEST-A", type="input-field")
        self.assertEqual(field["placeholder_text"], f'<span foreground="##{clock}">Press to unlock</span>')
        ink, pane, _ = card(text, "TEST-A")["reload_cmd"].split()[-1].split(",")
        self.assertEqual(ink, clock)
        self.assertTrue(pane.startswith("ffffff") and int(pane[6:], 16) >= 0x73, pane)

    def test_the_dark_takes_the_hue_opposite_the_wallpapers(self):
        text = self.fit(self.wallpaper("cream.png", (1600, 900), (1, (246, 226, 160))))
        clock = ink_of(widget(text, "TEST-A", text="$TIME")["color"])
        apart = abs((hue(clock) - hue("f6e2a0") + 180) % 360 - 180)
        self.assertGreater(apart, 150, (clock, hue(clock), hue("f6e2a0")))

    # A light sky over dark hills: the clock dark, the field below beige.
    def test_a_screen_light_above_and_dark_below_splits_its_colours(self):
        text = self.fit(self.wallpaper("sky.png", (1600, 900), (0.45, (235, 228, 220)), (0.55, (24, 26, 30))))
        self.assertNotEqual(widget(text, "TEST-A", text="$TIME")["color"], BEIGE)
        self.assertEqual(widget(text, "TEST-A", type="input-field")["font_color"], BEIGE)
        self.assertIn("card ecf0c1,", card(text, "TEST-A")["reload_cmd"])

    # A tower in a light sky behind the clock: the clock keeps its dark, with
    # a halo, while a plain sky gets none.
    def test_a_halo_only_over_what_the_ink_does_not_read_on(self):
        plain = self.fit(self.wallpaper("plain.png", (1600, 900), (1, (235, 228, 220))))
        self.assertEqual(widget(plain, "TEST-A", text="$TIME")["shadow_passes"], "0")
        im = Image.open(self.root / "plain.png").copy()
        im.paste((15, 15, 20), (760, 0, 840, 900))
        im.save(self.root / "tower.png")
        tower = self.fit(self.root / "tower.png")
        clock = widget(tower, "TEST-A", text="$TIME")
        self.assertNotEqual(clock["color"], BEIGE)
        self.assertEqual(clock["shadow_passes"], str(lock_colours.HALO_PASSES))
        self.assertEqual(clock["shadow_color"], f"rgba({lock_colours.GLOWS['dark']})")

    # Fine print under the clock, as the playing cards the user's wallpaper
    # shows (2026-10-27): no halo holds it off, so that screen's background
    # is blurred more and darkened until the bar's beige reads over it. The
    # tower above, a halo's case but no fine detail, keeps the design's blur.
    def test_fine_detail_behind_the_text_is_blurred_more(self):
        # Light paper, small dark marks: still light once blurred.
        im = Image.new("RGB", (1600, 900), (240, 240, 236))
        for x in range(0, 1600, 12):
            for y in range(0, 900, 12):
                im.paste((12, 12, 14), (x, y, x + 4, y + 4))
        im.save(self.root / "print.png")
        text = self.fit(self.root / "print.png")
        for name in ("TEST-A", "TEST-B"):
            back = widget(text, name, type="background")
            self.assertEqual(back["blur_passes"], str(lock_colours.BUSY_PASSES))
            self.assertLess(float(back["brightness"]), 0.85)
            self.assertGreaterEqual(float(back["brightness"]), lock_colours.BUSY_DARKEST)
            self.assertEqual(widget(text, name, text="$TIME")["color"], BEIGE)
        im = Image.new("RGB", (1600, 900), (235, 228, 220))
        im.paste((15, 15, 20), (760, 0, 840, 900))
        im.save(self.root / "tower.png")
        tower = self.fit(self.root / "tower.png")
        self.assertEqual(widget(tower, "TEST-A", text="$TIME")["shadow_passes"], str(lock_colours.HALO_PASSES))
        self.assertEqual(widget(tower, "TEST-A", type="background")["blur_passes"], "1")

    def test_without_a_wallpaper_the_copy_keeps_the_tokens_hyprlock_conf_defines(self):
        text = self.fit(self.root / "missing.png")
        self.assertEqual(widget(text, "TEST-A", text="$TIME")["color"], "$head_ink")
        self.assertIn("$head_ink = rgba(ecf0c1ff)", text)
        self.assertIn("$card_paint = ecf0c1,ffffff1a,ffffff33", text)

    # hyprlock covers the screen and cuts the middle, so must the judgement.
    def test_the_wallpaper_is_cut_as_hyprlock_cuts_it(self):
        im = Image.new("RGB", (3000, 1000), (0, 0, 0))
        im.paste((255, 255, 255), (0, 0, 1500, 1000))
        small = lock_colours.backdrop(im, 1000, 1000, {})
        self.assertEqual(small.size, (125, 125))
        self.assertEqual(small.getpixel((10, 60)), (255, 255, 255))
        self.assertEqual(small.getpixel((115, 60)), (0, 0, 0))

    def test_only_a_blurred_background_is_dimmed(self):
        im = Image.new("RGB", (800, 800), (200, 200, 200))
        sharp = lock_colours.backdrop(im, 800, 800, {"brightness": "0.5", "blur_passes": "0"})
        blurred = lock_colours.backdrop(im, 800, 800, {"brightness": "0.5", "blur_passes": "1"})
        self.assertEqual(sharp.getpixel((50, 50)), (200, 200, 200))
        self.assertEqual(blurred.getpixel((50, 50)), (100, 100, 100))

    # A lock decodes the wallpaper only after it changed: same size and time,
    # different bytes, and the cache answers; a new time and it is read again.
    def test_the_cache_answers_until_the_wallpaper_changes(self):
        path = self.wallpaper("cached.png", (1600, 900), (1, (255, 255, 255)))
        first = self.fit(path)
        st = path.stat()
        path.write_bytes(b"x" * st.st_size)
        os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))
        self.assertEqual(self.fit(path), first)
        os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))
        self.assertEqual(widget(self.fit(path), "TEST-A", text="$TIME")["color"], "$head_ink")

    def test_the_card_is_measured_as_lock_media_draws_it(self):
        self.assertAlmostEqual(lock_colours.card_aspect(), lock_media.W / lock_media.H)

    # Theme.fg and Theme.bg in the bar's Theme.qml: keep in step.
    def test_the_beige_and_the_dark_hue_are_the_bars(self):
        theme = (REPO / "quickshell/bar/services/Theme.qml").read_text(encoding="utf-8")
        self.assertIn(f'readonly property color fg:     "#{lock_colours.BEIGE}"', theme)
        self.assertIn(f'readonly property color bg:     "#{lock_colours.BAR_BG}"', theme)


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
