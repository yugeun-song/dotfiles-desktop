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

# The arrow, as the centre line of its own outline, in a space 100 tall.
#
# Tip, then the long edge down to the right shoulder, then back in to the heel,
# then out to the foot of the tail. The left edge closes it. The notch between
# the shoulder and the heel is what separates an arrow from a triangle: without
# it the shape reads as a play button.
#
# These are not eyeballed. They were fitted against the reference drawing by
# rendering a candidate, classifying every pixel of both as background, fill or
# outline, and walking each number until the agreement stopped improving: 89.1%
# to 96.1%, the remainder being antialiasing and the reference's own uneven
# corners. Note that the tip sits slightly to the right of the foot, so the left
# edge leans rather than dropping straight; that came out of the fit and it is
# what stops the shape reading as a right triangle.
OUTLINE = [(11.75, 3), (82.25, 66.5), (42.75, 69), (10, 93)]

# Fraction of the shape's height, when there is an outline at all. Measured off
# the reference, where the dark band along the left edge is 15 pixels against a
# path 275 tall, and then confirmed by the same fit as the coordinates above.
#
# It carries its weight twice. Against a busy window it is what keeps a light
# fill visible at all, which a hairline edge does not; and at the small end it
# is the outline, not the fill, that keeps the notch readable, because at 24
# pixels the notch is two dark lines before it is ever a gap.
STROKE = 0.052

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


def svg(fill, outline):
    # The viewBox is the stroked bounds rather than the path's, so the shape
    # meets every edge of what is rendered and no size wastes a margin it would
    # then have to be scaled up to make up for. With no outline the two are the
    # same thing.
    xs = [p[0] for p in OUTLINE]
    ys = [p[1] for p in OUTLINE]
    sw = 0.0 if outline == "none" else STROKE * (max(ys) - min(ys))
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

    doc, aspect = svg(args.fill, args.outline)
    images = []
    for size in SIZES:
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
