"""Tests for hypr/scripts/lock-media.py, the lock screen's card, transport and
weather, against stand-ins for playerctl and the bar's weather script put
first on PATH. Nothing here reaches a player, the network or the machine's
runtime directory.
"""

import contextlib
import importlib.util
import io
import os
import pathlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

REPO = pathlib.Path(__file__).resolve().parents[2]
# No cache beside the scripts loaded here: install.sh mirrors their directory
# whole.
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("lock_media", REPO / "hypr/scripts/lock-media.py")
lock_media = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lock_media)


def line(name, status, title, artist="Artist", art="", position="30000000", length="200000000"):
    return "\t".join([status, title, artist, art, position, length, name])


class LockMediaTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.players = root / "players.txt"
        self.calls = root / "calls.txt"
        self.loop = root / "loop.txt"
        self.players.write_text("")
        self.loop.write_text("None\n")
        # metadata prints the players' lines, which end in the instance;
        # asked for the name, as playerctl, without the instance. loop with
        # no value reads the state; every call is logged.
        self.stub("playerctl", f'''#!/bin/sh
echo "$*" >> "{self.calls}"
case "$*" in
    *"{{{{playerInstance}}}}"*) cat "{self.players}" ;;
    *metadata*) sed 's/[.]instance[^[:space:]]*$//' "{self.players}" ;;
    *" loop") cat "{self.loop}" ;;
esac
''')
        self.old_path = os.environ["PATH"]
        os.environ["PATH"] = f"{self.bin}:{self.old_path}"
        self.saved = (lock_media.RUN, lock_media.CONFIG, lock_media.WEATHER)
        lock_media.RUN = root / "run" / "hyprlock"
        lock_media.CONFIG = root / "config"
        lock_media.WEATHER = str(self.bin / "weather.sh")

    def tearDown(self):
        os.environ["PATH"] = self.old_path
        lock_media.RUN, lock_media.CONFIG, lock_media.WEATHER = self.saved
        self.tmp.cleanup()

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_out(self, fn, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            fn(*args)
        return out.getvalue().strip()

    def test_nothing_playing_hides_the_card_and_the_transport(self):
        path = self.run_out(lock_media.card, lock_media.PAINT)
        self.assertTrue(path.endswith("none.png"), path)
        self.assertTrue(os.path.exists(path))
        self.assertEqual(self.run_out(lock_media.glyph, "toggle"), "")
        self.assertEqual(self.run_out(lock_media.glyph, "next"), "")

    def test_the_lock_glyph_is_there_without_a_player(self):
        self.assertEqual(self.run_out(lock_media.glyph, "lock"), lock_media.GLYPHS["lock"])

    def test_the_installed_blank_picture_is_preferred(self):
        blank = lock_media.CONFIG / "hypr/lock-blank.png"
        blank.parent.mkdir(parents=True)
        blank.write_bytes((REPO / "hypr/lock-blank.png").read_bytes())
        self.assertEqual(self.run_out(lock_media.card, lock_media.PAINT), str(blank))

    def test_a_playing_player_is_chosen_over_a_paused_one(self):
        self.players.write_text(line("a", "Paused", "Old") + "\n" + line("b", "Playing", "New") + "\n")
        self.assertEqual(lock_media.player()["title"], "New")
        self.assertEqual(self.run_out(lock_media.glyph, "toggle"), lock_media.GLYPHS["pause"])

    def test_a_paused_player_shows_play(self):
        self.players.write_text(line("a", "Paused", "Song") + "\n")
        self.assertEqual(self.run_out(lock_media.glyph, "toggle"), lock_media.GLYPHS["play"])

    def test_the_card_is_drawn_once_per_change_into_alternate_files(self):
        from PIL import Image
        self.players.write_text(line("a", "Playing", "Song") + "\n")
        first = self.run_out(lock_media.card, lock_media.PAINT)
        self.assertRegex(first, r"/card-[0-9a-f]{8}-a\.png$")
        with Image.open(first) as im:
            self.assertEqual(im.size, (lock_media.W * lock_media.SCALE, lock_media.H * lock_media.SCALE))
        self.assertEqual(self.run_out(lock_media.card, lock_media.PAINT), first)
        self.players.write_text(line("a", "Playing", "Song", position="31000000") + "\n")
        second = self.run_out(lock_media.card, lock_media.PAINT)
        self.assertEqual(second, first[:-len("a.png")] + "b.png")

    # The title, the artist and the cover only change with the track, and
    # setting the text starts Pango: drawn once per track, not per second.
    def test_the_track_is_drawn_once_and_the_position_every_second(self):
        drawn = []
        real = lock_media.draw_face
        lock_media.draw_face = lambda *args: (drawn.append(args[0]["title"]), real(*args))
        try:
            self.players.write_text(line("a", "Playing", "Song") + "\n")
            first = self.run_out(lock_media.card, lock_media.PAINT)
            self.players.write_text(line("a", "Playing", "Song", position="31000000") + "\n")
            second = self.run_out(lock_media.card, lock_media.PAINT)
            self.players.write_text(line("a", "Playing", "Next", position="0") + "\n")
            self.run_out(lock_media.card, lock_media.PAINT)
        finally:
            lock_media.draw_face = real
        self.assertNotEqual(first, second)
        self.assertEqual(drawn, ["Song", "Next"])

    # 2026-10-25: Pillow drew a Korean title in Inter, which has no Hangul,
    # as boxes. Pango finds every letter; Hangul from Pretendard.
    def test_a_korean_title_is_set_with_every_letter(self):
        try:
            _, PangoCairo, cairo = lock_media.pango()
        except (ImportError, ValueError):
            self.skipTest("PyGObject with Pango, or pycairo, is not installed")
        families = subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True).stdout
        if "Pretendard" not in families:
            self.skipTest("Pretendard is not installed")
        context = PangoCairo.create_context(cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)))
        layout, _ = lock_media.row_layout(context, "밤양갱 (Bam Yang Gang)", "SemiBold", 48, 2000)
        self.assertEqual(layout.get_unknown_glyphs_count(), 0)
        used, runs = set(), layout.get_iter()
        while True:
            run = runs.get_run_readonly()
            if run is not None:
                used.add(run.item.analysis.font.describe().get_family())
            if not runs.next_run():
                break
        self.assertEqual(used, {"Inter", "Pretendard"})
        # A title too long for the card ends in an ellipsis.
        layout, _ = lock_media.row_layout(context, "가" * 200, "SemiBold", 48, 400)
        self.assertTrue(layout.is_ellipsized())

    def test_without_pango_the_card_is_drawn_in_inter(self):
        def missing():
            raise ImportError("no Pango")
        real = lock_media.pango
        lock_media.pango = missing
        try:
            self.players.write_text(line("a", "Playing", "밤양갱") + "\n")
            path = self.run_out(lock_media.card, lock_media.PAINT)
        finally:
            lock_media.pango = real
        self.assertTrue(path.endswith("-a.png"), path)
        self.assertTrue(os.path.exists(path))

    # lock-colours.py's paint for the screen reaches the picture, which
    # keeps the bar's grown island's proportions (the user, 2026-10-26).
    def test_the_screens_paint_reaches_the_picture(self):
        from PIL import Image
        self.players.write_text(line("a", "Playing", "Song") + "\n")
        path = self.run_out(lock_media.card, lock_media.paint_of("404661,ffffffb3,40466124"))
        with Image.open(path) as im:
            self.assertEqual(im.size, (lock_media.W * lock_media.SCALE, lock_media.H * lock_media.SCALE))
            # The pane, above the middle of the card.
            self.assertEqual(im.convert("RGBA").getpixel((im.width // 2, 30)), (255, 255, 255, 0xB3))
        self.assertAlmostEqual(lock_media.W / lock_media.H, 540 / 162, places=2)

    # Two screens of two looks draw at once: each keeps its own pair of
    # pictures, so neither redraws, nor overwrites what the other shows.
    def test_two_looks_keep_pictures_of_their_own(self):
        self.players.write_text(line("a", "Playing", "Song") + "\n")
        light = self.run_out(lock_media.card, lock_media.PAINT)
        dark = self.run_out(lock_media.card, lock_media.paint_of("404661,ffffffb3,40466124"))
        self.assertNotEqual(os.path.dirname(light) + os.path.basename(light)[:13],
                            os.path.dirname(dark) + os.path.basename(dark)[:13])
        self.assertEqual(self.run_out(lock_media.card, lock_media.PAINT), light)
        self.assertEqual(self.run_out(lock_media.card, lock_media.paint_of("404661,ffffffb3,40466124")), dark)

    # hyprlock.conf as written, or an older one, passes less.
    def test_a_short_or_broken_paint_keeps_the_defaults(self):
        self.assertEqual(lock_media.paint_of("d39cf2"), ("d39cf2", "ffffff1a", "ffffff33"))
        self.assertEqual(lock_media.paint_of("#d39cf2,zz"), ("d39cf2", "ffffff1a", "ffffff33"))
        self.assertEqual(lock_media.paint_of("$card_paint"), lock_media.PAINT)

    # The disc's middle: the ink between pause's bars, cut out under play's
    # triangle, the pane showing through; redrawn when the player turns.
    def test_play_pause_follows_the_player(self):
        from PIL import Image
        middle = (lock_media.W * lock_media.SCALE // 2, round(lock_media.CONTROL_Y * lock_media.SCALE))
        self.players.write_text(line("a", "Playing", "Song") + "\n")
        playing = self.run_out(lock_media.card, lock_media.PAINT)
        with Image.open(playing) as im:
            self.assertEqual(im.convert("RGBA").getpixel(middle)[3], 255)
        self.players.write_text(line("a", "Paused", "Song") + "\n")
        paused = self.run_out(lock_media.card, lock_media.PAINT)
        self.assertNotEqual(paused, playing)
        with Image.open(paused) as im:
            self.assertEqual(im.convert("RGBA").getpixel(middle)[3], 0x1A)
        self.assertEqual(list(lock_media.RUN.glob("*.part")), [])

    # hyprlock.conf's transparent pictures take the clicks for the controls
    # the card draws: each over its control, the size of its cell, kept from
    # stretching as the card is.
    def test_the_clicks_lie_over_the_drawn_controls(self):
        blocks, current = [], None
        for raw in (REPO / "hypr/hyprlock.conf").read_text(encoding="utf-8").splitlines():
            s = raw.strip()
            if s.endswith("{") and "=" not in s:
                current = {"type": s[:-1].strip(), "even": False}
            elif s == "}" and current is not None:
                blocks.append(current)
                current = None
            elif current is not None and s.replace(" ", "") == "#fit:even":
                current["even"] = True
            elif current is not None and "=" in s and not s.startswith("#"):
                key, value = s.split("=", 1)
                current[key.strip()] = value.strip()
        (picture,) = [b for b in blocks if "card" in b.get("reload_cmd", "")]
        self.assertTrue(picture["even"])
        self.assertEqual(int(picture["size"]), lock_media.H)
        middle = [float(v) for v in picture["position"].split(",")]
        for name in lock_media.CONTROLS:
            (target,) = [b for b in blocks if b.get("onclick") == f"$media click {name}"]
            self.assertTrue(target["even"], name)
            x, y = (float(v) for v in target["position"].split(","))
            self.assertLessEqual(abs(x - (middle[0] + lock_media.CONTROL_X[name])), 0.5, name)
            self.assertLessEqual(abs(y - (middle[1] + lock_media.H / 2 - lock_media.CONTROL_Y)), 0.5, name)
            self.assertGreaterEqual(int(target["size"]), lock_media.DISC, name)

    def test_covers_come_from_files_or_trusted_hosts_only(self):
        cover = pathlib.Path(self.tmp.name) / "cover.png"
        cover.write_bytes(b"x")
        self.assertEqual(lock_media.cover(f"file://{cover}"), str(cover))
        self.assertIsNone(lock_media.cover("file:///nonexistent/cover.png"))
        self.assertIsNone(lock_media.cover("http://i.scdn.co/image/x"))
        self.assertIsNone(lock_media.cover("https://evil.example/x.png"))
        self.assertIsNone(lock_media.cover("https://i.scdn.co.evil.example/x"))

    def test_clicks_reach_the_player_shown(self):
        self.players.write_text(line("spotify", "Playing", "Song") + "\n")
        lock_media.click("toggle")
        lock_media.click("loop")
        calls = self.calls.read_text().splitlines()
        self.assertIn("--player spotify play-pause", calls)
        self.assertIn("--player spotify loop Playlist", calls)

    def test_clicks_reach_the_instance_shown_not_its_namesake(self):
        self.players.write_text(line("firefox.instance_1_9", "Playing", "Song") + "\n")
        lock_media.click("toggle")
        self.assertIn("--player firefox.instance_1_9 play-pause", self.calls.read_text().splitlines())

    # A PNG header claiming 20000 x 20000: Pillow refuses it with its own
    # error, not an OSError.
    def test_a_cover_that_does_not_decode_draws_the_card_without_it(self):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        bomb = pathlib.Path(self.tmp.name) / "bomb.png"
        bomb.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 20000, 20000, 8, 2, 0, 0, 0))
                         + chunk(b"IEND", b""))
        self.players.write_text(line("a", "Playing", "Song", art=f"file://{bomb}") + "\n")
        path = self.run_out(lock_media.card, lock_media.PAINT)
        self.assertTrue(path.endswith("-a.png"), path)
        self.assertTrue(os.path.exists(path))

    def test_no_click_without_a_player(self):
        lock_media.click("toggle")
        self.assertNotIn("play-pause", self.calls.read_text())

    def test_the_weather_reads_the_bars_script(self):
        self.stub("weather.sh", '#!/bin/sh\necho \'{"code": 0, "temp": 16.4, "day": 0}\'\n')
        out = self.run_out(lock_media.weather)
        self.assertIn(lock_media.weather_icon(0, False), out)
        self.assertTrue(out.endswith("16°"), out)

    def test_no_weather_says_nothing(self):
        self.stub("weather.sh", "#!/bin/sh\nexit 1\n")
        self.assertEqual(self.run_out(lock_media.weather), "")

    # Theme.weatherIcon's table, by the same codes.
    def test_weather_icons_match_the_bar(self):
        self.assertEqual(lock_media.weather_icon(0, True), "\U000F0599")
        self.assertEqual(lock_media.weather_icon(0, False), "\U000F0594")
        self.assertEqual(lock_media.weather_icon(2, True), "")
        self.assertEqual(lock_media.weather_icon(45, True), "")
        self.assertEqual(lock_media.weather_icon(61, True), "")
        self.assertEqual(lock_media.weather_icon(81, True), "")
        self.assertEqual(lock_media.weather_icon(67, True), "")
        self.assertEqual(lock_media.weather_icon(73, True), "\U000F0598")
        self.assertEqual(lock_media.weather_icon(96, True), "")


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
