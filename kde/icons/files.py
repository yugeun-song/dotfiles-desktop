#!/usr/bin/env python3
"""The SpaceduckFiles icon theme: each kind of file told apart at a glance, as an
editor's file icons do (the user, 2026-11-06, who asked for open source, well
kept, safe and free of licence trouble). Only files: colour goes on files, and
every folder stays one colour (the user, the same day), so the theme names no
folder and SpaceduckLines, which it sits over (Inherits), draws them all and
every other name.

    files.py --from DIR --out DIR [--mime DIR]
                write the theme at --out from DIR's copy of the upstream files,
                naming what that machine's MIME database (--mime) knows

The drawings are Material Icon Theme's (MIT; its LICENSE goes beside the theme).
Chosen on 2026-11-06, at v5.40.0, against the others of its kind:
  - vscode-icons says MIT on its repository page, but its README puts the icons
    under CC BY-SA and the branded ones under their owners' terms, and seven of
    its SVGs hold a <script>;
  - Symbols has an SVG that loads an <image>, and a single maintainer;
  - Catppuccin's last commit by a person was in 2025-10;
  - Papirus is GPL-3.0, against this repository's 0BSD.

They are not committed. Many are the logos of languages and tools, and a marks'
owner has rights no drawing's licence gives away, so this repository ships none
(as with the bar's distribution marks). It holds this table and files.lock;
verify.py fetches the files from the official Git repository at install time,
checks each by hash and has this script write the theme into the user's own
icon directory. A theme that is not there costs only the colour: KDE stays on
SpaceduckLines.

KDE takes a file's icon from its MIME type alone, so an extension or a file name
the system has no type for is given one in kde/mime/code-files.xml.
"""

import argparse
import pathlib
import re
import shutil
import sys
import xml.etree.ElementTree as ET

OFFICIAL = "https://github.com/material-extensions/vscode-material-icon-theme.git"
SVG_NS = "http://www.w3.org/2000/svg"
# Upstream generates its plain file at build time, in the colour of its default
# configuration, from path data this file holds. It stands for what has no kind.
GENERATOR = "src/core/generator/fileGenerator.ts"
PLAIN = "#90a4ae"
PLAIN_NAMES = ["application-octet-stream", "unknown", "application-x-zerosize", "inode-x-empty"]

