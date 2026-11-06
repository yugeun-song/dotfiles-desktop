#!/usr/bin/env python3
"""Dolphin's main toolbar without the split view's two buttons, for the dark
look the user chose (2026-11-06: the toolbar trimmed): back, forward, the
view's modes, the path, search, and the menu, which must stay, being the
only way to the menus.

    dolphin-toolbar.py [DOLPHIN]   print the window's ui.rc so changed

KXMLGUI takes a user's copy of the ui.rc over the one built in only while
both have one version, and the built-in one is compiled into the program
(a Qt resource, zstd), so the copy is made from the installed Dolphin
itself: its newest <gui name="dolphin"> document, the two actions dropped.
install.sh runs this at every install and seeds the result, so a Dolphin
with a new ui.rc gets a fresh copy, and one the user has changed in
Configure Toolbars is left alone. Prints nothing and fails when the
document cannot be found; the toolbar then stays as Dolphin ships it.
"""

import re
import shutil
import sys

try:
    from compression import zstd
except ImportError:
    sys.exit(1)

DROP = ("split_view", "split_stash")


def documents(binary):
    data = open(binary, "rb").read()
    magic = b"\x28\xb5\x2f\xfd"
    at = data.find(magic)
    while at >= 0:
        try:
            text = zstd.ZstdDecompressor().decompress(data[at:at + 400_000], max_length=2_000_000)
        except Exception:
            text = b""
        found = re.search(rb'<gui name="dolphin" version="(\d+)"', text)
        if found:
            yield int(found.group(1)), text.decode("utf-8")
        at = data.find(magic, at + 1)


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else shutil.which("dolphin")
    if not binary:
        sys.exit(1)
    try:
        found = max(documents(binary), default=None)
    except OSError:
        sys.exit(1)
    if found is None:
        sys.exit(1)
    text = found[1]
    bar = re.search(r'<ToolBar[^>]*name="mainToolBar"[^>]*>.*?</ToolBar>', text, re.S)
    if not bar:
        sys.exit(1)
    trimmed = bar.group(0)
    for name in DROP:
        trimmed = re.sub(rf'\n[ \t]*<Action name="{name}"\s*/>', "", trimmed)
    sys.stdout.write(text[:bar.start()] + trimmed + text[bar.end():])


if __name__ == "__main__":
    main()
