#!/usr/bin/env python3
"""Neovim opens text (the user, 2026-11-06: vi, vim, neovim and vscode are all
installed, and neovim is the default).

    default-editor.py MIMEAPPS [--check] [--mime DIR]

Adds `type=nvim.desktop` to MIMEAPPS's [Default Applications] for what is edited
as text, and prints how many lines that took (--check writes nothing). Left
without a default, KDE picks by its own ranking (vim, whose entry the user met as
"Terminal konsole not found"), a program that claims a type wins over text/plain's
default even where it is no editor (a notes app for Markdown, a browser for
JSON), and xdg-open falls back on the browser. So each type is named.

A type the file already names is left alone: that is someone's choice, such as the
browser's for text/html, and a change made later stays. Every text/ type counts
but the few below; application/ types only by name, since most of those under
text/plain are formats with programs of their own (office files, subtitles, mail).
"""

import argparse
import os
import pathlib
import re
import sys
import tempfile

EDITOR = "nvim.desktop"
SECTION = "[Default Applications]"
# Pages, contacts and appointments, which are text but have programs to read them.
NOT_EDITED = {"text/html", "text/calendar", "text/vcard", "text/x-uri"}
EDITED = {
    "application/json", "application/json5", "application/schema+json", "application/ld+json",
    "application/geo+json", "application/yaml", "application/toml", "application/xml", "application/xsd",
    "application/xslt+xml", "application/xml-dtd", "application/sql", "application/typescript",
    "application/ecmascript", "application/x-perl", "application/x-php", "application/x-ruby",
    "application/x-powershell", "application/x-fishscript", "application/x-nuscript", "application/x-bat",
    "application/x-m4", "application/x-gdscript", "application/x-gnuplot", "application/x-cmakecache",
    "application/vnd.coffeescript", "application/vnd.dart", "application/texinfo",
}
KIND = re.compile(r"[a-z]+/[A-Za-z0-9.+_-]+")


def edited(mime):
    """The types to name: this machine's text/ types, then EDITED, sorted."""
    known = (mime / "types").read_text(encoding="utf-8").split()
    kinds = {k for k in known if k.startswith("text/") and k not in NOT_EDITED} | (EDITED & set(known))
    return sorted(k for k in kinds if KIND.fullmatch(k))


def with_defaults(text, kinds):
    """(the file's text with a line for each kind it names nowhere, lines added)."""
    lines = text.splitlines()
    try:
        start = lines.index(SECTION)
    except ValueError:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(SECTION)
        start = len(lines) - 1
    end = start + 1
    while end < len(lines) and not lines[end].startswith("["):
        end += 1
    named = {line.split("=", 1)[0].strip() for line in lines[start + 1:end] if "=" in line}
    added = [f"{k}={EDITOR}" for k in kinds if k not in named]
    # Before the blank lines that part this section from the next.
    while end > start + 1 and not lines[end - 1].strip():
        end -= 1
    lines[end:end] = added
    return "\n".join(lines) + "\n", len(added)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("mimeapps", type=pathlib.Path)
    parser.add_argument("--check", action="store_true", help="only say how many lines it would add")
    parser.add_argument("--mime", type=pathlib.Path, default=pathlib.Path("/usr/share/mime"))
    args = parser.parse_args()
    try:
        kinds = edited(args.mime)
    except OSError as e:
        sys.exit(f"default-editor.py: no MIME database: {e}")
    before = args.mimeapps.read_text(encoding="utf-8") if args.mimeapps.exists() else ""
    after, added = with_defaults(before, kinds)
    if added and not args.check:
        args.mimeapps.parent.mkdir(parents=True, exist_ok=True)
        # Whole or not at all: every program that opens a file reads this one.
        fd, tmp = tempfile.mkstemp(dir=args.mimeapps.parent, prefix=".mimeapps.")
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(after)
        os.chmod(tmp, 0o644)
        os.replace(tmp, args.mimeapps)
    print(added)


if __name__ == "__main__":
    main()
