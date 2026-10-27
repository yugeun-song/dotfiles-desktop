#!/usr/bin/env python3
"""The lock screen's text colours, from the wallpaper behind the text: the
bar's beige wherever it reads, as the user asked (2026-10-24), else a deep
tone of the hue opposite the wallpaper's there.

    lock-colours.py CONFIG   print CONFIG, lock-fit.sh's copy of
                             hyprlock.conf, with each screen's colours in

hyprlock.conf names its text colours as tokens, $GROUP_KIND. A widget that
names head_ink belongs to the head, and the head's colours are chosen
against the part of the wallpaper behind the head's widgets as hyprlock
shows it on that screen: cut to cover the screen, dimmed by the
background's brightness. The kinds are ink (hyprlock's rgba), soft (the same
at the strength of secondary text), hex (for markup), paint (lock-media.py's
card: its ink, pane and edge), halo and glow (a label's shadow passes and
colour).

The beige stays where most of the picture behind a group is dark enough for
it. A light sky over dark hills can give the clock the dark and the foot the
beige; a group takes the clock's choice wherever that reads, though, so a
screen changes colour only where the picture forces it. A screen has one
dark, opposite the hue behind the text it colours; a grey wallpaper leaves
no hue to oppose, and the dark takes the bar's. Text over a part its colour
does not read on, a dark tower in a light sky, gets a soft halo of the
other tone rather than a colour of its own. The card's pane thickens until
the card's text reads over the darkest or lightest of what lies behind it.
Where the part a group's text does not read on is fine detail, a playing
card's print under the clock (the user's wallpaper, 2026-10-27), no halo
holds it off: that screen's background is blurred more and darkened until
the beige reads over it, and its colours are chosen against it so changed.

lock-fit.sh runs this at every lock. The result is kept in FIT_INK_CACHE,
keyed by the copy and by the wallpaper's size and time, so the wallpaper is
decoded (about a tenth of a second) only after it or a screen changed.
Fails, printing nothing, when no screen's colours could be chosen:
lock-fit.sh then keeps the tokens, which hyprlock.conf defines as the beige.
"""

import hashlib
import importlib.util
import math
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent

# The bar's text (Theme.fg, quickshell/bar/services/Theme.qml), the lock's
# default, and the bar's background (Theme.bg), whose hue the dark takes on
# a grey wallpaper. Keep in step.
BEIGE = "ecf0c1"
BAR_BG = "0f111b"

# Secondary text's strength: the card's artist and times, shuffle and repeat.
SOFT = 0xB8

# WCAG 2 contrast: what large text needs, below which the beige gives way,
# and below which against the tenth of the picture that opposes it most a
# group's text gets a halo; and what the darks and the card's pane are
# pushed to.
READS = 3.0
TARGET = 4.5
# The halo, in shadow passes (hyprlock blurs a label's shadow that often),
# and its colours round the beige and round a dark.
HALO_PASSES = 3
GLOWS = {"light": "000000a6", "dark": "ffffffa6"}

# The dark's OKLab lightness starts high enough to show its hue and drops
# until it reads; its chroma grows with the wallpaper's.
DARK_L = (0.40, 0.14)
DARK_C = (0.04, 0.10)

# The wallpaper is judged at an eighth of each screen's pixels.
SHRINK = 8

# A busy background takes BUSY_PASSES of blur. Busy: some group needs its
# halo, needs none against the picture blurred by FINE_RADIUS at the eighth
# (what fails is fine), and the picture behind it is detailed, the mean
# difference (grey, 0 to 1) between it and itself blurred by DETAIL_RADIUS at
# the eighth past DETAIL. The cards' print gave 0.04 to 0.10; the calm
# wallpapers the user had used, 0 to 0.02. The colours are then chosen
# against the picture as those passes blur it, which at the eighth is about a
# blur of BUSY_SPREAD times the background's blur_size (fitted to renders of
# both screens).
DETAIL = 0.03
DETAIL_RADIUS = 2
FINE_RADIUS = 3
BUSY_PASSES = 3
BUSY_SPREAD = 0.5
# A busy picture is darkened too, a dark haze over it as the user offered
# (2026-10-27: the navy over the blurred cards still read poorly): from the
# background's own brightness down, until the bar's beige reads over what
# lies behind each group, its middle to TARGET and its brightest tenth to
# READS, though never below BUSY_DARKEST. A dark and a light under one line
# of text leave no ink that reads on both.
BUSY_DARKEST = 0.35

