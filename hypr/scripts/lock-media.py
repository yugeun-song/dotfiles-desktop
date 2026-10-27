#!/usr/bin/env python3
"""What the lock screen shows besides the time (hyprlock.conf), after the
design the user chose: the playing track as a card with its transport, the
weather under the clock.

    lock-media.py card PAINT     print the path of the card's picture; PAINT
                                 is INK[,PANE[,EDGE]] in hex (lock-colours.py
                                 chooses it per screen)
    lock-media.py glyph NAME     print a control's glyph: shuffle prev toggle
                                 next loop, nothing while nothing plays; or
                                 the island's lock
    lock-media.py click NAME     what the control does, to the same player
    lock-media.py weather        print the weather as Pango markup

The card is the bar's grown island at M times, its proportions and not its
size (the user, 2026-10-26): the cover with the title and artist, the
transport with play-pause on a disc, the position at the foot, as
quickshell/bar/modules/MediaPlayer.qml lays them out. hyprlock places a
label by its middle and the title starts at the cover's edge, so the card
is one picture per screen, transport included, drawn here with Pillow and
read by an image widget every second; hyprlock.conf lays a transparent
picture over each control for its clicks. It is redrawn only when what it
shows changes, into two files in turn, as hyprlock rereads a path only when
the path or its time changes; while nothing plays it is a transparent
picture, since a widget cannot be absent.

Inter has no Hangul, kana or emoji (a Korean title came out as boxes,
2026-10-25), so the title and the artist are set by Pango, which falls back
per letter. Pango takes a tenth of a second to start: what changes only with
the track is drawn once per track, and each second adds the position.

hyprlock runs this every second per screen while locked, so it imports
little up front and asks fontconfig once per lock; the controls run nothing
of their own (as labels run each second, they had taken a third of a core
per screen, mostly Python starting). Runs overlap, one per screen: every
file is written whole under a name of its own and renamed into place.

Drawn at twice hyprlock.conf's units, about twice the panel's size, so that
a larger screen's copy is not blown up. Covers come from local files or,
over https, from the hosts the bar trusts (Theme.artHosts in
quickshell/bar/services/Theme.qml; keep the two in step), kept in the
runtime directory, a tmpfs gone at logout.
"""

import os
import pathlib
import re
import subprocess
import sys
import zlib

