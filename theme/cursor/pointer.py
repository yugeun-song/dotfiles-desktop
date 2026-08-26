#!/usr/bin/env python3

# Draws the plain arrow of a generated cursor theme instead of recolouring one.
#
# This runs after tint-cursors.py and overwrites one file. Everything else in
# the theme stays as that script left it: the resize handles, the text caret and
# the hands are shapes with a meaning, and redrawing them here would be a second
# cursor theme kept in a Python file. The arrow is the one cursor that says
# nothing except "here", so it is the one worth drawing.
#
# It is drawn rather than tinted because the two things that make a pointer
# readable are not colour. A recoloured Oxygen arrow keeps Oxygen's hairline
# edge, which disappears against a busy window at any size; and it keeps
# Oxygen's bitmaps, which exist at three sizes and are stretched for every other
# request. What is wanted is a heavy dark outline, round joins and a flat fill,
# and all three are properties of a shape, not of a palette.
#
# The geometry is a path, so every size is rasterised from it rather than scaled
# from a neighbour, and the hotspot is read back off the rendered image at the
# tip rather than assumed. A pointer whose hotspot is guessed at the corner of
# its box is off by a pixel or two at every size, in a different direction each
# time.

import argparse
import importlib.util
import os
import subprocess
import sys
import tempfile

from PIL import Image

# The arrow, as the centre line of its own outline, in a space 90 tall.
#
# Tip, then the long edge down to the right shoulder, then back in to the heel,
# then out to the foot of the tail. The left edge closes it. The notch between
# the shoulder and the heel is what separates an arrow from a triangle: without
# it the shape reads as a play button.
#
# Fitted against the reference drawing rather than judged by eye. A candidate is
# rendered, both it and the drawing are classified pixel by pixel as background,
# fill or outline, and the score is the overlap of the two shapes at their best
# alignment, found through their cross correlation so that where each one sits
# never enters into it. Scoring on raw pixel agreement instead, over a canvas
# they mostly share as white, let a shape buy back a positioning error by
# growing: it settled 5.7% too wide and looked it.
#
# The width is not among the fitted numbers. It is pinned to the drawing's own
# ratio, 0.7690 of the height once the outline is counted, so nothing the search
# tries can come out wider than the thing it copies. That costs about a point of
# overlap against letting it float, 94.5% rather than 95.6%, and buys a shape
# that is the right shape.
OUTLINE = [(10.00, 3.00), (78.07, 66.50), (39.08, 62.20), (10.35, 93.00)]

# The notch is the one number here that is not the drawing's. The drawing barely
# cuts into the back, which reads as a triangle with a corner clipped off, so
# this one is pulled 15% of the way from where the drawing puts it towards the
# tip: enough that the back is hollowed and the shape reads as an arrow rather
# than a wedge.
#
# It is a narrow band to work in. Below this the notch stops registering at 24
# pixels; much above it the shape turns into a barbed arrowhead, which is more
# than a pointer should be saying. Depth also costs fill, and the fill is what
# carries the colour: blue area falls 113, 79, 61 and 44 pixels across depths of
# 0, 20, 30 and 40 percent, so past a third of the way the lower barb at 24
# pixels is an outline with nothing inside it.

# Outline width as a fraction of the rendered cursor, measured off the drawing:
# a 15 pixel band down a shape 290 tall.
STROKE = 15.0 / 290.0

# Below roughly 40 pixels that fraction stops being a line. At 24, the size this
# is actually used at, it comes to 1.2 pixels, which antialiasing turns into a
# soft edge rather than the black border the drawing has. So the fraction is a
# floor from here up and this is a floor from here down; the shape is drawn
# slightly heavier when small, which is the trade every icon set makes.
MIN_STROKE_PX = 2.0

# Both measured from the reference drawing rather than taken from Theme.qml.
#
# The rest of the theme is recoloured to the bar's accentSky by tint-cursors.py,
# and these are deliberately not that: the arrow was asked for in the colours of
# a particular drawing, and a pointer is looked at on its own, never beside the
# resize handles it would be compared against.
FILL = "#1d89e4"
INK = "#212121"

# The sizes a client is likely to ask for. Anything not here is served by
# XCursor picking the nearest, which this list exists to make rare.
SIZES = (16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 96, 128)


def load_encoder():
    # tint-cursors.py owns the Xcursor writer, and a second copy of a binary
    # format is a second thing to get wrong. The hyphen in its name is why this
    # is loaded by path rather than imported.
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tint-cursors.py")
    spec = importlib.util.spec_from_file_location("tint_cursors", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def stroke_for(size, outline):
    # Answers in path units, given what the outline has to measure in pixels
    # once drawn. The viewBox spans the path plus the stroke, and that whole
    # span is what maps onto `size`, so the two are tangled: widening the stroke
    # widens the box it is measured against. Solving for it directly is shorter
    # than iterating and lands exactly.
    if outline == "none":
        return 0.0
    span = max(y for _, y in OUTLINE) - min(y for _, y in OUTLINE)
    px = max(MIN_STROKE_PX, STROKE * size)
    if px >= size:
        return 0.0
    return px * span / (size - px)


def svg(fill, outline, sw):
    # The viewBox is the stroked bounds rather than the path's, so the shape
    # meets every edge of what is rendered and no size wastes a margin it would
    # then have to be scaled up to make up for. With no outline the two are the
    # same thing.
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

    # Left-aligned in a square canvas. A cursor is addressed by one number and
    # this shape is taller than it is wide, so the spare column is on the right,
    # away from the tip, where nothing is ever drawn.
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, (0, 0))
    return canvas


def tip(im, floor=40):
    # The topmost opaque run, taken at its centre. Read off the image because
    # the round join puts the visible point a little inside the path's corner,
    # by an amount that depends on the size being rendered.
    a = im.split()[3].load()
    w, h = im.size
    for y in range(h):
        run = [x for x in range(w) if a[x, y] >= floor]
        if run:
            return (run[0] + run[-1]) // 2, y
    raise SystemExit("pointer: nothing was drawn")


def to_bgra(im):
    # Xcursor stores premultiplied BGRA. Skipping the multiply leaves a pale
    # halo along every antialiased edge, which on a heavy outline is most of it.
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
        # A separate document per size, because the stroke is not the same
        # fraction at every one of them.
        doc, aspect = svg(args.fill, args.outline, stroke_for(size, args.outline))
        im = render(doc, aspect, size)
        xh, yh = tip(im)
        images.append({"nominal": size, "w": size, "h": size,
                       "xhot": xh, "yhot": yh, "delay": 0, "px": to_bgra(im)})

    target = os.path.join(cursors, args.name)
    # A symlink here would be replaced by a file and the alias it stood for
    # would be lost, so refuse rather than guess. tint-cursors.py writes
    # left_ptr as a real file, which is the case this is written for.
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
