#!/usr/bin/env bash
# The Qt and GTK look: kde/Kvantum's theme is what build.py writes, its SVG
# parses and has every part Kvantum's built-in theme has (a part a theme
# lacks is drawn in that theme's grey bevels instead), its config reads as
# Kvantum's INI, and gtk/colors.css is colour definitions only.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
command -v python3 >/dev/null 2>&1 || { echo "SKIP  look: python3 is not installed"; exit 0; }

python3 -I - "$REPO" <<'PY'
import configparser
import importlib.util
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

repo = pathlib.Path(sys.argv[1])
theme = repo / "kde/Kvantum/SpaceduckDark"
failed = []
passed = 0


def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
    else:
        failed.append(f"{name}{': ' + detail if detail else ''}")


run = subprocess.run([sys.executable, "-I", str(repo / "kde/Kvantum/build.py"), "--check"],
                     capture_output=True, text=True)
check("the committed theme is what build.py writes", run.returncode == 0, run.stderr.strip())

# Kvantum 1.1.8's built-in theme (:/Kvantum/default.svg in libkvantum.so):
# frames with their eight pieces, then the single elements.
FRAMES = ['button-normal', 'button-pressed', 'button-toggled', 'common-normal', 'group-normal',
    'itemview-focused', 'itemview-pressed', 'itemview-toggled', 'lineedit-focused',
    'lineedit-normal', 'menu-normal', 'menu-shadow', 'scrollbarslider-normal', 'tab-normal',
    'tab-toggled', 'tabframe-normal', 'toolbar-normal', 'tooltip-normal', 'tooltip-shadow']
SINGLE = ['arrow-down-disabled', 'arrow-down-focused', 'arrow-down-normal', 'arrow-down-pressed',
    'arrow-left-disabled', 'arrow-left-focused', 'arrow-left-normal', 'arrow-left-pressed',
    'arrow-minus-disabled', 'arrow-minus-focused', 'arrow-minus-normal', 'arrow-minus-pressed',
    'arrow-plus-disabled', 'arrow-plus-focused', 'arrow-plus-normal', 'arrow-plus-pressed',
    'arrow-right-disabled', 'arrow-right-focused', 'arrow-right-normal', 'arrow-right-pressed',
    'arrow-up-disabled', 'arrow-up-focused', 'arrow-up-normal', 'arrow-up-pressed',
    'button-default-indicator', 'button-focused', 'checkbox-checked-focused',
    'checkbox-checked-normal', 'checkbox-focused', 'checkbox-normal',
    'checkbox-tristate-focused', 'checkbox-tristate-normal', 'dial', 'dial-handle',
    'dial-notches', 'dock-normal', 'focus-bottom', 'focus-left', 'focus-right', 'focus-top',
    'grip-focused', 'grip-normal', 'grip-pressed', 'header-separator', 'mdi-close-disabled',
    'mdi-close-focused', 'mdi-close-normal', 'mdi-close-pressed', 'mdi-maximize-disabled',
    'mdi-maximize-focused', 'mdi-maximize-normal', 'mdi-maximize-pressed', 'mdi-menu-normal',
    'mdi-minimize-disabled', 'mdi-minimize-focused', 'mdi-minimize-normal',
    'mdi-minimize-pressed', 'mdi-restore-disabled', 'mdi-restore-focused', 'mdi-restore-normal',
    'mdi-restore-pressed', 'mdi-shade-disabled', 'mdi-shade-focused', 'mdi-shade-normal',
    'mdi-shade-pressed', 'menu-shadow-hint-bottom', 'menu-shadow-hint-left',
    'menu-shadow-hint-right', 'menu-shadow-hint-top', 'menubaritem-pressed-bottom',
    'menubaritem-toggled-bottom', 'menuitem-pressed', 'menuitem-tearoff-focused',
    'menuitem-tearoff-normal', 'menuitem-toggled', 'progress-normal',
    'progress-pattern-disabled', 'progress-pattern-normal', 'radio-checked-focused',
    'radio-checked-normal', 'radio-focused', 'radio-normal', 'scrollbarslider-focused',
    'scrollbarslider-pressed', 'sizegrip-normal', 'slider-bottomglow-normal', 'slider-normal',
    'slider-tick-normal', 'slider-toggled', 'slider-topglow-normal', 'slidercursor-disabled',
    'slidercursor-focused', 'slidercursor-normal', 'slidercursor-pressed', 'spin-focused',
    'spin-normal', 'spin-normal-bottom', 'spin-normal-bottomright', 'spin-normal-right',
    'spin-normal-top', 'spin-normal-topright', 'spin-pressed', 'spin-pressed-bottom',
    'spin-pressed-bottomright', 'spin-pressed-right', 'spin-pressed-top',
    'spin-pressed-topright', 'splitter-grip-focused', 'splitter-grip-normal',
    'splitter-grip-pressed', 'tab-close-disabled', 'tab-close-focused', 'tab-close-normal',
    'tab-close-pressed', 'tab-focused', 'tab-tear', 'titlebar-focused', 'titlebar-normal',
    'toolbar-handle', 'tooltip-shadow-hint-bottom', 'tooltip-shadow-hint-left',
    'tooltip-shadow-hint-right', 'tooltip-shadow-hint-top']
