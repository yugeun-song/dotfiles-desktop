#!/usr/bin/env python3
"""The lock screen's layout and colours for the Quickshell lock
(quickshell/bar/lock.qml): what hyprlock would draw on each screen, read
from lock-fit.sh's copy of hyprlock.conf, as JSON.

    lock-spec.py FITTED   print FITTED, lock-fit.sh's output, as JSON

hyprlock.conf stays the lock screen's design (the user's, 2026-10-24 to
2026-11-02) and the locker lock.sh falls back to; lock-fit.sh fits it to
each screen and lock-colours.py colours it against each screen's wallpaper.
This reads their result, so the two lockers draw one design in one set of
colours and the numbers live in one file.

Each output: its mode and the two factors lock-fit.sh used (its header),
then the background, the island and its three labels, the date, the clock,
the weather, the card and the field, each with the numbers hyprlock.conf
gives it, in that screen's pixels. An output lock-fit.sh had no mode for
holds the design's numbers as written, for the lock to fit to a screen that
appears while it is locked, with the reference and the scale it needs. A
colour is #AARRGGBB, as QML reads one. A block marked "fit: even" says so:
its widths take the screen's height factor, not its width's. A background
picture with a .video link beside it (wallpaper.sh sets one for a video)
names that video too, for the lock to play under its blur.

Exits 1, printing nothing, when the file names no output.
"""

import json
import os
import re
import sys

HEADER = re.compile(r"^# (\S+) (?:(\d+)x(\d+)|no mode) fit ([0-9.]+) wide ([0-9.]+)\s*$")
RGBA = re.compile(r"rgba\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})?\)")
REFERENCE = re.compile(r"^\$fit_reference\s*=\s*(\d+)x(\d+)")
SCALE = re.compile(r"^\$fit_scale\s*=\s*([0-9.]+)")
EVEN = re.compile(r"^\s*#\s*fit:\s*even\s*$")
# lock-fit.sh's STRETCH_MAX: keep in step.
STRETCH_MAX = 1.25

# strftime's fields in the date label's command, as Qt.formatDateTime
# writes them.
DATE_FIELDS = {"%a": "ddd", "%A": "dddd", "%d": "dd", "%-d": "d", "%e": "d", "%b": "MMM", "%B": "MMMM",
               "%m": "MM", "%-m": "M", "%Y": "yyyy", "%y": "yy"}


def bare(line):
    """The line without its comment; "##" is hyprlang's "#"."""
    s = line.replace("##", "\x01")
    s = s.split("#", 1)[0]
    return s.replace("\x01", "#").strip()


def colour(value):
    m = RGBA.fullmatch(value.strip())
    if not m:
        return None
    return f"#{(m.group(2) or 'ff')}{m.group(1)}".lower()


def numbers(value):
    try:
        return [float(p.strip().removesuffix("px")) for p in value.split(",")]
    except ValueError:
        return None


def number(value, default=0.0):
    got = numbers(value or "")
    return got[0] if got else default


def blocks(text):
    """Top-level blocks as {type, keys, even}; lines between them skipped."""
    out, current, depth = [], None, 0
    for raw in text.splitlines():
        s = bare(raw)
        if current is not None and depth == 1 and EVEN.match(raw):
            current["even"] = True
        if not s:
            continue
        if s.endswith("{") and "=" not in s:
            depth += 1
            if depth == 1:
                current = {"type": s[:-1].strip(), "keys": {}, "even": False}
            continue
        if s == "}":
            depth = max(0, depth - 1)
            if depth == 0 and current is not None:
                out.append(current)
                current = None
            continue
        if current is not None and depth == 1 and "=" in s:
            key, value = s.split("=", 1)
            current["keys"][key.strip()] = value.strip()
    return out


def date_format(command):
    m = re.search(r'date \+"([^"]*)"', command)
    if not m:
        return "ddd, d MMM"
    fmt = m.group(1)
    for field in sorted(DATE_FIELDS, key=len, reverse=True):
        fmt = fmt.replace(field, DATE_FIELDS[field])
    return fmt


def text_of(markup):
    """A placeholder's words without its markup."""
    return re.sub(r"<[^>]*>", "", markup).strip()


def label(keys, even):
    return {
        "font_size": number(keys.get("font_size"), 16),
        "font_family": keys.get("font_family", ""),
        "color": colour(keys.get("color", "")) or "#ffecf0c1",
        "position": numbers(keys.get("position", "0, 0")) or [0, 0],
        "halign": keys.get("halign", "center"),
        "valign": keys.get("valign", "center"),
        "halo": int(number(keys.get("shadow_passes"), 0)),
        "halo_size": number(keys.get("shadow_size"), 0),
        "glow": colour(keys.get("shadow_color", "")) or "#a6000000",
        "even": even,
    }


