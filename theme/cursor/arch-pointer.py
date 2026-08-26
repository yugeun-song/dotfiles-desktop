#!/usr/bin/env python3

# Replaces the plain arrow of a generated cursor theme with the Arch logo.
#
# This runs after tint-cursors.py and overwrites one file. Everything else in
# the theme stays as that script left it: the resize handles, the text caret and
# the hands are shapes with a meaning, and a logo in place of any of them would
# be decoration standing where information used to be. The arrow is the one
# cursor that says nothing except "here", so it is the one that can carry a mark
# without costing anything.
#
# Three things have to be true for a logo to work as a pointer at all.
#
# The tip has to be a tip. The Arch logo is a triangle with an apex two pixels
# wide at the top, and the hotspot is put exactly there, so what the pointer
# claims to be pointing at is what it is pointing at. A logo centred in its box
# with the hotspot guessed at the middle is the usual way this is done badly.
#
# It has to be visible on any background. A #7dcfff shape alone disappears the
# moment it crosses anything pale, so every size gets a dark outline grown from
# its own alpha channel rather than a border drawn at a fixed width.
#
# Every size has to be rendered, not scaled. The source is an SVG, so each size
# is rasterised from it. That is worth stating because the theme this replaces a
# cursor in carries only 24, 48 and 72, and a request for anything else there is
# served by stretching the nearest one.

import argparse
import importlib.util
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageFilter

# The sizes a client is likely to ask for. Anything not on this list is served
# by XCursor picking the nearest, which is the case this list exists to make
# rare rather than to make impossible.
SIZES = (16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 96, 128)

SOURCE = "/usr/share/pixmaps/archlinux-logo.svg"

# Rasterise well above the largest target and reduce from there. Going straight
# to 16 pixels from the SVG loses the notch between the legs entirely; coming
# down from 512 with a windowed filter keeps it as a grey hint, which is what it
# should be at that size.
SUPERSAMPLE = 512


def load_encoder():
    # tint-cursors.py owns the Xcursor writer, and a second copy of a binary
    # format is a second thing to get wrong. The hyphen in the name is why this
    # is loaded by path rather than imported.
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tint-cursors.py")
    spec = importlib.util.spec_from_file_location("tint_cursors", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def render_source():
    # Cropped to its own opaque bounds. The SVG carries about four percent of
    # empty margin on every side, and keeping it would put the apex four percent
    # below the top of every cursor, which is four percent of a lie about where
    # the pointer is.
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as fh:
        tmp = fh.name
    try:
        subprocess.run(["rsvg-convert", "-w", str(SUPERSAMPLE), "-h", str(SUPERSAMPLE),
                        SOURCE, "-o", tmp], check=True, capture_output=True)
        im = Image.open(tmp).convert("RGBA")
    finally:
        os.unlink(tmp)
    box = im.split()[3].getbbox()
    if not box:
        raise SystemExit("arch-pointer: the logo rendered empty")
    return im.crop(box)


def apex(alpha, floor=40):
    # The x of the topmost opaque run, taken as its centre. Read off the image
    # rather than assumed to be the middle: the logo is symmetric today and a
    # hotspot that depends on that staying true is a hotspot that moves when the
    # package updates.
    w, h = alpha.size
    px = alpha.load()
    for y in range(h):
        run = [x for x in range(w) if px[x, y] >= floor]
        if run:
            return (run[0] + run[-1]) // 2, y
    raise SystemExit("arch-pointer: no opaque pixel in the logo")


def build(logo, size, fill, outline):
    # The outline is grown from the alpha channel, so it follows the notch and
    # the flared legs instead of boxing them in. One pixel up to 32, two beyond:
    # a fixed width looks heavy when small and vanishes when large.
    pad = 1 if size <= 32 else 2
    inner = size - pad * 2
    if inner < 4:
        return None

    scaled = logo.resize((inner, inner), Image.LANCZOS)
    a = Image.new("L", (size, size), 0)
    a.paste(scaled.split()[3], (pad, pad))

    grown = a.filter(ImageFilter.MaxFilter(pad * 2 + 1))

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (size, size), outline + (255,)), (0, 0), grown)
    out.paste(Image.new("RGBA", (size, size), fill + (255,)), (0, 0), a)

    xh, yh = apex(a)
    return out, xh, yh


def to_bgra(im):
    # Xcursor stores premultiplied BGRA. Skipping the multiply leaves a pale
    # halo everywhere the outline fades out, which is most of its edge.
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
    ap.add_argument("--fill", default="#7dcfff")
    ap.add_argument("--outline", default="#0f111b")
    ap.add_argument("--name", default="left_ptr",
                    help="the cursor file to replace; every standard alias for "
                         "the plain arrow already points at it")
    args = ap.parse_args()

    if not os.path.exists(SOURCE):
        print(f"arch-pointer: {SOURCE} is missing; the arrow is unchanged", file=sys.stderr)
        return 1

    enc = load_encoder()
    cursors = enc.find_theme(args.theme)
    if not cursors:
        print(f"arch-pointer: no theme named {args.theme}", file=sys.stderr)
        return 1

    logo = render_source()
    fill, outline = rgb(args.fill), rgb(args.outline)

    images = []
    for size in SIZES:
        built = build(logo, size, fill, outline)
        if not built:
            continue
        im, xh, yh = built
        images.append({"nominal": size, "w": size, "h": size,
                       "xhot": xh, "yhot": yh, "delay": 0, "px": to_bgra(im)})

    target = os.path.join(cursors, args.name)
    # A symlink here would be replaced by a file and the alias it stood for would
    # be lost, so refuse rather than guess. tint-cursors.py writes left_ptr as a
    # real file, which is the case this is written for.
    if os.path.islink(target):
        print(f"arch-pointer: {args.name} is a link, not the arrow itself", file=sys.stderr)
        return 1

    enc.write(target, images)
    print(f"arch-pointer: {args.theme}/{args.name} is the Arch logo in {args.fill}: "
          f"{len(images)} sizes, hotspot at the apex")
    return 0


if __name__ == "__main__":
    sys.exit(main())