PIECES = ("top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright")
try:
    ids = {e.get("id") for e in ET.parse(theme / "SpaceduckDark.svg").iter() if e.get("id")}
    check("the SVG parses", True)
except ET.ParseError as error:
    ids = set()
    check("the SVG parses", False, str(error))
need = set(SINGLE) | {f"{f}-{p}" for f in FRAMES for p in PIECES} | set(FRAMES) - {"menu-shadow", "tooltip-shadow"}
missing = sorted(need - ids)
check("every part of the built-in theme is drawn by this one", not missing, " ".join(missing[:12]))

config = configparser.ConfigParser(interpolation=None, strict=True)
try:
    config.read_string((theme / "SpaceduckDark.kvconfig").read_text())
    check("the config reads as INI, one of each section", True)
except configparser.Error as error:
    check("the config reads as INI, one of each section", False, str(error).splitlines()[0])
elements = {config[s][k] for s in config.sections() for k in ("frame.element", "interior.element")
            if k in config[s] and config[s].get(k.split(".")[0], "true") != "false"}
unknown = sorted(e for e in elements if not any(i == e or i.startswith(e + "-") for i in ids))
check("every element the config names is in the SVG", not unknown, " ".join(unknown))
choice = configparser.ConfigParser(interpolation=None)
choice.read_string((repo / "kde/Kvantum/kvantum.kvconfig").read_text())
check("Kvantum is pointed at this theme", choice.get("General", "theme", fallback="") == "SpaceduckDark")

# The file icons: no drawing in the repository, only the table and its lock on
# the official repository, and every type kde/mime adds has an icon.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("files", repo / "kde/icons/files.py")
files = importlib.util.module_from_spec(spec)
spec.loader.exec_module(files)
check("the file icons' drawings are not committed", not (repo / "kde/icons/SpaceduckFiles").exists())
rows = (repo / "kde/icons/files.lock").read_text().splitlines()
check("their lock pins the official repository", f"repo {files.OFFICIAL}" in rows)
check("and a commit", any(re.fullmatch(r"commit [0-9a-f]{40}", r) for r in rows))
locked = sorted(r.split()[3] for r in rows if r.startswith("file "))
check("and the files the table needs", locked == files.needed())
coloured = [n for names in files.MAP.values() for n in names if "folder" in n or n == "inode-directory" or n.startswith("user-")]
check("colour goes on files, never on a folder", not coloured, " ".join(coloured))
added = ET.parse(repo / "kde/mime/code-files.xml").getroot()
kinds = [m.get("type") for m in added]
named = {n for names in files.MAP.values() for n in names}
lacking = [k for k in kinds if k.replace("/", "-") not in named]
check("every type kde/mime adds has an icon", not lacking, " ".join(lacking))
for entry in added:
    parent = entry.find("{http://www.freedesktop.org/standards/shared-mime-info}sub-class-of")
    known = entry.get("type") == "text/x-shellscript"
    check(f"{entry.get('type')} stays text", known or (parent is not None and parent.get("type") == "text/plain"))

