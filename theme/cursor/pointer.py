#!/usr/bin/env python3

# Draws the plain arrow of a generated cursor theme instead of recolouring one.
#
# Runs after tint-cursors.py and replaces only left_ptr. The other cursors
# carry meaning and stay as tinted; redrawing them would be a second cursor
# theme kept in Python.
#
# Drawn, not tinted, because readability is shape, not colour: a recoloured
# Oxygen arrow keeps its hairline edge and its three bitmap sizes stretched to
# every other request. Wanted: a heavy dark outline, round joins, flat fill.
#
# Every size is rasterised from the path, and the hotspot is read off the
# rendered tip; a hotspot guessed at the box corner is off by a pixel or two,
# in a different direction at each size.

import argparse
import importlib.util
import os
import subprocess
import sys
import tempfile

from PIL import Image

# The arrow as the centre line of its outline, in a space 90 tall: tip, long
# edge to the right shoulder, in to the heel (the notch that makes it an arrow,
# not a play button), out to the tail foot; the left edge closes it.
#
# Fitted to the reference drawing: both are classified per pixel as background,
# fill or outline, and scored by shape overlap at their best alignment (cross
# correlation). Raw pixel agreement let a shape trade position error for size
# and it settled 5.7% too wide. Width is pinned to the drawing's ratio, 0.7690
# of the height including the outline: 94.5% overlap instead of 95.6% floating,
# but never wider than the original.
OUTLINE = [(10.00, 3.00), (78.07, 66.50), (39.08, 62.20), (10.35, 93.00)]

# The notch is the one value not taken from the drawing. The drawing's barely
# cuts in and reads as a clipped triangle, so it is pulled 15% of the way
# towards the tip. Narrow band: less and the notch vanishes at 24 px; more and it
# becomes a barbed arrowhead. Depth also eats fill, which carries the colour:
# fill area at 24 px is 113, 79, 61, 44 px at 0, 20, 30, 40% depth, and past a
# third the lower barb is outline only.

# Outline width as a fraction of cursor height: the drawing's 15 px on 290.
STROKE = 15.0 / 290.0

# Below ~40 px the fraction stops being a line: at 24 (the size in use,
# hypr/config/env.lua) it is 1.2 px, which antialiasing turns into a soft edge.
# So small sizes get this floor and are drawn slightly heavier, as icon sets do.
MIN_STROKE_PX = 2.0

# Measured from the reference drawing, not taken from Theme.qml. FILL is also
# the single source of the whole theme's tint: install.sh reads this line and
# passes it to tint-cursors.py, so the pointer does not change colour on its way
# onto a link. Keep the `FILL = "#rrggbb"` form; install.sh parses it with sed.
FILL = "#1d89e4"
INK = "#212121"

# Sizes clients are likely to request; others get XCursor's nearest match.
SIZES = (16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 96, 128)


def load_encoder():
    # tint-cursors.py owns the Xcursor writer; one copy of a binary format.
    # Loaded by path because of the hyphen in its name.
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tint-cursors.py")
    spec = importlib.util.spec_from_file_location("tint_cursors", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def stroke_for(size, outline):
    # Stroke in path units for a given pixel width. The viewBox includes the
    # stroke, so widening it widens the box it is measured against; solved in
    # closed form rather than iterated.
    if outline == "none":
        return 0.0
    span = max(y for _, y in OUTLINE) - min(y for _, y in OUTLINE)
    px = max(MIN_STROKE_PX, STROKE * size)
    if px >= size:
        return 0.0
    return px * span / (size - px)


def svg(fill, outline, sw):
    # viewBox = stroked bounds, so the shape touches every edge and no size
    # wastes a margin.
    xs = [p[0] for p in OUTLINE]
    ys = [p[1] for p in OUTLINE]
    x0, y0 = min(xs) - sw / 2, min(ys) - sw / 2
    w, h = (max(xs) - min(xs)) + sw, (max(ys) - min(ys)) + sw
    d = "M " + " L ".join(f"{x} {y}" for x, y in OUTLINE) + " Z"
    edge = "" if sw == 0 else (f'stroke="{outline}" stroke-width="{sw}" '
                               f'stroke-linejoin="round" stroke-linecap="round"')
    doc = (f'<svg xmlns="http://www.w3.org/2000/svg" '
           f'viewBox="{x0} {y0} {w} {h}">'
           f'<path d="{d}" fill="{fill}" {edge}/></svg>')
    return doc, w / h


def render(doc, aspect, size):
    w = max(1, round(size * aspect))
    with tempfile.NamedTemporaryFile(suffix=".svg", delete=False) as fh:
        fh.write(doc.encode())
        src = fh.name
    dst = src[:-4] + ".png"
    try:
        subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(size), src, "-o", dst],
                       check=True, capture_output=True)
        im = Image.open(dst).convert("RGBA")
    finally:
        os.unlink(src)
        if os.path.exists(dst):
            os.unlink(dst)

    # Left-aligned in a square canvas (a cursor has one size number); the spare
    # columns fall on the right, away from the tip.
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, (0, 0))
    return canvas


def tip(im, floor=40):
    # Centre of the topmost opaque run. Read off the image because the round
    # join moves the visible point inside the path corner by a size-dependent
    # amount.
    a = im.split()[3].load()
    w, h = im.size
    for y in range(h):
        run = [x for x in range(w) if a[x, y] >= floor]
        if run:
            return (run[0] + run[-1]) // 2, y
    raise SystemExit("pointer: nothing was drawn")


def to_bgra(im):
    # Xcursor stores premultiplied BGRA; without the multiply every
    # antialiased edge gets a pale halo.
    px = im.load()
    w, h = im.size
    buf = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            buf += bytes((b * a // 255, g * a // 255, r * a // 255, a))
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", default="Spaceduck-Sky")
    ap.add_argument("--fill", default=FILL)
    ap.add_argument("--outline", default=INK,
                    help='a colour, or "none" for a flat shape with no edge')
    ap.add_argument("--name", default="left_ptr",
                    help="the cursor file to replace; every standard alias for "
                         "the plain arrow already points at it")
    args = ap.parse_args()

    enc = load_encoder()
    cursors = enc.find_theme(args.theme)
    if not cursors:
        print(f"pointer: no theme named {args.theme}", file=sys.stderr)
        return 1

    images = []
    for size in SIZES:
        # One document per size: the stroke fraction varies with size.
        doc, aspect = svg(args.fill, args.outline, stroke_for(size, args.outline))
        im = render(doc, aspect, size)
        xh, yh = tip(im)
        images.append({"nominal": size, "w": size, "h": size,
                       "xhot": xh, "yhot": yh, "delay": 0, "px": to_bgra(im)})

    target = os.path.join(cursors, args.name)
    # Refuse a symlink: writing would replace it and lose the alias.
    # tint-cursors.py writes left_ptr as a real file.
    if os.path.islink(target):
        print(f"pointer: {args.name} is a link, not the arrow itself", file=sys.stderr)
        return 1

    enc.write(target, images)
    edge = "no outline" if args.outline == "none" else f"outlined in {args.outline}"
    print(f"pointer: {args.theme}/{args.name} drawn in {args.fill}, {edge}: "
          f"{len(images)} sizes, hotspot at the tip")
    return 0


if __name__ == "__main__":
    sys.exit(main())