# Upstream's icon, and the MIME types' icon names it stands for. An alias needs
# no row: the database answers with the type it stands for.
MAP = {
    # C, the kernel's languages and their build files.
    "c": ["text-x-csrc"],
    "h": ["text-x-chdr"],
    "cpp": ["text-x-c++src"],
    "hpp": ["text-x-c++hdr"],
    "assembly": ["text-x-asm"],
    "makefile": ["text-x-makefile", "text-x-kconfig", "text-x-kbuild"],
    "cmake": ["text-x-cmake"],
    "meson": ["text-x-meson"],
    "tree": ["text-x-devicetree-source"],
    "tune": ["text-x-linker-script", "text-x-conf", "text-x-editorconfig"],
    "diff": ["text-x-patch", "text-x-reject"],
    # Other languages.
    "rust": ["text-rust"],
    "go": ["text-x-go"],
    "python": ["text-x-python", "text-x-python2", "text-x-python3", "application-x-python-bytecode"],
    "java": ["text-x-java"],
    "javaclass": ["application-x-java"],
    "jar": ["application-x-java-archive"],
    "javascript": ["text-javascript"],
    "typescript": ["application-typescript", "text-vnd.trolltech.linguist"],
    "react": ["text-x-jsx"],
    "react_ts": ["text-x-tsx"],
    "lua": ["text-x-lua"],
    "perl": ["application-x-perl"],
    "php": ["application-x-php"],
    "ruby": ["application-x-ruby"],
    "kotlin": ["text-x-kotlin"],
    "swift": ["text-x-swift"],
    "scala": ["text-x-scala"],
    "haskell": ["text-x-haskell"],
    "ocaml": ["text-x-ocaml"],
    "zig": ["text-x-zig"],
    "nim": ["text-x-nim"],
    "dart": ["application-vnd.dart"],
    "csharp": ["text-x-csharp"],
    "d": ["text-x-dsrc"],
    "objective-c": ["text-x-objcsrc"],
    "objective-cpp": ["text-x-objc++src"],
    "fortran": ["text-x-fortran"],
    "ada": ["text-x-adasrc"],
    "tcl": ["text-tcl"],
    "vala": ["text-x-vala"],
    "verilog": ["text-x-verilog", "text-x-vhdl"],
    "erlang": ["text-x-erlang"],
    "elixir": ["text-x-elixir"],
    "julia": ["text-julia"],
    "matlab": ["text-x-matlab"],
    "lisp": ["text-x-common-lisp"],
    "scheme": ["text-x-scheme"],
    "jupyter": ["application-x-ipynb+json"],
    "console": ["text-x-shellscript", "text-x-awk", "text-x-pkgbuild"],
    "powershell": ["application-x-powershell"],
    "vim": ["text-x-vim"],
    "nix": ["text-x-nix"],
    "docker": ["text-x-dockerfile"],
    "systemd": ["text-x-systemd-unit", "text-x-dbus-service"],
    # The web.
    "html": ["text-html", "application-xhtml+xml"],
    "css": ["text-css"],
    "sass": ["text-x-scss", "text-x-sass"],
    "less": ["text-x-less"],
    "vue": ["text-x-vue"],
    "svelte": ["text-x-svelte"],
    # Data.
    "json": ["application-json", "application-json5", "application-schema+json"],
    "yaml": ["application-yaml"],
    "toml": ["application-toml"],
    "xml": ["application-xml", "text-x-maven+xml"],
    "database": ["application-sql", "application-vnd.sqlite3"],
    "table": ["text-csv", "text-tab-separated-values"],
    "lock": ["text-x-lockfile"],
    "git": ["text-x-git"],
    # Words.
    "document": ["text-plain", "text-x-generic"],
    "markdown": ["text-markdown", "text-x-rst"],
    "tex": ["text-x-tex", "text-x-bibtex"],
    "log": ["text-x-log"],
    "todo": ["text-x-todo-txt"],
    "readme": ["text-x-readme"],
    "license": ["text-x-copying", "text-x-license"],
    "changelog": ["text-x-changelog"],
    "authors": ["text-x-authors"],
    "credits": ["text-x-credits"],
    "installation": ["text-x-install"],
    "pdf": ["application-pdf"],
    "epub": ["application-epub+zip"],
    "email": ["message-rfc822"],
    # Keys and certificates: told from each other, never read.
    "key": ["application-pgp-keys", "application-pkcs8", "application-pkcs8-encrypted", "application-x-pem-file"],
    "certificate": ["application-pkix-cert", "application-x-pkcs7-certificates"],
    # What a build leaves.
    "exe": ["application-x-executable", "application-x-pie-executable", "application-vnd.microsoft.portable-executable"],
    "lib": ["application-x-sharedlib", "application-x-object", "application-x-archive"],
    "disc": ["application-vnd.efi.iso", "application-vnd.efi.img"],
    # The kinds below also take whole families (GENERIC, FAMILY).
    "svg": ["image-svg+xml"],
    "image": [],
    "audio": [],
    "video": [],
    "font": [],
    "zip": [],
    "word": [],
    "powerpoint": [],
}
# What a family's types say in the database's generic-icons, and their top-level
# media type: read from the machine's own database when the theme is written, as
# every type of a family has its own icon name in Breeze, which would answer first.
GENERIC = {
    "package-x-generic": "zip",
    "image-x-generic": "image",
    "audio-x-generic": "audio",
    "video-x-generic": "video",
    "font-x-generic": "font",
    "x-office-document": "word",
    "x-office-spreadsheet": "table",
    "x-office-presentation": "powerpoint",
    "text-x-script": "console",
    "text-x-generic": "document",
    "application-x-executable": "exe",
}
FAMILY = {"image/": "image", "audio/": "audio", "video/": "video", "font/": "font"}

# All a checked icon may hold. Its drawing and nothing else: no script, style,
# image, text or animation, and no reference out of the file. Upstream's are
# plain today; a release that is not stops the build, and the theme with it.
TAGS = {"svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs",
        "linearGradient", "radialGradient", "stop", "clipPath", "use"}
ATTRIBUTES = {
    "viewBox", "width", "height", "x", "y", "x1", "x2", "y1", "y2", "cx", "cy", "r", "rx", "ry", "d", "points",
    "id", "fill", "fill-rule", "fill-opacity", "opacity", "stroke", "stroke-width", "stroke-linecap",
    "stroke-linejoin", "stroke-miterlimit", "stroke-opacity", "clip-rule", "clip-path", "clipPathUnits",
    "transform", "offset", "stop-color", "stop-opacity", "gradientTransform", "gradientUnits", "href",
    "preserveAspectRatio", "data-mit-no-recolor", "space", "data-name", "aria-label", "paint-order", "class",
}
LOCAL_URL = re.compile(r"url\(#[\w.-]+\)")
PATH_DATA = re.compile(r"[MmLlHhVvCcSsQqTtAaZz0-9 ,.\-]+")
MIME_NAME = re.compile(r"(?!.*\.\.)[A-Za-z0-9.+_-]+")
MOST_BYTES = 64 * 1024