# Dolphin's rows scroll under its column header, and only the theme covers
# them: every state in the view's ground, solid over the whole piece.
header = config["HeaderSection"] if "HeaderSection" in config else {}
check("a column header draws its interior", header.get("interior") == "true", header.get("interior", "absent"))
ground = config.get("GeneralColors", "base.color", fallback="")
pieces = {g.get("id"): list(g) for g in ET.parse(theme / "SpaceduckDark.svg").iter() if g.get("id")}
for state in ("normal", "focused", "pressed", "toggled"):
    piece = pieces.get(f"{header.get('interior.element', 'header')}-{state}", [])
    whole = len(piece) == 2 and piece[0].get("width") == piece[1].get("width") \
        and piece[0].get("height") == piece[1].get("height")
    solid = whole and piece[1].get("fill") == ground and piece[1].get("fill-opacity") is None
    check(f"a column header covers what scrolls under it, {state}", solid)

lines = [l for l in (repo / "gtk/colors.css").read_text().splitlines() if l.strip()]
body = [l for l in lines if not l.lstrip().startswith(("/*", "*"))]
bad = [l for l in body if not re.fullmatch(r"@define-color [a-z_]+ #[0-9a-f]{6};", l)]
check("gtk/colors.css defines colours and nothing else", not bad and len(body) > 50, bad[0] if bad else "")
for css in ("gtk-3.0.css", "gtk-4.0.css"):
    check(f"gtk/{css} reads the colours", "@import 'colors.css';" in (repo / "gtk" / css).read_text())

# The window buttons: one layout in every place GTK reads it, KDE's button
# module out of GTK 3 (it drew KWin's buttons over these), and the glyph
# there and named -symbolic.svg, or GTK leaves its colour as drawn.
layouts = {}
for ini in ("gtk-3.0-settings.ini", "gtk-4.0-settings.ini"):
    found = re.findall(r"^gtk-decoration-layout=(.*)$", (repo / "gtk" / ini).read_text(), re.M)
    layouts[ini] = found[0] if len(found) == 1 else None
applied = re.findall(r'button-layout "([^"]*)"', (repo / "hypr/scripts/gsettings-apply.sh").read_text())
check("one window button layout in both settings.ini and gsettings-apply.sh",
      len(set(layouts.values())) == 1 and applied == [layouts["gtk-3.0-settings.ini"]], f"{layouts} {applied}")
modules = re.findall(r"^gtk-modules=(.*)$", (repo / "gtk/gtk-3.0-settings.ini").read_text(), re.M)
check("no KDE GTK module is loaded (kde-gtk-config is not installed)", not any("gtk-module" in m for m in modules), str(modules))
glyphs = re.findall(r'url\("([^"]+)"\)', (repo / "gtk/gtk-3.0.css").read_text())
check("every glyph gtk-3.0.css names is in gtk/ and symbolic",
      glyphs and all((repo / "gtk" / g).is_file() and g.endswith("-symbolic.svg") for g in glyphs), " ".join(glyphs))
# The browsers' tab and selection colours reach the browsers alone: a window
# or selection rule without Chrome's .chromium or Firefox's window name would
# recolour every GTK window instead.
css3 = re.sub(r"/\*.*?\*/", "", (repo / "gtk/gtk-3.0.css").read_text(), flags=re.S)
selectors = [s.strip() for block in css3.split("}") if "{" in block for s in block.split("{")[0].split(",")]
loose = [s for s in selectors if re.search(r"(^|\s)window\b|selection", s) and ".chromium" not in s and "#MozillaGtkWidget" not in s]
check("gtk-3.0.css recolours windows and selections only in the browsers",
      not loose and any(".chromium" in s for s in selectors) and any("#MozillaGtkWidget" in s for s in selectors), " | ".join(loose))
