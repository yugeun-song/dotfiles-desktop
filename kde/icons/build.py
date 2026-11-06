#!/usr/bin/env python3
"""The SpaceduckLines icon theme: line icons the user chose (2026-11-06, in
the manner of lucide.dev), taken from Lucide (ISC, its LICENSE kept beside the
theme) for the places, the kinds of file and the common actions that Dolphin
and the file dialogs show; every other name falls back to Breeze
(Inherits=breeze-dark).

    build.py --from DIR [--out DIR]
                write the theme (kde/icons/SpaceduckLines/ unless --out names
                another place) from DIR's icons/ and LICENSE

Each icon is redrawn for KDE: its strokes in the text's colour by the
colour scheme KDE writes into every monochrome icon it loads
(.ColorScheme-Text), so the icons take the palette's ink and turn to the
selection's in a selected row, as Breeze's monochrome ones do. An SVG's stroke
grows with its size, and the size a program asks for is not the size it draws:
with a fractionally scaled screen on the desktop, Qt asks twice over for an icon
it draws small (the sidebar's 18 as 36, the toolbar's 22 as 44, measured with a
theme of one directory per size), while Dolphin's list asks for 22 or 33 as the
screen's scale has it. So the sidebar drew 0.75 px beside the list's 1.6 (the
user, 2026-11-06: the two differ, and make them heavier). Each range below
sets its stroke for what is drawn from it, to come out about 1.9 px on the screen,
the weight of the file icons in the same list (files.py). From 49 px up it is
lighter, where the same stroke drawn larger came out heavy (the icons view, 64).

The theme is committed as written here, Lucide's paths unchanged, from the
commit upstream.lock pins of Lucide's official Git repository: verify.py writes
theme and lock together (--update) and checks them on every new content, so
nothing else fetches Lucide, and install.sh copies only what verify.py passed.
"""

import argparse
import pathlib
import re
import shutil
import sys
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "SpaceduckLines"
INK = "#ecf0c1"
SVG_NS = "http://www.w3.org/2000/svg"

