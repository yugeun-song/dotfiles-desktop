#!/usr/bin/env python3
"""Build a tinted XCursor theme from an installed one.

Cursor colours are baked into bitmaps, so a themed pointer has to be drawn.
Recolouring an existing theme keeps every hotspot, size and alias.

Tinting is by luminance, not colour replacement: black outline stays black,
the white body becomes the tint, grey shading lands proportionally, so the
shape stays readable on dark and light windows.

Output goes to its own directory under ~/.local/share/icons. The source theme
belongs to a package and is never modified (pacman would silently undo it).

Usage (--tint defaults to pointer.py's FILL, which install.sh also passes):
    tint-cursors.py --from Oxygen_White --name Spaceduck-Sky --tint '#1d89e4'
"""

import argparse
import os
import re
import shutil
import struct
import sys

XCURSOR_MAGIC = b"Xcur"
CHUNK_IMAGE = 0xFFFD0002

# cursor-shape-v1 names mapped to their legacy X names. Clients on that
# protocol ask for "default", which Oxygen_White lacks, so the main pointer went
# untinted while hand-set cursors (X names) were fine. Added only where the
# target exists, so this completes any source theme rather than assuming one.
SHAPE_ALIASES = {
    "default": "left_ptr",
    "context-menu": "left_ptr",
    "help": "help",
    "pointer": "pointing_hand",
    "progress": "half-busy",
    "wait": "wait",
    "cell": "plus",
    "crosshair": "cross",
    "text": "xterm",
    "vertical-text": "xterm",
    "alias": "link",
    "copy": "copy",
    "move": "fleur",
    "no-drop": "forbidden",
    "not-allowed": "forbidden",
    "grab": "openhand",
    "grabbing": "closedhand",
    "all-scroll": "fleur",
    "col-resize": "split_h",
    "row-resize": "split_v",
    "ew-resize": "size_hor",
    "ns-resize": "size_ver",
    "nesw-resize": "size_bdiag",
    "nwse-resize": "size_fdiag",
    "zoom-in": "left_ptr",
    "zoom-out": "left_ptr",
}


def parse(path):
    """Every image chunk in an Xcursor file, in file order.

    Layout: header, table of contents, chunks. Comment chunks are dropped;
    nothing reads them.
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


def luminance_of(px, i, a):
    """Un-premultiplied luminance of one BGRA pixel.

    Half-transparent white is stored as mid-grey; measuring it premultiplied
    would tint antialiased edges darker than their body.
    """
    b = min(255, px[i] * 255 // a)
    g = min(255, px[i + 1] * 255 // a)
    r = min(255, px[i + 2] * 255 // a)
    return (r * 299 + g * 587 + b * 114) // 1000


def body_level(images, floor=150):
    """A cursor's body luminance: the commonest opaque level above `floor`.

    Oxygen's bodies differ (arrow #efefef, move #e6e6e6, resize #e8e8e8), and
    a straight luminance map made three visibly different blues. Normalising to
    each cursor's own body makes them one colour. The floor keeps the black
    outline out; the hand is mostly outline and would measure near black.
    """
    counts = {}
    for im in images:
        px = im["px"]
        for i in range(0, len(px), 4):
            a = px[i + 3]
            if a < 250:
                continue
            lum = luminance_of(px, i, a)
            if lum >= floor:
                counts[lum] = counts.get(lum, 0) + 1
    if not counts:
        return 255
    return max(counts.items(), key=lambda kv: (kv[1], kv[0]))[0]


def tint(px, rgb, full=255):
    """Recolour premultiplied BGRA pixels in place.

    `full` (the cursor's body level, not 255) maps to the tint exactly; brighter
    pixels clamp.
    """
    r_t, g_t, b_t = rgb
    full = max(1, full)
    for i in range(0, len(px), 4):
        a = px[i + 3]
        if a == 0:
            continue
        lum = min(255, luminance_of(px, i, a) * 255 // full)
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


def pointer_fill():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pointer.py")
    try:
        with open(path, encoding="utf-8") as f:
            m = re.search(r'^FILL = "(#[0-9a-fA-F]{6})"', f.read(), re.M)
    except OSError:
        return None
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="source", default="Oxygen_White")
    ap.add_argument("--name", default="Spaceduck-Sky")
    fill = pointer_fill()
    ap.add_argument("--tint", default=fill, required=fill is None)
    ap.add_argument("--comment", default="")
    args = ap.parse_args()

    src = find_theme(args.source)
    if not src:
        print(f"tint-cursors: no theme named {args.source}", file=sys.stderr)
        return 1

    h = args.tint.lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", h):
        print(f"tint-cursors: --tint wants #rrggbb, got {args.tint}", file=sys.stderr)
        return 1
    rgb = tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))

    root = os.path.join(os.path.expanduser("~/.local/share/icons"), args.name)
    dst = os.path.join(root, "cursors")
    # Rebuilt from scratch: a stale file would leave one pointer in thirty
    # the wrong colour.
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
        # Measured across all sizes before tinting, so one file is one colour.
        full = body_level(images)
        for im in images:
            tint(im["px"], rgb, full)
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

    # Add missing shape names only; the source's own names win.
    added = 0
    for name, target in SHAPE_ALIASES.items():
        link = os.path.join(dst, name)
        if os.path.exists(link) or os.path.islink(link):
            continue
        if not os.path.exists(os.path.join(dst, target)):
            continue
        os.symlink(target, link)
        added += 1

    with open(os.path.join(root, "index.theme"), "w") as fh:
        fh.write("[Icon Theme]\n")
        fh.write(f"Name={args.name}\n")
        fh.write(f"Comment={args.comment or f'{args.source} tinted {args.tint}'}\n")
        fh.write("Inherits=Adwaita\n")

    print(f"tint-cursors: {args.name} <- {args.source} at {args.tint}: "
          f"{made} cursors, {linked} aliases, {added} shape names added"
          + (f", {skipped} skipped (not Xcursor)" if skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
