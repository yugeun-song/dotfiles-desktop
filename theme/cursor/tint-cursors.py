#!/usr/bin/env python3
"""Build a tinted XCursor theme from one already installed.

Cursor themes are bitmaps with the colour baked into them, so a themed pointer
is not something a setting can ask for: it has to be drawn. Drawing 26 shapes
by hand to change one colour is not a good trade, and recolouring what is
already there keeps every hotspot, every size and every alias exactly as the
source theme had them.

Tinting is by luminance rather than by replacing a colour. The black outline
stays black, the white body becomes the tint, and the grey shading in between
lands proportionally, so the drawing keeps the shape that makes it readable
against both a dark and a light window.

Output goes to a directory of its own under ~/.local/share/icons. The source
theme is never touched: it belongs to a package, and pacman would overwrite an
edit at the next upgrade without saying so.

Usage:
    tint-cursors.py --from Oxygen_White --name Spaceduck-Sky --tint '#7dcfff'
"""

import argparse
import os
import shutil
import struct
import sys

XCURSOR_MAGIC = b"Xcur"
CHUNK_IMAGE = 0xFFFD0002


def parse(path):
    """Every image chunk in an Xcursor file, in file order.

    The format is a fixed header, a table of contents, then chunks. Only image
    chunks matter here; a theme may also carry comment chunks, and those are
    dropped rather than rewritten because nothing reads them.
    """
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != XCURSOR_MAGIC:
        return None
    _, _, ntoc = struct.unpack("<III", data[4:16])
    out = []
    for i in range(ntoc):
        ctype, subtype, pos = struct.unpack("<III", data[16 + i * 12 : 28 + i * 12])
        if ctype != CHUNK_IMAGE:
            continue
        w, h, xhot, yhot, delay = struct.unpack("<IIIII", data[pos + 16 : pos + 36])
        px = bytearray(data[pos + 36 : pos + 36 + w * h * 4])
        if len(px) != w * h * 4:
            return None
        out.append({"nominal": subtype, "w": w, "h": h,
                    "xhot": xhot, "yhot": yhot, "delay": delay, "px": px})
    return out


def tint(px, rgb):
    """Recolour in place. Pixels are BGRA, premultiplied by alpha.

    Un-premultiplying before measuring luminance matters: a half-transparent
    white pixel is stored as mid-grey, and treating that as grey would tint the
    antialiased edge darker than the body it belongs to.
    """
    r_t, g_t, b_t = rgb
    for i in range(0, len(px), 4):
        a = px[i + 3]
        if a == 0:
            continue
        b = min(255, px[i] * 255 // a)
        g = min(255, px[i + 1] * 255 // a)
        r = min(255, px[i + 2] * 255 // a)
        lum = (r * 299 + g * 587 + b * 114) // 1000
        px[i] = (b_t * lum // 255) * a // 255
        px[i + 1] = (g_t * lum // 255) * a // 255
        px[i + 2] = (r_t * lum // 255) * a // 255
    return px


def write(path, images):
    toc = b""
    chunks = b""
    header_len = 16 + len(images) * 12
    offset = header_len
    for im in images:
        toc += struct.pack("<III", CHUNK_IMAGE, im["nominal"], offset)
        body = struct.pack("<IIII", 36, CHUNK_IMAGE, im["nominal"], 1)
        body += struct.pack("<IIIII", im["w"], im["h"], im["xhot"], im["yhot"], im["delay"])
        body += bytes(im["px"])
        chunks += body
        offset += len(body)
    with open(path, "wb") as fh:
        fh.write(XCURSOR_MAGIC)
        fh.write(struct.pack("<III", 16, 0x10000, len(images)))
        fh.write(toc)
        fh.write(chunks)


def find_theme(name):
    for base in (os.path.expanduser("~/.local/share/icons"),
                 os.path.expanduser("~/.icons"),
                 "/usr/share/icons"):
        d = os.path.join(base, name, "cursors")
        if os.path.isdir(d):
            return d
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="source", default="Oxygen_White")
    ap.add_argument("--name", default="Spaceduck-Sky")
    ap.add_argument("--tint", default="#7dcfff")
    ap.add_argument("--comment", default="")
    args = ap.parse_args()

    src = find_theme(args.source)
    if not src:
        print(f"tint-cursors: no theme named {args.source}", file=sys.stderr)
        return 1

    h = args.tint.lstrip("#")
    if len(h) != 6:
        print(f"tint-cursors: --tint wants #rrggbb, got {args.tint}", file=sys.stderr)
        return 1
    rgb = tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))

    root = os.path.join(os.path.expanduser("~/.local/share/icons"), args.name)
    dst = os.path.join(root, "cursors")
    # Rebuilt from nothing every time. Leaving old files behind would keep a
    # shape the source theme has since dropped, and the only symptom would be
    # one pointer out of thirty in the wrong colour.
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(dst, exist_ok=True)

    made = skipped = linked = 0
    # Real files first: a symlink cannot be created before its target exists.
    entries = sorted(os.listdir(src))
    for name in entries:
        path = os.path.join(src, name)
        if os.path.islink(path):
            continue
        images = parse(path)
        if images is None:
            skipped += 1
            continue
        for im in images:
            tint(im["px"], rgb)
        write(os.path.join(dst, name), images)
        made += 1

    for name in entries:
        path = os.path.join(src, name)
        if not os.path.islink(path):
            continue
        target = os.readlink(path)
        if os.path.exists(os.path.join(dst, target)):
            os.symlink(target, os.path.join(dst, name))
            linked += 1

    with open(os.path.join(root, "index.theme"), "w") as fh:
        fh.write("[Icon Theme]\n")
        fh.write(f"Name={args.name}\n")
        fh.write(f"Comment={args.comment or f'{args.source} tinted {args.tint}'}\n")
        fh.write("Inherits=Adwaita\n")

    print(f"tint-cursors: {args.name} <- {args.source} at {args.tint}: "
          f"{made} cursors, {linked} aliases"
          + (f", {skipped} skipped (not Xcursor)" if skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