# LOCK_MEDIA_RUN points the tests elsewhere: a real lock may be using this one.
RUN = pathlib.Path(os.environ.get("LOCK_MEDIA_RUN")
                   or pathlib.Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hyprlock")
CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config"))
WEATHER = os.environ.get("LOCK_WEATHER") or str(CONFIG / "quickshell/bar/scripts/weather.sh")

ART_HOSTS = {"i.scdn.co", "i.ytimg.com", "yt3.ggpht.com", "lastfm.freetls.fastly.net", "coverartarchive.org"}

# The bar's player card (Theme.qml's media* and popupPad, in its px() units)
# at M times, in hyprlock.conf's units, drawn at twice that. M keeps the
# title at the size the user set (2026-10-24) and the card about as large as
# it was. Every screen draws it at these proportions, as the island keeps
# its own: hyprlock.conf marks it and its controls "fit: even" (lock-fit.sh).
# Keep in step with Theme.qml and the controls' places in hyprlock.conf.
SCALE = 2
M = 1.6
W, H = round(540 * M), round(162 * M)
RADIUS = 22 * M
PAD = 18 * M
ART = 52 * M
ART_RADIUS = 11 * M
TEXT_X = PAD + ART + 13 * M
TITLE_SIZE = 15 * M
ARTIST_SIZE = 12 * M
NAMES_GAP = 2 * M
# The transport: cells round the middle of the card, the disc in the middle
# with its mark cut out.
CONTROL_Y = PAD + ART + 14 * M + 36 * M / 2
CELL = 32 * M
DISC = 36 * M
DISC_MARK = 13 * M
CONTROL_GAP = 18 * M
SKIP_SIZE = 24 * M
EDGE_SIZE = 21 * M
NEAR = DISC / 2 + CONTROL_GAP + CELL / 2
FAR = NEAR + CELL + CONTROL_GAP
CONTROL_X = {"shuffle": -FAR, "prev": -NEAR, "toggle": 0.0, "next": NEAR, "loop": FAR}
# The position: the times in the icon font's figures, the track between.
POSITION_Y = PAD + ART + 14 * M + 36 * M + 10 * M + 14 * M / 2
TIME_SIZE = 11 * M
TIME_GAP = 10 * M
TRACK = 4 * M
# The track as the island's quieter companion of its fill (islandDimFactor).
TRACK_ALPHA = round(0.40 * 255)
# The bar's icon font (Theme.iconFont), for the transport and the times.
ICONS = "CaskaydiaCove Nerd Font Mono"

# The instance, not the name: two of one player (firefox.instance_1_2 and
# _3) share the name, and --player NAME picks the first of them.
FIELDS = ["status", "title", "artist", "mpris:artUrl", "position", "mpris:length", "playerInstance"]

CONTROLS = ("shuffle", "prev", "toggle", "next", "loop")

# hyprlock.conf's $card_paint as written: the bar's beige on the design's
# faint white pane.
PAINT = ("ecf0c1", "ffffff1a", "ffffff33")
HEX = re.compile(r"[0-9a-fA-F]{6}([0-9a-fA-F]{2})?")
# Secondary text (artist, times, shuffle and repeat) at lock-colours.py's
# SOFT strength.
SOFT = 0xB8

# Pretendard for Hangul, as fontconfig/local.conf means it: left to
# fontconfig, Pango's Korean tag ranks Noto Sans CJK KR first, a weight
# heavier than asked. Kana, han and emoji come from whatever it finds.
FAMILIES = "Inter,Pretendard"


def part_of(path):
    return path.with_name(f"{path.name}.{os.getpid()}.part")


def keep(path, text):
    """Writes text to path unless it is there already."""
    try:
        if path.read_text(encoding="utf-8") == text:
            return
    except OSError:
        pass
    part = part_of(path)
    part.write_text(text, encoding="utf-8")
    part.replace(path)


def player():
    """The playing player's fields, else those of one with a track loaded;
    None while there is neither, as the bar's Media service chooses."""
    fmt = "\t".join("{{" + f + "}}" for f in FIELDS)
    try:
        out = subprocess.run(["playerctl", "--all-players", "metadata", "--format", fmt],
                             capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    players = []
    for line in out.splitlines():
        values = line.split("\t")
        if len(values) == len(FIELDS):
            players.append(dict(zip(FIELDS, values)))
    players = [p for p in players if p["title"]]
    playing = [p for p in players if p["status"] == "Playing"]
    return (playing or players or [None])[0]


def clock(micros):
    try:
        s = max(0, int(int(micros) / 1_000_000))
    except ValueError:
        return "-:--"
    return f"{s // 60}:{s % 60:02d}"


def cover(url):
    """A local path for the cover, or None."""
    import urllib.parse
    if url.startswith("file://"):
        path = urllib.parse.unquote(url[len("file://"):])
        return path if os.path.isfile(path) else None
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() not in ART_HOSTS:
        return None
    import hashlib
    path = RUN / "art" / hashlib.sha1(url.encode()).hexdigest()
    if not path.exists():
        import urllib.request
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                data = response.read(4 * 1024 * 1024)
        except OSError:
            return None
        part = part_of(path)
        part.write_bytes(data)
        part.replace(path)
    return str(path)


def font(style, size, family="Inter"):
    from PIL import ImageFont
    # fc-match took half of a card's drawing, three times a second.
    known = RUN / f"font-{family.replace(' ', '')}-{style}"
    try:
        found = known.read_text(encoding="utf-8")
    except OSError:
        found = subprocess.run(["fc-match", "-f", "%{file}\t%{index}", f"{family}:style={style}"],
                               capture_output=True, text=True).stdout
        if found.count("\t") == 1:
            keep(known, found)
    out = found.split("\t")
    try:
        return ImageFont.truetype(out[0], round(size * SCALE), index=int(out[1] or 0))
    except (OSError, IndexError, ValueError):
        return ImageFont.load_default(round(size * SCALE))


def fitted(draw, text, face, width):
    """The text cut with an ellipsis to the width, as the bar elides."""
    if draw.textlength(text, font=face) <= width:
        return text
    while text and draw.textlength(text + "…", font=face) > width:
        text = text[:-1]
    return text.rstrip() + "…"


def transparent():
    installed = CONFIG / "hypr/lock-blank.png"
    if installed.exists():
        return installed
    path = RUN / "none.png"
    if not path.exists():
        from PIL import Image
        part = part_of(path)
        Image.new("RGBA", (1, 1), (0, 0, 0, 0)).save(part, format="PNG")
        part.replace(path)
    return path


def share(p):
    """How far into the track, 0 to 1."""
    try:
        return max(0.0, min(1.0, int(p["position"]) / int(p["mpris:length"])))
    except (ValueError, ZeroDivisionError):
        return 0.0


def paint_of(text):
    """INK, PANE and EDGE from INK[,PANE[,EDGE]]: an old INK alone, or a part
    not in hex, keeps the default for the rest."""
    parts = [part.strip().lstrip("#") for part in text.split(",")]
    return tuple(parts[i] if i < len(parts) and HEX.fullmatch(parts[i]) else PAINT[i] for i in range(3))


def rgba(hexa):
    return tuple(int(hexa[i:i + 2], 16) for i in range(0, len(hexa), 2)) + (() if len(hexa) == 8 else (255,))


def card(paint):
    RUN.mkdir(parents=True, exist_ok=True)
    p = player()
    if p is None:
        print(transparent())
        return
    art = cover(p["mpris:artUrl"])
    # Tabs and newlines cannot occur: playerctl's lines were split on them.
    look = ",".join(paint)
    key = "\t".join([p["title"], p["artist"], art or "", clock(p["position"]), clock(p["mpris:length"]),
                     str(round(share(p) * 600)), p["status"], look])
    # Its own files per look: two screens drawing two looks into the same
    # pair would take turns overwriting the picture the other shows.
    tag = f"{zlib.crc32(look.encode()):08x}"
    state = RUN / f"card-{tag}"
    try:
        last_key, last_path = state.read_text(encoding="utf-8").split("\n")[:2]
    except (OSError, ValueError):
        last_key, last_path = "", ""
    if last_key == key and os.path.exists(last_path):
        print(last_path)
        return
    # The key starts with the title, the artist and the cover.
    face = RUN / f"face-{tag}.png"
    if last_key.split("\t")[:3] != key.split("\t")[:3] or not face.exists():
        draw_face(p, art, paint, face)
    path = RUN / (f"card-{tag}-b.png" if last_path.endswith("-a.png") else f"card-{tag}-a.png")
    draw_card(p, paint, face, path)
    keep(state, f"{key}\n{path}\n")
    print(path)


def save(im, path):
    part = part_of(path)
    # The least compression: drawn every second per screen while a track
    # plays, into a tmpfs, and compressing took three quarters of a draw.
    im.save(part, format="PNG", compress_level=1)
    part.replace(path)


def draw_face(p, art, paint, path):
    """The card as long as the track lasts: pane, cover, title and artist,
    and the transport but play-pause, which follows the player."""
    from PIL import Image, ImageDraw
    s = SCALE
    ink = rgba(paint[0])[:3]
    im = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # Frosted: the design's card is a pane with a hairline edge, lighter or
    # darker as the wallpaper behind it needs (lock-colours.py).
    d.rounded_rectangle((0, 0, W * s - 1, H * s - 1), RADIUS * s, fill=rgba(paint[1]),
                        outline=rgba(paint[2]), width=2 * s)

    side = round(ART * s)
    corner = (round(PAD * s), round(PAD * s))
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side - 1, side - 1), ART_RADIUS * s, fill=255)
    picture = None
    if art:
        # Any failure, not only OSError: a fetched cover is untrusted, and a
        # decompression bomb or a broken chunk raises other errors.
        try:
            picture = Image.open(art).convert("RGB")
        except Exception:
            picture = None
    if picture is not None:
        edge = min(picture.size)
        left, top = (picture.width - edge) // 2, (picture.height - edge) // 2
        picture = picture.crop((left, top, left + edge, top + edge)).resize((side, side), Image.LANCZOS)
        im.paste(picture, corner, mask)
    else:
        im.paste(Image.new("RGBA", (side, side), ink + (40,)), corner, mask)

    # The names take the row: the island's waveform beside them is left out,
    # as a picture drawn once a second cannot follow the sound.
    room = round((W - TEXT_X - PAD) * s)
    left = round(TEXT_X * s)
    middle = (PAD + ART / 2) * s
    title_h, artist_h, gap = TITLE_SIZE * s * 1.2, ARTIST_SIZE * s * 1.2, NAMES_GAP * s
    top = middle - (title_h + gap + artist_h) / 2
    rows = ((p["title"], "SemiBold", TITLE_SIZE, 255, top),
            (p["artist"], "Medium", ARTIST_SIZE, SOFT, top + title_h + gap))
    try:
        words = set_by_pango(rows, ink, room, H * s)
    except (ImportError, ValueError):
        # Without PyGObject or pycairo: Inter alone, Hangul as boxes.
        for text, style, size, alpha, y in rows:
            typeface = font(style, size)
            d.text((left, y), fitted(d, text, typeface, room), font=typeface, fill=ink + (alpha,))
    else:
        im.alpha_composite(words, (left, 0))

    # Shuffle and repeat quieter than the skips, as in the design.
    skip, edge = font("Regular", SKIP_SIZE, ICONS), font("Regular", EDGE_SIZE, ICONS)
    for name in ("shuffle", "prev", "next", "loop"):
        near = name in ("prev", "next")
        d.text(((W / 2 + CONTROL_X[name]) * s, CONTROL_Y * s), GLYPHS[name], font=skip if near else edge,
               fill=ink + (255 if near else SOFT,), anchor="mm")
    save(im, path)


