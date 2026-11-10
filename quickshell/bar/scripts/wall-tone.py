#!/usr/bin/env python3
"""What the desktop's wallpaper asks of the bar's colours (services/Appearance.qml;
the user, 2026-11-11):

    wall-tone.py PICTURE NAME:WIDTH:HEIGHT:BAR [...]

PICTURE is the desktop's wallpaper (wallpaper.sh's current-desktop.png, a
video's first frame included); each screen is named with its size and the
bar's height, in the same pixels. The picture is judged as hyprpaper shows
it on each screen, cut to cover it, at an eighth of its pixels. One JSON
object on stdout:

    tone      "light" or "dark": the bar's ground, the strip under the bar on
              every screen, against the crossover where dark text and light
              text read alike (relative luminance 0.18)
    palettes  {"match": ..., "opposite": ...}: a bar background, text and
              accent drawn from the wallpaper, in its tone or in the other
    swatches  up to eight of the picture's own colours, the most of it first,
              for the colour editor
    screens   per screen, "island": the fill the island takes where it hangs
              below the bar over this ground: black where black reads, else
              the darkest grey that does (the user chose the lift to grey)

Nothing is kept: the bar asks again when the picture or a screen changes,
about a tenth of a second. Fails, printing nothing, when the picture cannot
be read; the bar then keeps what it had.
"""

import json
import math
import sys

# The ground under the bar: its own strip. The island's: below the bar's
# middle, as wide and as deep as its grown card reaches at most.
SHRINK = 8
ISLAND_W = 0.36
ISLAND_H = 0.22

# Where dark and light text read alike on a ground, by WCAG 2 contrast.
CROSSOVER = 0.18

# Black reads as an island over a ground to this contrast; below it the
# island lifts to the darkest grey that reaches it, never lighter than
# FILL_MOST. hypr/scripts/lock-colours.py lifts the lock's notch by the
# same rule; keep the two in step.
FILL_READS = 1.6
FILL_MOST = 0.09

# The palettes' lightness (OKLab L) and how much of the wallpaper's chroma
# they keep; the grey wallpapers' fallbacks are the bar's own colours
# (Appearance.qml's black and white tones).
DARK_BG_L, LIGHT_BG_L = 0.21, 0.955
DARK_FG_L, LIGHT_FG_L = 0.935, 0.22
ACCENT_L = {"dark": 0.74, "light": 0.56}
ACCENT_C = (0.10, 0.16)
GREY = 0.012


