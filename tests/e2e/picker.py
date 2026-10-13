#!/usr/bin/env python3
"""Find the badge picker in two captures of one region, for tests/e2e/run.sh.

Usage: picker.py BEFORE AFTER

BEFORE is taken with the picker closed, AFTER with it open. Prints JSON: the
picker's box, the centre of its Automatic row, and per grid tile, in reading
order, the centre and the size of the mark's ink, all in the captures'
pixels. Exits 1 when nothing opened, 2 when what opened is not a grid.

Ink is what is drawn in the foreground colour: the muted name under the grid
and the tints behind tiles stay below INK, so the first band of ink is the
Automatic row and every later band is a row of marks. A mark is measured in
its whole cell against the lower EDGE, which keeps the anti-aliased rim of a
thin stroke (KDE neon's ring read 14 px of its 19 at INK).
"""

import hashlib
import json
import sys

from PIL import Image, ImageChops

INK = 150
EDGE = 90
ROW_GAP = 6
MARK_GAP = 8
ALIGN = 4

before = Image.open(sys.argv[1]).convert("L")
after = Image.open(sys.argv[2]).convert("L")
box = ImageChops.difference(before, after).point(lambda v: 255 if v > 24 else 0).getbbox()
if box is None:
    sys.exit(1)
x0, y0, x1, y1 = box
px = after.load()


def runs(values, gap):
    out = []
    for v in values:
        if out and v - out[-1][1] <= gap + 1:
            out[-1][1] = v
        else:
            out.append([v, v])
    return out


def inked(xs, ys, level):
    return [(x, y) for y in ys for x in xs if px[x, y] > level]


def pitch(centres):
    steps = sorted(b - a for a, b in zip(centres, centres[1:]))
    return steps[len(steps) // 2] if steps else None


rows = runs([y for y in range(y0, y1) if any(px[x, y] > INK for x in range(x0, x1))], ROW_GAP)
if len(rows) < 2:
    sys.exit(2)
auto, rows = rows[0], rows[1:]

bands = []
for top, bottom in rows:
    cols = runs([x for x in range(x0, x1) if any(px[x, y] > INK for y in range(top, bottom + 1))], MARK_GAP)
    bands.append((top, bottom, cols))

# Columns from the fullest row; every other row's marks must sit on them.
widest = max(bands, key=lambda b: len(b[2]))[2]
centres = [(a + b) / 2 for a, b in widest]
across = pitch(centres)
down = pitch([(t + b) / 2 for t, b, _ in bands]) or across
if across is None:
    sys.exit(2)
tiles = []
for top, bottom, cols in bands:
    for a, b in cols:
        c = (a + b) / 2
        if min(abs(c - k) for k in centres) > ALIGN + (b - a) / 2:
            print(json.dumps({"error": "a mark off the grid", "at": [a, top]}))
            sys.exit(2)
        m = (top + bottom) / 2
        ink = inked(range(round(c - across / 2) + 2, round(c + across / 2) - 1),
                    range(round(m - down / 2) + 2, round(m + down / 2) - 1), EDGE)
        xs = [x for x, _ in ink]
        ys = [y for _, y in ink]
        tiles.append({
            "x": round(c), "y": round(m),
            "w": max(xs) - min(xs) + 1, "h": max(ys) - min(ys) + 1,
            "ink": hashlib.sha1(repr([(x - min(xs), y - min(ys)) for x, y in ink]).encode()).hexdigest()[:16],
        })

print(json.dumps({
    "box": [x0, y0, x1 - x0, y1 - y0],
    "automatic": [x0 + (x1 - x0) // 4, (auto[0] + auto[1]) // 2],
    "tiles": tiles,
}))