def pango():
    """Pango, PangoCairo and cairo; ImportError or ValueError without them."""
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    import cairo
    from gi.repository import Pango, PangoCairo
    return Pango, PangoCairo, cairo


def row_layout(context, text, weight, size, width):
    """A row of text set in FAMILIES, size and width in the picture's pixels,
    cut with an ellipsis to fit as the bar elides; and its font."""
    Pango = pango()[0]
    desc = Pango.FontDescription.from_string(f"{FAMILIES} {weight}")
    desc.set_absolute_size(size * Pango.SCALE)
    layout = Pango.Layout.new(context)
    layout.set_font_description(desc)
    # An Arabic or a Hebrew title still starts at the cover.
    layout.set_auto_dir(False)
    layout.set_width(width * Pango.SCALE)
    layout.set_ellipsize(Pango.EllipsizeMode.END)
    layout.set_text(text, -1)
    return layout, desc


def set_by_pango(rows, ink, width, height):
    """The rows (text, weight, size, alpha, top) as a picture width wide. A
    row's baseline sits where Inter's would, whatever font a letter comes
    from: Noto Sans CJK is taller, and would push a Japanese title down."""
    Pango, PangoCairo, cairo = pango()
    from PIL import Image
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(surface)
    context = PangoCairo.create_context(cr)
    # Grey: hyprlock scales the picture to the screen, and subpixel
    # fringes, if fontconfig asks for them, would show as colour.
    options = cairo.FontOptions()
    options.set_antialias(cairo.ANTIALIAS_GRAY)
    PangoCairo.context_set_font_options(context, options)
    for text, weight, size, alpha, top in rows:
        layout, desc = row_layout(context, text, weight, size * SCALE, width)
        ascent = context.get_metrics(desc, None).get_ascent() / Pango.SCALE
        cr.move_to(0, top + ascent - layout.get_baseline() / Pango.SCALE)
        cr.set_source_rgba(*(c / 255 for c in ink), alpha / 255)
        PangoCairo.show_layout(cr, layout)
    surface.flush()
    # cairo's ARGB32 is premultiplied and in the machine's byte order,
    # little-endian on every machine this desktop runs on.
    return Image.frombuffer("RGBA", (width, height), bytes(surface.get_data()), "raw", "BGRa",
                            surface.get_stride(), 1)