# Firefox mixes its toolbar from its window's colour, 85 parts to 15 of white:
# the window's colour is chosen to come out as this dark grey. Only Chrome's toolbar
# went lighter (2026-11-07), for a selected tab it cannot light alone.
def css_colour(selector):
    m = re.search(re.escape(selector) + r"\s*\{[^}]*?background-color:\s*#([0-9a-f]{6})", css3)
    return tuple(int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4)) if m else None
firefox_bar = css_colour("window#MozillaGtkWidget.background")
mixed = tuple(round(c * 0.85 + 255 * 0.15) for c in firefox_bar) if firefox_bar else None
check("Firefox's toolbar stays its dark grey", mixed == (0x2c, 0x2c, 0x2f), f"{mixed}")
check("Firefox's selected tab alone takes its colour, not the toolbar",
      "--tab-background-color-selected: #2563eb" in (repo / "firefox/userChrome.css").read_text()
      and "#nav-bar" not in (repo / "firefox/userChrome.css").read_text())

# Dolphin's places panel padding: one style sheet, handed over the same way
# by every start (install.sh's entry, the Super+E binding, the unit drop-in).
check("the places panel's style sheet is in kde/", (repo / "kde/dolphin.qss").is_file())
starts = {
    "install.sh": 'mirror_file "$SRC/kde/dolphin.qss" "$CONFIG/dolphin.qss"' in (repo / "install.sh").read_text(),
    "keybinds.lua": "-stylesheet \\\"${XDG_CONFIG_HOME:-$HOME/.config}/dolphin.qss" in (repo / "hypr/config/keybinds.lua").read_text(),
    "drop-in": "-stylesheet %E/dolphin.qss" in (repo / "systemd/user/plasma-dolphin.service.d/stylesheet.conf").read_text(),
}
check("every way Dolphin starts names the same style sheet", all(starts.values()), str(starts))

# Dolphin in its dark look: the list view by default with its four
# columns, the sidebar a face of its own, and the toolbar without the split
# view's buttons but with the menu, which is the only way to the menus.
props = configparser.ConfigParser(interpolation=None)
props.optionxform = str
props.read_string((repo / "kde/dolphin/global.directory").read_text())
check("Dolphin shows hidden files by default", props.get("Settings", "HiddenFilesShown", fallback="") == "true")
check("Dolphin opens folders in the list view with its four columns",
      props.get("Dolphin", "ViewMode", fallback="") == "1"
      and props.get("Dolphin", "VisibleRoles", fallback="").split(",")
      == ["Details_text", "Details_modificationtime", "Details_size", "Details_type"])
qss = (repo / "kde/dolphin.qss").read_text()
check("the sidebar has a face and padding of its own",
      re.search(r"KFilePlacesView\s*\{[^}]*background-color:[^}]*padding|KFilePlacesView\s*\{[^}]*padding:[^}]*background-color", qss, re.S) is not None)
import shutil, subprocess
if shutil.which("dolphin"):
    done = subprocess.run([sys.executable, "-I", str(repo / "kde/dolphin-toolbar.py")], capture_output=True, text=True)
    bar = re.search(r'<ToolBar[^>]*name="mainToolBar"[^>]*>(.*?)</ToolBar>', done.stdout, re.S)
    actions = re.findall(r'<Action name="([^"]+)"', bar.group(1)) if bar else []
    check("the toolbar keeps back, forward, the path and the menu, without the split view",
          done.returncode == 0 and not any(a.startswith("split_") for a in actions)
          and all(a in actions for a in ("go_back", "go_forward", "url_navigators", "hamburger_menu")),
          f"{done.returncode} {actions}")

# The line icons: an icon theme KDE reads, every directory it names there,
# every icon an SVG in the colour scheme's ink, every name build.py maps
# drawn, Lucide's licence beside them, and Breeze under them.
theme_dir = repo / "kde/icons/SpaceduckLines"
idx = configparser.ConfigParser(interpolation=None)
idx.optionxform = str
idx.read_string((theme_dir / "index.theme").read_text())
dirs = idx.get("Icon Theme", "Directories", fallback="").split(",")
check("the line icons are an icon theme over Breeze, every directory in it there",
      idx.get("Icon Theme", "Inherits", fallback="").startswith("breeze-dark")
      and dirs and all((theme_dir / d).is_dir() and idx.has_section(d) for d in dirs), " ".join(dirs))