def decode(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def encode(v):
    v = max(0.0, min(1.0, v))
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


LIN = [decode(c / 255) for c in range(256)]


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


def hex_of(rgb):
    return "#" + "".join(f"{round(encode(c) * 255):02x}" for c in rgb)


def colour(big_l, hue, chroma):
    """The colour at that lightness, hue and chroma, its chroma cut until
    sRGB has it."""
    while True:
        rgb = linear((big_l, chroma * math.cos(hue), chroma * math.sin(hue)))
        if all(-1e-6 <= c <= 1 + 1e-6 for c in rgb) or chroma < 0.002:
            return tuple(max(0.0, min(1.0, c)) for c in rgb)
        chroma *= 0.9


def cover(picture, w, h):
    """The picture as hyprpaper shows it on a w x h screen, at an eighth:
    scaled to cover it and cut to the middle."""
    from PIL import Image
    scale = max(w / picture.width, h / picture.height)
    cw, ch = w / scale, h / scale
    left, top = max(0.0, (picture.width - cw) / 2), max(0.0, (picture.height - ch) / 2)
    return picture.resize((max(1, w // SHRINK), max(1, h // SHRINK)), Image.BILINEAR,
                          box=(left, top, min(picture.width, left + cw), min(picture.height, top + ch)))


def patch(small, area):
    """The pixels in area (in screen pixels): their median luminance and
    their mean colour, both in light."""
    x0, y0, x1, y1 = (round(v / SHRINK) for v in area)
    x0, y0 = max(0, min(x0, small.width - 1)), max(0, min(y0, small.height - 1))
    x1, y1 = max(x0 + 1, min(x1, small.width)), max(y0 + 1, min(y1, small.height))
    data = small.crop((x0, y0, x1, y1)).tobytes()
    ys, total = [], [0.0, 0.0, 0.0]
    for i in range(0, len(data), 3):
        rgb = (LIN[data[i]], LIN[data[i + 1]], LIN[data[i + 2]])
        for k in range(3):
            total[k] += rgb[k]
        ys.append(luminance(rgb))
    ys.sort()
    n = len(ys)
    return {"y": ys[(n - 1) // 2], "mean": tuple(t / n for t in total), "count": n}


def island_fill(ground):
    """Black where it reads over the ground, else the darkest grey that
    does, up to FILL_MOST."""
    if contrast(0.0, ground) >= FILL_READS:
        return "#000000"
    y = min(FILL_MOST, FILL_READS * (ground + 0.05) - 0.05)
    v = round(encode(y) * 255)
    return f"#{v:02x}{v:02x}{v:02x}"


def swatches(small, most=8):
    """The picture's own colours, the most of it first, none two alike."""
    from PIL import Image
    quantized = small.quantize(colors=most * 2, method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette() or []
    counted = sorted(quantized.getcolors() or [], reverse=True)
    out, seen = [], []
    for count, index in counted:
        rgb = tuple(LIN[palette[3 * index + k]] for k in range(3))
        lab = oklab(rgb)
        if any(math.dist(lab, other) < 0.06 for other in seen):
            continue
        seen.append(lab)
        out.append({"hex": hex_of(rgb), "count": count, "lab": lab})
        if len(out) == most:
            break
    return out


def accent(found, tone, bg, base_hue):
    """The most telling vivid colour of the picture, brought to a lightness
    that reads on the bar's background; None on a grey picture. One of
    another hue than the bar's tint stands out from it, so it counts up to
    twice: a blue sky's orange sunset over the sky's own blue."""
    total = sum(s["count"] for s in found) or 1
    best, score = None, 0.0
    for s in found:
        _, a, b = s["lab"]
        chroma = math.hypot(a, b)
        if chroma < 0.06:
            continue
        hue = math.atan2(b, a)
        apart = 0.0 if base_hue is None else abs(math.remainder(hue - base_hue, 2 * math.pi)) / math.pi
        here = chroma * math.sqrt(s["count"] / total) * (1 + apart)
        if here > score:
            best, score = (hue, chroma), here
    if best is None:
        return None
    hue, chroma = best
    chroma = max(ACCENT_C[0], min(ACCENT_C[1], chroma))
    big_l = ACCENT_L[tone]
    y_bg = luminance(bg)
    step = 0.02 if tone == "dark" else -0.02
    rgb = colour(big_l, hue, chroma)
    while contrast(luminance(rgb), y_bg) < 3.0 and 0.30 < big_l < 0.92:
        big_l += step
        rgb = colour(big_l, hue, chroma)
    return rgb


def palette(mean, tone, found):
    """A background, text and accent in that tone, tinted by the ground's
    hue; a grey ground leaves the bar's own colours."""
    big_l, a, b = oklab(mean)
    hue, chroma = math.atan2(b, a), math.hypot(a, b)
    if tone == "dark":
        if chroma < GREY:
            bg, fg = lin_of("#0f111b"), lin_of("#ecf0c1")
        else:
            bg = colour(DARK_BG_L, hue, min(0.045, 0.3 * chroma + 0.01))
            fg = colour(DARK_FG_L, hue, min(0.05, 0.35 * chroma))
    else:
        if chroma < GREY:
            bg, fg = lin_of("#f4f4f0"), lin_of("#0f111b")
        else:
            bg = colour(LIGHT_BG_L, hue, min(0.022, 0.2 * chroma))
            fg = colour(LIGHT_FG_L, hue, min(0.05, 0.35 * chroma))
    # The text to 7:1 at least, darkened or lightened along its own hue.
    fl, fa, fb = oklab(fg)
    while contrast(luminance(fg), luminance(bg)) < 7.0 and 0.05 < fl < 0.99:
        fl += 0.02 if tone == "dark" else -0.02
        fg = linear((fl, fa, fb))
        fg = tuple(max(0.0, min(1.0, c)) for c in fg)
    picked = accent(found, tone, bg, hue if chroma >= GREY else None)
    return {"bg": hex_of(bg), "fg": hex_of(fg), "accent": hex_of(picked) if picked else ""}


def lin_of(text):
    """A "#rrggbb" in light."""
    return tuple(LIN[int(text[i:i + 2], 16)] for i in (1, 3, 5))


def judge(picture, screens):
    out, bars, means = {}, [], []
    whole = None
    for name, w, h, bar in screens:
        small = cover(picture, w, h)
        if whole is None:
            whole = small
        strip = patch(small, (0, 0, w, max(bar, SHRINK)))
        zone_w = w * ISLAND_W
        zone = patch(small, ((w - zone_w) / 2, bar, (w + zone_w) / 2, bar + h * ISLAND_H))
        bars.append(strip["y"])
        means.append((strip["mean"], strip["count"]))
        out[name] = {"bar": round(strip["y"], 4), "ground": round(zone["y"], 4), "island": island_fill(zone["y"])}
    bars.sort()
    tone = "light" if bars[len(bars) // 2] > CROSSOVER else "dark"
    n = sum(c for _, c in means)
    mean = tuple(sum(m[k] * c for m, c in means) / n for k in range(3))
    found = swatches(whole)
    other = "dark" if tone == "light" else "light"
    return {"tone": tone,
            "palettes": {"match": palette(mean, tone, found), "opposite": palette(mean, other, found)},
            "swatches": [s["hex"] for s in found],
            "screens": out}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    screens = []
    for arg in sys.argv[2:]:
        try:
            name, w, h, bar = arg.rsplit(":", 3)
            screens.append((name, int(w), int(h), int(bar)))
        except ValueError:
            sys.exit(f"wall-tone: not NAME:WIDTH:HEIGHT:BAR: {arg}")
    try:
        from PIL import Image
    except ImportError:
        sys.exit("wall-tone: python3-pillow is not installed")
    try:
        picture = Image.open(sys.argv[1])
        picture.draft("RGB", (picture.width // SHRINK, picture.height // SHRINK))
        picture = picture.convert("RGB")
    except Exception as e:
        sys.exit(f"wall-tone: cannot read {sys.argv[1]}: {e}")
    json.dump(judge(picture, screens), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