# A label's text is not known before hyprlock draws it: four of its sizes
# wide, about the clock's, the widest; one line high.
LABEL_EMS = 4
LINE = 1.25

TOKEN = re.compile(r"\$([a-z]+)_(ink|soft|hex|paint|halo|glow)\b")
BACK = re.compile(r"^(\s*(blur_passes|brightness)\s*=\s*)[0-9.]+")
# lock-fit.sh's line for each screen, with its two factors.
SCREEN = re.compile(r"^# (\S+) (\d+)x(\d+) fit ([0-9.]+) wide ([0-9.]+)$")
WIDGETS = {"background", "label", "image", "input-field", "shape"}


def decode(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def encode(v):
    v = max(0.0, min(1.0, v))
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


LIN = [decode(c / 255) for c in range(256)]


def rgb_of(hex6):
    return tuple(LIN[int(hex6[i:i + 2], 16)] for i in (0, 2, 4))


def hex_of(rgb):
    return "".join(f"{round(encode(c) * 255):02x}" for c in rgb)


def luminance(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def contrast(y1, y2):
    return (max(y1, y2) + 0.05) / (min(y1, y2) + 0.05)


def oklab(rgb):
    r, g, b = rgb
    lms = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
           0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
           0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in lms)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def linear(lab):
    big_l, a, b = lab
    l = (big_l + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (big_l - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (big_l - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


Y_BEIGE = luminance(rgb_of(BEIGE))
# The dark a choice is made with, before its tone is known: about the
# luminance of the darks it ends at.
Y_DARK = 0.03


def bare(line):
    """The line without its comment; "##" is hyprlang's escaped "#"."""
    return line.replace("##", "\x01").split("#", 1)[0].strip()


def parse(lines):
    """The screens lock-fit.sh sized, by name: width and height; and each
    widget block: its first and last line, type, keys and the groups its
    tokens name."""
    screens, blocks = {}, []
    depth, start, kind, keys = 0, 0, "", {}
    for i, line in enumerate(lines):
        found = SCREEN.match(line.rstrip("\n"))
        if found:
            name, w, h, _, _ = found.groups()
            screens[name] = (int(w), int(h))
            continue
        s = bare(line)
        if "=" not in s and s.endswith("{"):
            if depth == 0:
                start, kind, keys = i, s[:-1].strip(), {}
            depth += 1
        elif s == "}" and depth > 0:
            depth -= 1
            if depth == 0 and kind in WIDGETS:
                groups = {m.group(1) for j in range(start, i + 1) for m in TOKEN.finditer(lines[j])}
                blocks.append((start, i, kind, keys, groups))
        elif depth == 1 and "=" in s:
            key, value = s.split("=", 1)
            keys[key.strip()] = value.strip()
    return screens, blocks


def numbers(keys, key):
    try:
        return [float(v.strip().removesuffix("px")) for v in keys.get(key, "").split(",") if v.strip()]
    except ValueError:
        return []


def card_aspect():
    """The card's width over its height, as lock-media.py draws it; without
    that script there is no card to read, only its place."""
    # Read in place, leaving no cache beside it: the installer mirrors this
    # directory whole.
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("lock_media", HERE / "lock-media.py")
        media = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(media)
        return media.W / media.H
    except Exception:
        return 2.0


def box(kind, keys, w, h, aspect):
    """Where the widget lies on a w x h screen, from its top left, or None."""
    x, y = (numbers(keys, "position") + [0.0, 0.0])[:2]
    if kind == "label":
        size = (numbers(keys, "font_size") or [16.0])[0]
        bw, bh = size * LABEL_EMS, size * LINE
    elif kind == "image":
        # The only picture with colours to choose is the card, at its own
        # proportions on every screen; its controls' pictures name no group.
        side = (numbers(keys, "size") or [150.0])[0]
        bw, bh = side * aspect, side
    else:
        size = numbers(keys, "size")
        if len(size) != 2:
            return None
        bw, bh = size
    cx = {"left": x + bw / 2, "right": w - bw / 2 + x}.get(keys.get("halign"), w / 2 + x)
    cy = {"top": -y + bh / 2, "bottom": h - y - bh / 2}.get(keys.get("valign"), h / 2 - y)
    return (cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)


def backdrop(picture, w, h, keys):
    """The wallpaper as hyprlock shows it on a w x h screen, an eighth the
    size: scaled to cover it and cut to the middle, then dimmed."""
    from PIL import Image
    scale = max(w / picture.width, h / picture.height)
    cw, ch = w / scale, h / scale
    left, top = max(0.0, (picture.width - cw) / 2), max(0.0, (picture.height - ch) / 2)
    small = picture.resize((max(1, w // SHRINK), max(1, h // SHRINK)), Image.BILINEAR,
                           box=(left, top, min(picture.width, left + cw), min(picture.height, top + ch)))
    # hyprlock dims in its blur, so only a blurred background is dimmed.
    passes = (numbers(keys, "blur_passes") or [0.0])[0]
    dim = (numbers(keys, "brightness") or [1.0])[0] if passes > 0 else 1.0
    if dim != 1.0:
        small = small.point(lambda v: min(255, round(v * dim)))
    return small


def patch(small, area):
    """What a group's text is read against: the luminance of the pixels
    behind it, their median, the tenths and the twentieths at either end, and
    their mean colour."""
    x0, y0, x1, y1 = (round(v / SHRINK) for v in area)
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(small.width, x1), min(small.height, y1)
    if x1 <= x0 or y1 <= y0:
        return None
    data = small.crop((x0, y0, x1, y1)).tobytes()
    ys, total = [], [0.0, 0.0, 0.0]
    for i in range(0, len(data), 3):
        r, g, b = LIN[data[i]], LIN[data[i + 1]], LIN[data[i + 2]]
        total[0] += r
        total[1] += g
        total[2] += b
        ys.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
    ys.sort()
    n = len(ys)
    return {"darkest": ys[(n - 1) // 20], "dark": ys[(n - 1) // 10], "mid": ys[(n - 1) // 2],
            "bright": ys[(9 * (n - 1)) // 10], "brightest": ys[(19 * (n - 1)) // 20],
            "sum": total, "count": n}


def reads(mode, p):
    return contrast(Y_BEIGE if mode == "light" else Y_DARK, p["mid"])


def own_mode(p):
    light, dark = reads("light", p), reads("dark", p)
    return "light" if light >= READS or light >= dark else "dark"


def gamut(big_l, da, db, chroma):
    """The colour at that lightness and hue, its chroma cut until sRGB has it."""
    while True:
        rgb = linear((big_l, da * chroma, db * chroma))
        if all(-1e-6 <= c <= 1 + 1e-6 for c in rgb) or chroma < 0.005:
            return tuple(max(0.0, min(1.0, c)) for c in rgb)
        chroma *= 0.9


def dark_ink(patches):
    """The one dark for the groups given, opposite the hue behind them."""
    n = sum(p["count"] for p in patches)
    _, a, b = oklab(tuple(sum(p["sum"][i] for p in patches) / n for i in range(3)))
    chroma = math.hypot(a, b)
    _, ba, bb = oklab(rgb_of(BAR_BG))
    bar = math.hypot(ba, bb)
    # A greyer wallpaper's hue is noise: the dark turns to the bar's. A sage
    # (chroma 0.02) already reads as a colour and is opposed.
    w = max(0.0, min(1.0, (chroma - 0.005) / 0.015))
    da = -w * a / max(chroma, 1e-9) + (1 - w) * ba / bar
    db = -w * b / max(chroma, 1e-9) + (1 - w) * bb / bar
    norm = math.hypot(da, db)
    if norm < 1e-6:
        da, db, norm = ba / bar, bb / bar, 1.0
    da, db = da / norm, db / norm
    c = DARK_C[0] + (DARK_C[1] - DARK_C[0]) * min(chroma, 0.1) / 0.1
    # Against the middle of the picture: its darker parts get the halo, and
    # judged against those the dark ended near black on a busy one.
    middle = min(p["mid"] for p in patches)
    big_l = DARK_L[0]
    while True:
        rgb = gamut(big_l, da, db, c)
        if contrast(luminance(rgb), middle) >= TARGET or big_l <= DARK_L[1]:
            return rgb
        big_l = max(DARK_L[1], big_l - 0.02)


def under(y, alpha, pane):
    """A pixel's luminance under a pane (0 black, 1 white) at alpha, blended
    as hyprlock blends: in stored values, not in light."""
    return decode(alpha * pane + (1 - alpha) * encode(y))


def soft_over(ink_y, y, alpha, pane):
    """Secondary text's luminance over a pixel under the pane: the ink at
    SOFT laid over what the pane leaves, in stored values."""
    behind = alpha * pane + (1 - alpha) * encode(y)
    return decode(SOFT / 255 * encode(ink_y) + (1 - SOFT / 255) * behind)


def reads_on_pane(ink_y, y, alpha, pane):
    """Whether the card's text reads over that pixel: the ink to TARGET, the
    softer controls and the artist to READS."""
    shown = under(y, alpha, pane)
    return contrast(ink_y, shown) >= TARGET and contrast(soft_over(ink_y, y, alpha, pane), shown) >= READS


def paint(mode, ink, p):
    """lock-media.py's card: ink, pane and edge. The pane is as thin as lets
    the text read over the twentieth of the picture that opposes it most."""
    hex6 = hex_of(ink)
    y = luminance(ink)
    if mode == "light":
        # The design's pane, a faint white, where the beige reads through it;
        # else a dark one.
        if reads_on_pane(y, p["brightest"], 0.10, 1.0):
            return f"{hex6},ffffff1a,ffffff33"
        alpha = next((a / 100 for a in range(15, 71, 5) if reads_on_pane(y, p["brightest"], a / 100, 0.0)), 0.70)
        return f"{hex6},000000{round(alpha * 255):02x},ffffff1f"
    # Light, frosted.
    alpha = next((a / 100 for a in range(45, 91, 5) if reads_on_pane(y, p["darkest"], a / 100, 1.0)), 0.90)
    return f"{hex6},ffffff{round(alpha * 255):02x},{hex6}24"


def colours(patches, lead):
    """Every group's colours by kind, for one screen."""
    first = own_mode(patches[lead])
    modes = {g: first if g == lead or reads(first, p) >= READS else own_mode(p) for g, p in patches.items()}
    darks = [p for g, p in patches.items() if modes[g] == "dark"]
    dark = dark_ink(darks) if darks else None
    out = {}
    for g, p in patches.items():
        mode = modes[g]
        ink = rgb_of(BEIGE) if mode == "light" else dark
        hex6 = hex_of(ink)
        worst = p["bright"] if mode == "light" else p["dark"]
        out[g] = {"ink": f"rgba({hex6}ff)", "soft": f"rgba({hex6}{SOFT:02x})", "hex": hex6,
                  "paint": paint(mode, ink, p),
                  "halo": str(HALO_PASSES if contrast(luminance(ink), worst) < READS else 0),
                  "glow": f"rgba({GLOWS[mode]})"}
    return out


def judge(small, areas, sizes):
    """A screen's colours against that picture, or None with no group on it.
    The largest text leads: the clock."""
    patches = {g: p for g, p in ((g, patch(small, a)) for g, a in areas.items()) if p}
    if not patches:
        return None
    lead = max(patches, key=lambda g: sizes.get(g, 0.0))
    return colours(patches, lead)


def busy(small, areas, sizes, chosen):
    """Whether fine detail is what some group's ink fails on: the group needs
    its halo, needs none against the picture blurred wide, and the picture
    behind it is detailed. A dark tower in a light sky still needs the halo
    so blurred, and is left to it. The card is left out: its pane already
    thickens over what lies behind it."""
    from PIL import ImageFilter
    blurred = judge(small.filter(ImageFilter.GaussianBlur(FINE_RADIUS)), areas, sizes) or {}
    grey = small.convert("L")
    soft = grey.filter(ImageFilter.GaussianBlur(DETAIL_RADIUS))
    for g, area in areas.items():
        if g == "card" or chosen.get(g, {}).get("halo", "0") == "0" or blurred.get(g, {}).get("halo") != "0":
            continue
        x0, y0, x1, y1 = (round(v / SHRINK) for v in area)
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(grey.width, x1), min(grey.height, y1)
        if x1 <= x0 or y1 <= y0:
            continue
        a, b = grey.crop((x0, y0, x1, y1)).tobytes(), soft.crop((x0, y0, x1, y1)).tobytes()
        if sum(abs(p - q) for p, q in zip(a, b)) / len(a) / 255 > DETAIL:
            return True
    return False


def darkened(small, areas, applied, base):
    """A busy picture's brightness and the picture at it: the most, from the
    background's own (base) down by twentieths, at which the beige reads
    behind every group but the card. The picture given is at `applied`."""
    level = base
    while True:
        dim = small if level == applied else small.point(lambda v: min(255, round(v * level / applied)))
        patches = [p for p in (patch(dim, a) for g, a in areas.items() if g != "card") if p]
        if level <= BUSY_DARKEST or all(contrast(Y_BEIGE, p["mid"]) >= TARGET
                                        and contrast(Y_BEIGE, p["bright"]) >= READS for p in patches):
            return level, dim
        level = max(BUSY_DARKEST, round(level - 0.05, 2))


def wallpaper_of(keys):
    path = keys.get("path", "")
    if not path or path == "screenshot":
        return None
    return os.path.expanduser(path)


def stamp(text, blocks):
    """The cache's key: the copy, every wallpaper it names as it is now, and
    the scripts that choose, so a change to them shows at the next lock."""
    digest = hashlib.sha1(text.encode())
    for script in (pathlib.Path(__file__), HERE / "lock-media.py"):
        try:
            digest.update(script.read_bytes())
        except OSError:
            pass
    for path in sorted({wallpaper_of(keys) for _, _, kind, keys, _ in blocks if kind == "background"} - {None}):
        try:
            st = os.stat(path)
            digest.update(f"\0{path}\0{st.st_size}\0{st.st_mtime_ns}".encode())
        except OSError:
            digest.update(f"\0{path}\0missing".encode())
    return digest.hexdigest()


def ink(text, screens, blocks):
    """The copy with each screen's colours in, or None when none could be chosen."""
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit("lock-colours: python3-pillow is not installed")
    from PIL import ImageFilter
    lines = text.splitlines(keepends=True)
    aspect = card_aspect()
    pictures, judged, values = {}, {}, {}
    for name, (w, h) in screens.items():
        mine = [b for b in blocks if b[3].get("monitor") == name]
        background = next((b[3] for b in mine if b[2] == "background"), None)
        path = wallpaper_of(background) if background else None
        if path is None:
            continue
        if path not in pictures:
            try:
                picture = Image.open(path)
                picture.draft("RGB", (picture.width // SHRINK, picture.height // SHRINK))
                pictures[path] = picture.convert("RGB")
            except Exception:
                # Unreadable, or a decompression bomb: hyprlock shows its colour.
                pictures[path] = None
        if pictures[path] is None:
            continue
        small = backdrop(pictures[path], w, h, background)
        areas, sizes = {}, {}
        for _, _, kind, keys, groups in mine:
            area = box(kind, keys, w, h, aspect)
            if area is None:
                continue
            for g in groups:
                old = areas.get(g, area)
                areas[g] = (min(old[0], area[0]), min(old[1], area[1]), max(old[2], area[2]), max(old[3], area[3]))
                if kind == "label":
                    sizes[g] = max(sizes.get(g, 0.0), (numbers(keys, "font_size") or [0.0])[0])
        chosen = judge(small, areas, sizes)
        if chosen is not None:
            spread = BUSY_SPREAD * ((numbers(background, "blur_size") or [0.0])[0])
            base = (numbers(background, "brightness") or [1.0])[0]
            applied = base if (numbers(background, "blur_passes") or [0.0])[0] > 0 else 1.0
            judged[name] = (path, small, areas, sizes, chosen, spread, applied, base)
    if not judged:
        return None
    # One picture, one blur: busy behind the text on any screen, it is
    # blurred and darkened on every screen that shows it.
    busier = {j[0] for j in judged.values() if busy(*j[1:5])}
    for name, (path, small, areas, sizes, chosen, spread, applied, base) in judged.items():
        if path in busier:
            level, dim = darkened(small.filter(ImageFilter.GaussianBlur(spread)), areas, applied, base)
            again = judge(dim, areas, sizes)
            if again is not None:
                chosen = again
                chosen["back"] = {"blur_passes": str(BUSY_PASSES), "brightness": f"{level:.2f}"}
        values[name] = chosen
    for start, end, kind, keys, _ in blocks:
        chosen = values.get(keys.get("monitor"))
        if chosen is None:
            continue
        for j in range(start, end + 1):
            lines[j] = TOKEN.sub(lambda m: chosen.get(m.group(1), {}).get(m.group(2), m.group(0)), lines[j])
            if kind == "background" and "back" in chosen:
                lines[j] = BACK.sub(lambda m: m.group(1) + chosen["back"][m.group(2)], lines[j])
    return "".join(lines)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    screens, blocks = parse(text.splitlines())
    cache = os.environ.get("FIT_INK_CACHE")
    key = stamp(text, blocks)
    if cache:
        try:
            kept = pathlib.Path(cache).read_text(encoding="utf-8")
            if kept.startswith(key + "\n"):
                sys.stdout.write(kept[len(key) + 1:])
                return
        except OSError:
            pass
    result = ink(text, screens, blocks)
    if result is None:
        sys.exit("lock-colours: no wallpaper to choose the colours from")
    if cache:
        try:
            part = pathlib.Path(f"{cache}.{os.getpid()}.part")
            part.write_text(f"{key}\n{result}", encoding="utf-8")
            part.replace(cache)
        except OSError:
            pass
    sys.stdout.write(result)


if __name__ == "__main__":
    main()