def needed():
    """The upstream files the theme is made from, as verify.py locks them."""
    return sorted(["LICENSE", GENERATOR, *(f"icons/{name}.svg" for name in MAP)])


def checked(source):
    """The file's bytes, if it holds a drawing and nothing else."""
    raw = source.read_bytes()
    if len(raw) > MOST_BYTES:
        sys.exit(f"files.py: {source.name} is over {MOST_BYTES} bytes")
    if b"<!" in raw or b"<?" in raw:
        sys.exit(f"files.py: {source.name} holds a declaration")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as e:
        sys.exit(f"files.py: {source.name} does not parse: {e}")
    for element in root.iter():
        tag = element.tag.split("}", 1)[-1]
        if tag not in TAGS:
            sys.exit(f"files.py: {source.name}: a <{tag}> is no part of a drawing")
        for key, value in element.attrib.items():
            name = key.split("}", 1)[-1]
            if name not in ATTRIBUTES:
                sys.exit(f"files.py: {source.name}: <{tag} {name}=...> is no part of a drawing")
            if name == "href" and not value.startswith("#"):
                sys.exit(f"files.py: {source.name}: an href leaves the file")
            if "url(" in value and not LOCAL_URL.fullmatch(value.strip()):
                sys.exit(f"files.py: {source.name}: a url() leaves the file")
    return raw


def plain_file(source):
    """The plain file as upstream's build draws it."""
    found = re.search(r"const fileIcon =\s*'([^']+)'", (source / GENERATOR).read_text(encoding="utf-8"))
    if not found or not PATH_DATA.fullmatch(found.group(1)):
        sys.exit(f"files.py: no path data for the plain file in {GENERATOR}")
    return (f'<svg xmlns="{SVG_NS}" viewBox="0 0 16 16"><path fill="{PLAIN}" d="{found.group(1)}"/></svg>\n').encode()


def families(mime):
    """{icon name: upstream's icon} for the families, from the database at `mime`."""
    out = {}
    generic = mime / "generic-icons"
    if generic.is_file():
        for line in generic.read_text(encoding="utf-8").splitlines():
            kind, _, general = line.partition(":")
            if general in GENERIC:
                out[kind.replace("/", "-")] = GENERIC[general]
    types = mime / "types"
    if types.is_file():
        for kind in types.read_text(encoding="utf-8").split():
            for prefix, icon in FAMILY.items():
                if kind.startswith(prefix):
                    out[kind.replace("/", "-")] = icon
    return {name: icon for name, icon in out.items() if MIME_NAME.fullmatch(name)}


def index():
    return "\n".join([
        "[Icon Theme]",
        "Name=SpaceduckFiles",
        "Comment=File icons from Material Icon Theme, over the line icons",
        "Inherits=SpaceduckLines,breeze-dark,hicolor",
        "Directories=scalable/mimetypes",
        "",
        "[scalable/mimetypes]",
        "Size=32",
        "MinSize=8",
        "MaxSize=512",
        "Context=MimeTypes",
        "Type=Scalable",
        "",
    ])


def write_theme(source, out, mime=pathlib.Path("/usr/share/mime")):
    """The whole theme at `out` from `source`'s copy of the files needed()."""
    missing = [p for p in needed() if not (source / p).is_file()]
    if missing:
        sys.exit(f"files.py: not in {source}: {' '.join(missing[:5])}")
    drawn = {name: checked(source / "icons" / f"{name}.svg") for name in MAP}
    # By name, so that a type named here beats its family's icon.
    mimetypes = {name: drawn[icon] for name, icon in families(mime).items()}
    mimetypes.update({name: drawn[icon] for icon, names in MAP.items() for name in names})
    mimetypes.update({name: plain_file(source) for name in PLAIN_NAMES})
    if out.exists():
        shutil.rmtree(out)
    folder = out / "scalable" / "mimetypes"
    folder.mkdir(parents=True)
    for name, data in mimetypes.items():
        (folder / f"{name}.svg").write_bytes(data)
    (out / "index.theme").write_text(index(), encoding="utf-8")
    shutil.copyfile(source / "LICENSE", out / "LICENSE")
    return len(mimetypes)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--from", dest="source", required=True, type=pathlib.Path,
                        help="a directory holding upstream's files")
    parser.add_argument("--out", required=True, type=pathlib.Path, help="where the theme goes")
    parser.add_argument("--mime", type=pathlib.Path, default=pathlib.Path("/usr/share/mime"),
                        help="the MIME database whose families are named")
    args = parser.parse_args()
    count = write_theme(args.source, args.out, args.mime)
    print(f"SpaceduckFiles: {count} icons")


if __name__ == "__main__":
    main()