# Lucide's name, the contexts and freedesktop names it stands for. The names
# of its Git repository: packages add aliases (music, trash-2) it has no file for.
MAP = {
    # Places: the sidebar's and the special folders'.
    "house": [("places", "user-home"), ("places", "folder-home"), ("actions", "go-home")],
    "monitor": [("places", "user-desktop"), ("places", "desktop")],
    "file-text": [("places", "folder-documents"), ("places", "folder-document"),
                  ("mimetypes", "text-plain"), ("mimetypes", "text-x-generic"), ("mimetypes", "text-markdown"),
                  ("mimetypes", "text-x-readme"), ("mimetypes", "text-x-log"), ("mimetypes", "x-office-document"),
                  ("mimetypes", "application-pdf"), ("mimetypes", "application-vnd.oasis.opendocument.text"),
                  ("mimetypes", "application-msword"), ("mimetypes", "application-rtf")],
    "circle-arrow-down": [("places", "folder-download"), ("places", "folder-downloads")],
    "eighth-notes": [("places", "folder-music"), ("places", "folder-sound")],
    "image": [("places", "folder-pictures"), ("places", "folder-picture"), ("places", "folder-image"),
              ("places", "folder-images")],
    "film": [("places", "folder-videos"), ("places", "folder-video"), ("places", "folder-movies")],
    "users": [("places", "folder-public"), ("places", "folder-publicshare")],
    "layout-template": [("places", "folder-templates"), ("places", "folder-template")],
    "trash": [("places", "user-trash"), ("places", "user-trash-full"), ("actions", "edit-delete"),
                ("actions", "trash-empty")],
    "globe": [("places", "network-workgroup"), ("places", "folder-network")],
    "server": [("places", "folder-remote"), ("places", "network-server"), ("devices", "network-server")],
    "folder": [("places", "folder"), ("mimetypes", "inode-directory"), ("places", "folder-grey")],
    "folder-open": [("places", "folder-open"), ("places", "folder-drag-accept")],
    "clock": [("places", "folder-recent"), ("actions", "document-open-recent")],
    "calendar-check": [("actions", "go-jump-today")],
    "calendar": [("actions", "view-calendar-day"), ("actions", "view-calendar"),
                 ("actions", "view-calendar-week"), ("actions", "view-calendar-month")],
    "search": [("places", "folder-saved-search"), ("actions", "edit-find"), ("actions", "system-search")],
    "tag": [("places", "tag"), ("actions", "tag")],
    # Devices.
    "hard-drive": [("devices", "drive-harddisk"), ("devices", "drive-harddisk-encrypted"),
                   ("devices", "drive-harddisk-root"), ("places", "drive-harddisk")],
    "usb": [("devices", "drive-removable-media"), ("devices", "drive-removable-media-usb"),
            ("devices", "media-removable")],
    "disc": [("devices", "media-optical"), ("devices", "drive-optical")],
    "smartphone": [("devices", "phone"), ("devices", "smartphone")],
    # Kinds of file.
    "file": [("mimetypes", "application-octet-stream"), ("mimetypes", "unknown"), ("mimetypes", "application-x-zerosize"),
             ("mimetypes", "inode-x-empty")],
    "file-code": [("mimetypes", n) for n in (
        "text-x-csrc", "text-x-chdr", "text-x-c++src", "text-x-c++hdr", "text-x-python", "text-x-python3",
        "text-x-rust", "text-x-go", "text-x-java", "text-x-javascript", "application-javascript",
        "application-x-javascript", "text-html", "application-xhtml+xml", "application-json", "text-x-makefile",
        "text-x-cmake", "text-css", "application-xml", "text-xml", "text-x-lua", "application-x-yaml",
        "text-x-yaml", "application-toml", "text-x-qml", "text-x-patch", "text-x-diff")],
    "file-terminal": [("mimetypes", "application-x-shellscript"), ("mimetypes", "text-x-shellscript"),
                      ("mimetypes", "text-x-script"), ("mimetypes", "application-x-sh"),
                      ("mimetypes", "application-x-executable-script")],
    "file-image": [("mimetypes", n) for n in (
        "image-x-generic", "image-png", "image-jpeg", "image-svg+xml", "image-gif", "image-webp", "image-bmp",
        "image-tiff", "image-x-xcf", "image-avif", "image-heif")],
    "file-music": [("mimetypes", n) for n in (
        "audio-x-generic", "audio-mpeg", "audio-flac", "audio-x-flac", "audio-ogg", "audio-x-wav", "audio-mp4",
        "audio-x-vorbis+ogg", "audio-x-opus+ogg")],
    "file-play": [("mimetypes", n) for n in (
        "video-x-generic", "video-mp4", "video-x-matroska", "video-webm", "video-quicktime", "video-x-msvideo")],
    "file-archive": [("mimetypes", n) for n in (
        "package-x-generic", "application-zip", "application-x-tar", "application-x-compressed-tar",
        "application-x-bzip-compressed-tar", "application-x-xz-compressed-tar", "application-x-7z-compressed",
        "application-x-rar", "application-gzip", "application-x-zstd-compressed-tar", "application-x-archive")],
    "file-spreadsheet": [("mimetypes", "x-office-spreadsheet"), ("mimetypes", "application-vnd.oasis.opendocument.spreadsheet"),
                         ("mimetypes", "text-csv"), ("mimetypes", "application-vnd.ms-excel")],
    "presentation": [("mimetypes", "x-office-presentation"), ("mimetypes", "application-vnd.oasis.opendocument.presentation")],
    "file-cog": [("mimetypes", "application-x-executable"), ("mimetypes", "application-x-sharedlib"),
                 ("mimetypes", "application-x-object")],
    # Actions the file manager's toolbar and menus show.
    "chevron-left": [("actions", "go-previous")],
    "chevron-right": [("actions", "go-next")],
    "arrow-up": [("actions", "go-up")],
    "menu": [("actions", "application-menu"), ("actions", "open-menu")],
    "layout-grid": [("actions", "view-list-icons")],
    "list": [("actions", "view-list-details"), ("actions", "view-list-text")],
    "list-tree": [("actions", "view-list-tree")],
    "folder-plus": [("actions", "folder-new")],
    "copy": [("actions", "edit-copy")],
    "clipboard-paste": [("actions", "edit-paste")],
    "scissors": [("actions", "edit-cut")],
    "refresh-cw": [("actions", "view-refresh")],
    "info": [("actions", "document-properties")],
    "eye-off": [("actions", "view-hidden")],
    "plus": [("actions", "list-add")],
    "minus": [("actions", "list-remove")],
    "x": [("actions", "window-close"), ("actions", "dialog-close"), ("actions", "tab-close")],
    "pencil": [("actions", "edit-rename"), ("actions", "document-edit")],
    "share-2": [("actions", "document-share")],
    "settings": [("actions", "configure")],
    "columns-2": [("actions", "view-split-left-right")],
}

# Each size range its stroke, in Lucide's 24 units: 2.5 at 18 px and 2.05 at 22 px
# are both about 1.9 px. The ranges are what is asked for, so the 18 drawn from 36
# has 2.5 and the 22 drawn from 33 or 44 has 2.05.
RANGES = [("scalable-small", 18, 8, 20, 2.5), ("scalable-sidebar", 21, 21, 21, 2.8), ("scalable", 24, 22, 35, 2.05),
          ("scalable-small-2x", 36, 36, 40, 2.5), ("scalable-sidebar-2x", 42, 42, 42, 2.8), ("scalable-2x", 44, 43, 48, 2.05),
          ("scalable-large", 64, 49, 512, 1.0)]
