#!/usr/bin/env python3

# Makes the drag cursors bigger and heavier than the rest of the theme.
#
# A pointer is read against whatever is behind it, and the drag shapes lose that
# contest. The arrow is drawn with a two pixel border and a solid fill; Oxygen's
# open and closed hands are line art, mostly outline with little inside them, and
# at 24 pixels there is not enough of either to see while something is being
# dragged across a busy window. They are also the cursors that matter most at
# that moment, because they are the feedback that the drag is happening at all.
#
# Two changes, and neither is a resize of what is already there.
#
# Bigger, without blurring. An Xcursor image carries a nominal size and its own
# real dimensions, and clients pick by the nominal and draw at the real one. So
# a request for 24 can be answered with a 34 pixel image resampled down from
# Oxygen's 48, which is sharper than the 24 it would otherwise have got, not
# softer. Scaling the 24 up would have been the obvious move and the wrong one.
#
# Heavier, by growing an outline from the alpha channel rather than drawing one.
# It follows the fingers and the gap between them instead of boxing the hand in.

import argparse
import importlib.util
import os
import sys

from PIL import Image, ImageFilter

# Every shape a drag can put on screen. Named as the theme names them; each is
# resolved to the real file behind it, because these are mostly symlinks and
# writing through one would replace it and lose the alias.
DRAG = ("grab", "grabbing", "move", "all-scroll", "openhand", "closedhand", "fleur")

SCALE = 1.4
OUTLINE = "#212121"


def load_encoder():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tint-cursors.py")
    spec = importlib.util.spec_from_file_location("tint_cursors", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def to_image(im):
    # BGRA premultiplied to straight RGBA, so resampling and dilation do not
    # drag the alpha into the colour.
    w, h, px = im["w"], im["h"], im["px"]
    out = Image.new("RGBA", (w, h))
    data = []
    for i in range(0, len(px), 4):
        b, g, r, a = px[i], px[i + 1], px[i + 2], px[i + 3]
        if a:
            b, g, r = min(255, b * 255 // a), min(255, g * 255 // a), min(255, r * 255 // a)
        data.append((r, g, b, a))
    out.putdata(data)
    return out


def to_bgra(img):
    px = img.load()
    w, h = img.size
    buf = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            buf += bytes((b * a // 255, g * a // 255, r * a // 255, a))
    return buf


def emphasise(images, scale, ink):
    by_nominal = {}
    for im in images:
        by_nominal.setdefault(im["nominal"], im)

    out = []
    for nominal in sorted(by_nominal):
        target = max(1, round(nominal * scale))
        # The closest real image to what is being asked for, so the resample is
        # a reduction wherever the theme has anything larger to reduce from.
        src = min(images, key=lambda im: abs(im["w"] - target))
        img = to_image(src).resize((target, target), Image.LANCZOS)

        pad = max(1, round(target / 16))
        alpha = img.split()[3]
        grown = alpha.filter(ImageFilter.MaxFilter(pad * 2 + 1))
        ring = Image.new("RGBA", img.size, ink + (255,))
        ring.putalpha(grown)
        ring.alpha_composite(img)
        img = ring

        k = target / src["w"]
        out.append({"nominal": nominal, "w": target, "h": target,
                    "xhot": min(target - 1, round(src["xhot"] * k)),
                    "yhot": min(target - 1, round(src["yhot"] * k)),
                    "delay": src["delay"], "px": to_bgra(img)})
    return out


def rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", default="Spaceduck-Sky")
    ap.add_argument("--scale", type=float, default=SCALE)
    ap.add_argument("--outline", default=OUTLINE)
    args = ap.parse_args()

    enc = load_encoder()
    cursors = enc.find_theme(args.theme)
    if not cursors:
        print(f"emphasise: no theme named {args.theme}", file=sys.stderr)
        return 1

    ink = rgb(args.outline)
    done = set()
    for name in DRAG:
        path = os.path.join(cursors, name)
        if not os.path.exists(path):
            continue
        real = os.path.realpath(path)
        if real in done:
            continue
        images = enc.parse(real)
        if images is None:
            continue
        enc.write(real, emphasise(images, args.scale, ink))
        done.add(real)

    if not done:
        print("emphasise: no drag cursors found", file=sys.stderr)
        return 1
    print(f"emphasise: {len(done)} drag cursors at {args.scale:g}x with a grown outline: "
          + ", ".join(sorted(os.path.basename(d) for d in done)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