def draw_card(p, paint, face, path):
    """The track's face with play-pause as the player is and how far into
    the track it is."""
    from PIL import Image, ImageDraw
    s = SCALE
    ink = rgba(paint[0])[:3]
    soft = ink + (SOFT,)
    with Image.open(face) as kept:
        im = kept.convert("RGBA")
    side = round(DISC * s)
    im.alpha_composite(disc(ink, p["status"] == "Playing", side),
                       (round(W / 2 * s - side / 2), round(CONTROL_Y * s - side / 2)))
    d = ImageDraw.Draw(im)
    # Each time in the whole time's width, the elapsed one to its right, as
    # the island's: the track keeps its length as the seconds turn.
    time_face = font("Regular", TIME_SIZE, ICONS)
    elapsed, whole = clock(p["position"]), clock(p["mpris:length"])
    y = POSITION_Y * s
    reach = d.textlength(whole, font=time_face)
    d.text((PAD * s + reach, y), elapsed, font=time_face, fill=soft, anchor="rm")
    d.text(((W - PAD) * s - reach, y), whole, font=time_face, fill=soft, anchor="lm")
    x0, x1 = PAD * s + reach + TIME_GAP * s, (W - PAD) * s - reach - TIME_GAP * s
    t = TRACK * s
    d.rounded_rectangle((x0, y - t / 2, x1, y + t / 2), t / 2, fill=ink + (TRACK_ALPHA,))
    d.rounded_rectangle((x0, y - t / 2, max(x0 + t, x0 + (x1 - x0) * share(p)), y + t / 2), t / 2,
                        fill=ink + (255,))
    save(im, path)