# Dolphin's places panel asks for 21 (42 twice over), a size nothing else asks for, and
# draws its text 4 px after the box of the icon, which nothing can change
# (s_lateralMargin, kfileplacesview.cpp). So at that size the glyph stands in a box with
# room to its right and a little to its left: the words move away from the icons and the
# icons in from the lit row's edge, as in the sidebars the user sent (2026-11-07), the
# glyph still about 16 px. The box's height makes the rows taller too (dolphinrc's
# [PlacesPanel] IconSize, install.sh; kde/dolphin.qss has the rest).
VIEWS = {"scalable-sidebar": "-1.5 -3.5 31 31", "scalable-sidebar-2x": "-1.5 -3.5 31 31"}
CONTEXTS = {"places": "Places", "mimetypes": "MimeTypes", "devices": "Devices", "actions": "Actions"}


# What an icon may hold, and nothing else: plain shapes and their geometry,
# a fill of none or the ink. A file from outside is untrusted: an SVG can
# carry scripts, links to other files and to the network, and styles that
# fetch; a shape, an attribute or a value outside these stops the build.
SHAPES = {"path", "circle", "rect", "line", "polyline", "polygon", "ellipse"}
GEOMETRY = {"d", "cx", "cy", "r", "rx", "ry", "x", "y", "width", "height", "x1", "y1", "x2", "y2", "points"}
VALUE = re.compile(r"^[0-9eE.,\- +A-Za-z]*$")


def drawn(source, stroke, view="0 0 24 24"):
    """Lucide's shapes inside one group in the colour scheme's ink."""
    root = ET.parse(source).getroot()
    shapes = []
    for child in root:
        tag = child.tag.split("}", 1)[-1]
        if tag not in SHAPES or len(child):
            sys.exit(f"build.py: {source.name}: a <{tag}> is no plain shape")
        for key, value in child.attrib.items():
            if key == "fill" and value in ("none", "currentColor"):
                continue
            if key not in GEOMETRY or not VALUE.match(value) or "url" in value.lower():
                sys.exit(f"build.py: {source.name}: <{tag} {key}=...> is not geometry")
        attrs = "".join(f' {k}="{v}"' for k, v in child.attrib.items())
        shapes.append(f"    <{tag}{attrs}/>")
    return (
        f'<svg xmlns="{SVG_NS}" width="24" height="24" viewBox="{view}">\n'
        "  <!-- From Lucide (ISC License; LICENSE beside this theme), recoloured for KDE. -->\n"
        f'  <defs><style type="text/css" id="current-color-scheme">.ColorScheme-Text {{ color:{INK}; }}</style></defs>\n'
        f'  <g class="ColorScheme-Text" style="fill:none;stroke:currentColor" stroke-width="{stroke}"'
        ' stroke-linecap="round" stroke-linejoin="round">\n'
        + "\n".join(shapes) + "\n  </g>\n</svg>\n"
    )


def index(used):
    dirs = [f"{rng}/{ctx}" for rng, *_ in RANGES for ctx in sorted(used)]
    out = [
        "[Icon Theme]",
        "Name=SpaceduckLines",
        "Comment=Line icons from Lucide for places, files and common actions; Breeze for the rest",
        "Inherits=breeze-dark,hicolor",
        "Directories=" + ",".join(dirs),
        "",
    ]
    for rng, size, low, high, _ in RANGES:
        for ctx in sorted(used):
            out += [f"[{rng}/{ctx}]", f"Size={size}", f"MinSize={low}", f"MaxSize={high}",
                    f"Context={CONTEXTS[ctx]}", "Type=Scalable", ""]
    return "\n".join(out)


def write_theme(source, out):
    """The whole theme at `out` from `source`'s icons/ and LICENSE."""
    icons = source / "icons"
    licence = source / "LICENSE"
    missing = [name for name in MAP if not (icons / f"{name}.svg").is_file()]
    if missing or not licence.is_file():
        sys.exit(f"build.py: not in {source}: {' '.join(missing) or 'LICENSE'}")
    if out.exists():
        shutil.rmtree(out)
    used = set()
    for name, targets in MAP.items():
        for rng, _, _, _, stroke in RANGES:
            text = drawn(icons / f"{name}.svg", stroke, VIEWS.get(rng, "0 0 24 24"))
            for ctx, fdo in targets:
                path = out / rng / ctx / f"{fdo}.svg"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
                used.add(ctx)
    (out / "index.theme").write_text(index(used), encoding="utf-8")
    shutil.copyfile(licence, out / "LICENSE")
    return sum(1 for _ in out.rglob("*.svg"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--from", dest="source", required=True, type=pathlib.Path,
                        help="a directory holding icons/ and LICENSE")
    parser.add_argument("--out", type=pathlib.Path, default=OUT, help="where the theme goes")
    args = parser.parse_args()
    count = write_theme(args.source, args.out)
    print(f"SpaceduckLines: {count} icons from {len(MAP)} of Lucide's")


if __name__ == "__main__":
    main()