def video_beside(path):
    """The video a picture stands for, by the link wallpaper.sh keeps beside
    it, or "" where there is none or it names nothing any more."""
    if not path:
        return ""
    link = os.path.splitext(path)[0] + ".video"
    target = os.path.realpath(link) if os.path.islink(link) else ""
    return target if target and os.path.isfile(target) else ""


def describe(block):
    """(part, spec) for a block the lock draws, or None."""
    kind, keys, even = block["type"], block["keys"], block["even"]
    if kind == "background":
        path = os.path.expanduser(keys.get("path", ""))
        return "background", {
            "path": path,
            "video": video_beside(path),
            "color": colour(keys.get("color", "")) or "#ff000000",
            "blur_passes": int(number(keys.get("blur_passes"), 0)),
            "blur_size": number(keys.get("blur_size"), 0),
            "brightness": number(keys.get("brightness"), 1),
            "contrast": number(keys.get("contrast"), 1),
            "vibrancy": number(keys.get("vibrancy"), 0),
        }
    if kind == "shape":
        return "island", {
            "size": numbers(keys.get("size", "0, 0")) or [0, 0],
            # Black, as hyprlock.conf's $island_fill is before lock-colours.py
            # fills it in.
            "color": colour(keys.get("color", "")) or "#ff000000",
            "rounding": number(keys.get("rounding"), 0),
            "position": numbers(keys.get("position", "0, 0")) or [0, 0],
            "halign": keys.get("halign", "center"),
            "valign": keys.get("valign", "center"),
            "even": even,
        }
    if kind == "label":
        text = keys.get("text", "")
        for part in ("lead", "trail", "mark"):
            if re.search(rf"\$island {part}\b", text):
                return part, label(keys, even)
        if "date +" in text:
            spec = label(keys, even)
            spec["format"] = date_format(text)
            return "date", spec
        if text.strip() == "$TIME":
            return "time", label(keys, even)
        if "weather" in text:
            return "weather", label(keys, even)
        return None
    if kind == "image" and " card " in keys.get("reload_cmd", "") + " ":
        paint = keys["reload_cmd"].split(" card ", 1)[1].split()[0].split(",") if " card " in keys["reload_cmd"] else []
        paint = (paint + ["ecf0c1", "ffffff1a", "ffffff33"][len(paint):])[:3]
        return "card", {
            "size": number(keys.get("size"), 0),
            "position": numbers(keys.get("position", "0, 0")) or [0, 0],
            "paint": paint,
            "even": even,
        }
    if kind == "input-field":
        return "field", {
            "size": numbers(keys.get("size", "400, 90")) or [400, 90],
            "position": numbers(keys.get("position", "0, 0")) or [0, 0],
            "halign": keys.get("halign", "center"),
            "valign": keys.get("valign", "center"),
            "font_family": keys.get("font_family", ""),
            "color": colour(keys.get("font_color", "")) or "#ffecf0c1",
            "placeholder": text_of(keys.get("placeholder_text", "")) or "Press to unlock",
            "dots_size": number(keys.get("dots_size"), 0.13),
            "dots_spacing": number(keys.get("dots_spacing"), 0.35),
            "even": even,
        }
    return None


def spec(text):
    reference, scale = [2880, 1800], 1.0
    outputs = {}
    for line in text.splitlines():
        m = HEADER.match(line)
        if m:
            mode = [int(m.group(2)), int(m.group(3))] if m.group(2) else None
            outputs[m.group(1)] = {"mode": mode, "fit": float(m.group(4)), "wide": float(m.group(5))}
            continue
        m = REFERENCE.match(line)
        if m:
            reference = [int(m.group(1)), int(m.group(2))]
            continue
        m = SCALE.match(line)
        if m:
            scale = float(m.group(1))
    for block in blocks(text):
        name = block["keys"].get("monitor", "")
        if name not in outputs:
            continue
        found = describe(block)
        if found:
            outputs[name][found[0]] = found[1]
    return {"reference": reference, "scale": scale, "stretch_max": STRETCH_MAX, "outputs": outputs}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            got = spec(fh.read())
    except OSError:
        sys.exit(1)
    if not got["outputs"]:
        sys.exit(1)
    json.dump(got, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