def disc(ink, playing, side):
    """Play-pause as the island draws it (MediaPlayer.qml), side pixels
    across: a disc in the ink with pause's two bars or play's rounded
    triangle cut out. Drawn four times over and shrunk, for smooth edges."""
    from PIL import Image, ImageDraw
    n = side * 4
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, n - 1, n - 1), fill=ink + (255,))
    g = n * DISC_MARK / DISC
    mid = n / 2
    clear = (0, 0, 0, 0)
    if playing:
        bar, high = 0.26 * g, 0.86 * g
        for x in (mid - bar * 1.5, mid + bar * 0.5):
            d.rounded_rectangle((x, mid - high / 2, x + bar, mid + high / 2), max(4, bar / 4), fill=clear)
    else:
        # Nudged right: a triangle's weight sits a sixth of its width left
        # of the middle of its box.
        wide, inset = 0.84 * g, max(4, 0.07 * g)
        left = mid - wide / 2 + wide / 6
        corners = [(left + inset, mid - g / 2 + inset), (left + wide - inset, mid),
                   (left + inset, mid + g / 2 - inset)]
        d.polygon(corners, fill=clear)
        d.line(corners + corners[:1], fill=clear, width=round(2 * inset), joint="curve")
        for x, y in corners:
            d.ellipse((x - inset, y - inset, x + inset, y + inset), fill=clear)
    return im.resize((side, side), Image.LANCZOS)


# The bar's transport glyphs (Theme.qml's iconShuffle, iconPrev, iconNext,
# iconRepeat): keep the two in step.
GLYPHS = {
    "shuffle": "\U000F049D",   # md-shuffle
    "prev": "\U000F04AE",      # md-skip_previous
    "next": "\U000F04AD",      # md-skip_next
    "loop": "\U000F0456",      # md-repeat
    "play": "\U000F040A",      # md-play
    "pause": "\U000F03E4",     # md-pause
    "lock": "\U000F033E",      # md-lock, the island's, there with or without a player
}


def control_glyph(p, name):
    if p is None:
        return ""
    if name == "toggle":
        return GLYPHS["pause" if p["status"] == "Playing" else "play"]
    return GLYPHS.get(name, "")


def glyph(name):
    print(GLYPHS["lock"] if name == "lock" else control_glyph(player(), name))


def click(name):
    p = player()
    if p is None:
        return
    ctl = ["playerctl", "--player", p["playerInstance"]]
    if name == "loop":
        # Off -> playlist -> track, as the island's control.
        state = subprocess.run(ctl + ["loop"], capture_output=True, text=True).stdout.strip()
        following = {"None": "Playlist", "Playlist": "Track"}.get(state, "None")
        subprocess.run(ctl + ["loop", following], capture_output=True)
        return
    action = {"shuffle": ["shuffle", "toggle"], "prev": ["previous"], "next": ["next"],
              "toggle": ["play-pause"]}.get(name)
    if action:
        subprocess.run(ctl + action, capture_output=True)


# The bar's Theme.weatherIcon, by WMO code: keep the two in step.
def weather_icon(code, day):
    if code == 0:
        return "\U000F0599" if day else "\U000F0594"
    if code in (1, 2):
        return "\uEEF0" if day else "\uEEEF"
    if code in (3, 45, 48):
        return ""
    if 51 <= code <= 57 or 61 <= code <= 63:
        return "\uEF1C"
    if code == 65 or 80 <= code <= 82:
        return "\uEF1D"
    if code in (66, 67):
        return "\uEF1A"
    if 71 <= code <= 77 or code in (85, 86):
        return "\U000F0598"
    if code >= 95:
        return "\uEF2C"
    return ""


def weather():
    import json
    try:
        out = subprocess.run([WEATHER, "--bar"], capture_output=True, text=True, timeout=8).stdout
        data = json.loads(out.strip().splitlines()[-1])
        code, temp, day = int(data["code"]), int(data["temp"]), data.get("day") == 1
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, IndexError, TypeError):
        print("")
        return
    # The full-size variant: the Mono one fits a glyph to one narrow cell, a
    # dot beside the number, and a size in markup does not take (hyprlock
    # sizes the whole label). Its ink is wider than its advance: an en space.
    print(f'<span font_family="CaskaydiaCove Nerd Font">{weather_icon(code, day)}</span>\u2002  {temp}°')


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "card":
        card(paint_of(sys.argv[2]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "glyph":
        glyph(sys.argv[2])
    elif len(sys.argv) >= 3 and sys.argv[1] == "click":
        click(sys.argv[2])
    elif len(sys.argv) >= 2 and sys.argv[1] == "weather":
        weather()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