spec = importlib.util.spec_from_file_location("icons_build", repo / "kde/icons/build.py")
icons_build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons_build)
icons_shapes, icons_geometry = icons_build.SHAPES, icons_build.GEOMETRY
bad = []
for svg in theme_dir.rglob("*.svg"):
    text = svg.read_text()
    try:
        ET.fromstring(text)
    except ET.ParseError as error:
        bad.append(f"{svg.name}: {error}")
        continue
    if 'id="current-color-scheme"' not in text or "ColorScheme-Text" not in text:
        bad.append(f"{svg.name}: no colour scheme")
    # Nothing but plain shapes and their geometry (build.py's rule): no
    # script, link, fetching style or foreign content in a vendored file.
    if re.search(r"<!DOCTYPE|<!ENTITY|<script|javascript:|href|url\(|@import|foreignObject|<image|\son[a-z]+=", text, re.I):
        bad.append(f"{svg.name}: more than shapes")
    for el in ET.fromstring(text).iter():
        tag = el.tag.split("}")[-1]
        if tag in ("svg", "defs", "style", "g"):
            continue
        if tag not in icons_shapes or any(k not in icons_geometry and k != "fill" for k in el.attrib):
            bad.append(f"{svg.name}: <{tag}>")
check("every line icon is plain shapes in the colour scheme's ink", not bad, "; ".join(bad[:3]))
lacking = [f"{rng}/{ctx}/{name}" for targets in icons_build.MAP.values() for ctx, name in targets
           for rng, *_ in icons_build.RANGES if not (theme_dir / rng / ctx / f"{name}.svg").is_file()]
check("every name build.py maps is drawn, at both sizes", not lacking, " ".join(lacking[:5]))
check("Lucide's licence is kept beside its icons", "ISC License" in (theme_dir / "LICENSE").read_text())
lock = (repo / "kde/icons/upstream.lock").read_text()
check("the lock names Lucide's official repository, one tag and one commit",
      "repo https://github.com/lucide-icons/lucide.git\n" in lock
      and re.search(r"^tag \S+$", lock, re.M) is not None
      and re.search(r"^commit [0-9a-f]{40}$", lock, re.M) is not None)
check("every source of the theme has its Git id and SHA-256 in the lock",
      all(re.fullmatch(r"file [0-9a-f]{40} [0-9a-f]{64} \S+", row) for row in lock.splitlines() if row.startswith("file ")) and lock.count("\nfile ") > 50)
check("the third-party notices name what the repository carries",
      all(word in (repo / "THIRD_PARTY_NOTICES.md").read_text() for word in ("Lucide", "Feather", "kde/icons/SpaceduckLines/LICENSE", "tests/e2e/vinput/")))
check("KDE is pointed at the line icons", re.search(r"^\[Icons\]\n(#.*\n)*Theme=SpaceduckLines$", (repo / "kde/kdeglobals").read_text(), re.M) is not None)
# Chrome draws GTK's window buttons at the next whole scale on a fractional screen and,
# when the picture outgrows the button, stretches it over the whole button (gtk/gtk-3.0.css).
close_px = int(re.search(r'<svg[^>]* width="(\d+)"', (repo / "gtk/buttons/close-symbolic.svg").read_text()).group(1))
button_px = int(re.search(r"button\.titlebutton \{\s*min-width: (\d+)px", (repo / "gtk/gtk-3.0.css").read_text()).group(1))
check("the close x's file stays within half its button, so that Chrome keeps its size on a 1.5 screen", close_px * 2 <= button_px, f"{close_px} {button_px}")
# Firefox's window buttons: its own style sheet turned on by the right pref.
check("Firefox's user style sheets are turned on by the pref Firefox reads",
      'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' in (repo / "firefox/user.js").read_text()
      and ".titlebar-button" in (repo / "firefox/userChrome.css").read_text())

for line in failed:
    print(f"FAIL  look: {line}")
if not failed:
    print(f"PASS  look: {passed} checks")
sys.exit(1 if failed else 0)
PY
