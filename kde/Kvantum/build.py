#!/usr/bin/env python3
"""Writes the SpaceduckDark Kvantum theme beside this file.

Qt applications draw their widgets with it (kde/kdeglobals widgetStyle).
Generated rather than drawn: a Kvantum theme is a few hundred SVG pieces,
nine for each state of each widget part, and drawn by hand every colour
would be written a hundred times over. Here each colour is named once, by
the role the bar gives it (quickshell/bar/services/Theme.qml; the KDE
scheme in kde/kdeglobals repeats them), and each shape follows the bar's
rules: flat fills, no lines inside a window, a hairline only round what
floats over one (menus, tooltips), a 2 px accent ring for keyboard focus.

Run it after a change and commit what it writes; --check fails while the
files differ from what it would write (tests/unit/kvantum.sh).
"""

import argparse
import math
import pathlib
import sys

NAME = "SpaceduckDark"
HERE = pathlib.Path(__file__).resolve().parent


def _rgb(colour):
    return [int(colour[i:i + 2], 16) for i in (1, 3, 5)]


def _hex(channels):
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in channels)


def over(alpha, top, base):
    """top laid over base at alpha, as the bar lays its translucent fg."""
    t, b = _rgb(top), _rgb(base)
    return _hex(b[i] + (t[i] - b[i]) * alpha for i in range(3))


# The bar's roles (Theme.qml). The raised steps are Theme.surfaceRaised and
# surfaceRaisedHover, Qt.lighter(bg) by 1.45 and 1.9; the well is
# Qt.darker(bg, 1.8); kdeglobals gives the same raised value to its buttons.
BG = "#0f111b"
FG = "#ecf0c1"
MUTED = "#686f9a"
ACCENT = "#7aa2f7"
INK = "#0f111b"
LINK = "#7dcfff"
VISITED = "#bb9af7"
RAISED = "#161926"
RAISED_HOVER = "#1c2033"
WELL = "#08090f"
LINE = over(0.10, FG, BG)        # Theme.surfaceLine: the edge of what floats
SEPARATOR = over(0.07, FG, BG)   # Theme.surfaceSeparator
HOVER = over(0.12, FG, BG)       # Theme.surfaceHover
PRESS = over(0.16, FG, BG)
TRACK = over(0.12, FG, BG)
THUMB = over(0.30, FG, BG)
THUMB_HOT = over(0.45, FG, BG)
DIM = over(0.78, FG, BG)         # Theme.surfaceDim
# Theme.accentQuiet: the selection of a view that has the keyboard. Breeze's
# folder icons are drawn in the scheme's accent, so a selection in the
# accent swallowed them whole.
QUIET = "#c0caf5"
# The selection of a view without the keyboard. There KIO's places panel
# writes in the plain text colour (fg) and Dolphin's file view still in the
# selection's (ink), so the face sits between the two, each about 4:1 on it;
# with the keyboard both write in ink, on QUIET. Grey, as the sidebars the user
# sent have it (2026-11-06): the panel's icons are one colour, its selection too.
UNFOCUSED = over(0.42, "#ffffff", BG)
ACCENT_HOT = over(0.15, "#ffffff", ACCENT)
ACCENT_OFF = over(0.35, ACCENT, BG)


class Sheet:
    """The SVG: every element laid out in rows at its own place. Kvantum
    renders an element by its id into the rectangle it needs, so only an
    element's bounds count, never where it sits."""

    def __init__(self):
        self.parts = []
        self.x = self.y = self.row = 0.0

    def element(self, ident, w, h, shapes):
        if self.x + w > 1200:
            self.x, self.y, self.row = 0.0, self.y + self.row + 4, 0.0
        x, y = self.x, self.y
        self.x += w + 4
        self.row = max(self.row, h)
        # A clear rectangle the size of the piece: its bounds are then the
        # piece's even where it draws nothing (a focus ring's middle).
        body = [f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" fill="#000000" fill-opacity="0"/>']
        body += [shape(x, y) for shape in shapes]
        self.parts.append(f'<g id="{ident}">{"".join(body)}</g>')

    def text(self):
        width, height = 1200, math.ceil(self.y + self.row)
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
                f'viewBox="0 0 {width} {height}">\n' + "\n".join(self.parts) + "\n</svg>\n")


def rect(px, py, w, h, fill):
    return lambda x, y: f'<rect x="{x + px:g}" y="{y + py:g}" width="{w:g}" height="{h:g}" fill="{fill}"/>'


def path(d, fill=None, stroke=None, width=0, evenodd=False):
    """d is a function of the element's origin, so shapes stay local."""
    style = f'fill="{fill}"' if fill else 'fill="none"'
    if stroke:
        style += f' stroke="{stroke}" stroke-width="{width:g}" stroke-linecap="round" stroke-linejoin="round"'
    if evenodd:
        style += ' fill-rule="evenodd"'
    return lambda x, y: f'<path d="{d(x, y)}" {style}/>'


def _corner_shape(u, r, inset):
    """The top-left corner piece, u square, its outer corner rounded by r,
    shrunk by inset on its outer sides: points and arcs in local units."""
    ri = max(r - inset, 0.0)
    a = inset
    if ri <= 0:
        return [("M", u, u), ("L", a, u), ("L", a, a), ("L", u, a), ("Z",)]
    return [("M", u, u), ("L", a, u), ("L", a, a + ri), ("A", ri, a + ri, a), ("L", u, a), ("Z",)]


def _mirror(shape, u, where):
    fx = where.endswith("right")
    fy = where.startswith("bottom")
    out = []
    for step in shape:
        if step[0] == "Z":
            out.append(step)
            continue
        if step[0] == "A":
            _, radius, px, py = step
            px = u - px if fx else px
            py = u - py if fy else py
            # One mirrored axis turns the arc's direction round; two do not.
            sweep = 0 if fx != fy else 1
            out.append(("A", radius, px, py, sweep))
            continue
        op, px, py = step
        out.append((op, u - px if fx else px, u - py if fy else py))
    return out


def _d(shape, x, y):
    parts = []
    for step in shape:
        if step[0] == "Z":
            parts.append("Z")
        elif step[0] == "A":
            radius, px, py = step[1], step[2], step[3]
            sweep = step[4] if len(step) > 4 else 1
            parts.append(f"A {radius:g} {radius:g} 0 0 {sweep} {x + px:g} {y + py:g}")
        else:
            parts.append(f"{step[0]} {x + step[1]:g} {y + step[2]:g}")
    return " ".join(parts)


SIDES = ("top", "bottom", "left", "right")
CORNERS = ("topleft", "topright", "bottomleft", "bottomright")


def frame(sheet, element, u, r, fill, line=None, width=0.0, interior=True):
    """A rounded rectangle in nine pieces: corners u square rounded by r,
    edges u thick, a middle. line draws a ring width wide at the outer edge
    (inside the corners' rounding too); fill None leaves the inside clear."""
    for where in CORNERS:
        outer = _mirror(_corner_shape(u, r, 0), u, where)
        shapes = []
        if line:
            inner = _mirror(_corner_shape(u, r, width), u, where)
            shapes.append(path(lambda x, y, o=outer, i=inner: _d(o, x, y) + " " + _d(i, x, y), fill=line, evenodd=True))
            if fill:
                shapes.append(path(lambda x, y, i=inner: _d(i, x, y), fill=fill))
        elif fill:
            shapes.append(path(lambda x, y, o=outer: _d(o, x, y), fill=fill))
        sheet.element(f"{element}-{where}", u, u, shapes)
    for side in SIDES:
        shapes = []
        if fill:
            shapes.append(rect(0, 0, u, u, fill))
        if line:
            strip = {"top": (0, 0, u, width), "bottom": (0, u - width, u, width),
                     "left": (0, 0, width, u), "right": (u - width, 0, width, u)}[side]
            if fill:
                inside = {"top": (0, width, u, u - width), "bottom": (0, 0, u, u - width),
                          "left": (width, 0, u - width, u), "right": (0, 0, u - width, u)}[side]
                shapes = [rect(*inside, fill)]
            shapes.append(rect(*strip, line))
        sheet.element(f"{element}-{side}", u, u, shapes)
    if interior:
        sheet.element(element, u, u, [rect(0, 0, u, u, fill)] if fill else [])


def states(sheet, element, u, r, looks, interior=True):
    """looks: state -> fill, (fill, line, width), or None for nothing.
    Every state a part can be in is written, the bare ones too: Kvantum
    draws a state missing from a theme with its built-in theme's grey
    bevels."""
    for state, look in looks.items():
        fill, line, width = look if isinstance(look, tuple) else (look, None, 0.0)
        frame(sheet, f"{element}-{state}", u, r, fill, line, width, interior)


def bare(sheet, *elements):
    """Parts and indicators this theme leaves undrawn, present so that
    Kvantum's built-in theme does not stand in for them."""
    for element in elements:
        sheet.element(element, 4, 4, [])


# ------------------------------------------------------------- indicators --

def glyph(sheet, ident, size, shapes):
    sheet.element(ident, size, size, shapes)


def chevron(direction, colour, size=12.0, stroke=1.6):
    s = size
    points = {
        "down": [(0.25, 0.38), (0.5, 0.63), (0.75, 0.38)],
        "up": [(0.25, 0.62), (0.5, 0.37), (0.75, 0.62)],
        "right": [(0.38, 0.25), (0.63, 0.5), (0.38, 0.75)],
        "left": [(0.62, 0.25), (0.37, 0.5), (0.62, 0.75)],
    }[direction]
    return path(lambda x, y: "M " + " L ".join(f"{x + px * s:g} {y + py * s:g}" for px, py in points),
                stroke=colour, width=stroke)


def bar_line(colour, horizontal, size=12.0, stroke=1.6):
    s = size
    if horizontal:
        return path(lambda x, y: f"M {x + s * 0.27:g} {y + s / 2:g} L {x + s * 0.73:g} {y + s / 2:g}", stroke=colour, width=stroke)
    return path(lambda x, y: f"M {x + s / 2:g} {y + s * 0.27:g} L {x + s / 2:g} {y + s * 0.73:g}", stroke=colour, width=stroke)


def rounded_box(px, py, w, h, r, fill):
    return lambda x, y: (f'<rect x="{x + px:g}" y="{y + py:g}" width="{w:g}" height="{h:g}" '
                         f'rx="{r:g}" ry="{r:g}" fill="{fill}"/>')


def circle(cx, cy, radius, fill):
    return lambda x, y: f'<circle cx="{x + cx:g}" cy="{y + cy:g}" r="{radius:g}" fill="{fill}"/>'


def check_mark(colour, size=16.0):
    s = size
    return path(lambda x, y: f"M {x + s * 0.27:g} {y + s * 0.53:g} L {x + s * 0.44:g} {y + s * 0.69:g} "
                f"L {x + s * 0.74:g} {y + s * 0.33:g}", stroke=colour, width=s * 0.125)


def cross(colour, size=12.0, stroke=1.6):
    s = size
    a, b = 0.32, 0.68
    return path(lambda x, y: f"M {x + s * a:g} {y + s * a:g} L {x + s * b:g} {y + s * b:g} "
                f"M {x + s * b:g} {y + s * a:g} L {x + s * a:g} {y + s * b:g}", stroke=colour, width=stroke)


def build_svg():
    sh = Sheet()

    # Push buttons, combo boxes: raised faces, no edge; a press lifts them
    # further, a checked one keeps the pressed face.
    states(sh, "button", 7, 7, {"normal": RAISED, "focused": RAISED_HOVER, "pressed": PRESS,
                                "toggled": PRESS, "disabled": over(0.5, RAISED, BG)})
    # Tool buttons: nothing until the pointer is over them, as the bar's
    # own buttons; a checked one (a view mode) keeps the hover face.
    states(sh, "tbutton", 6, 6, {"normal": None, "focused": HOVER, "pressed": PRESS, "toggled": HOVER})
    # Text fields: the raised face; keyboard focus rings them in the accent.
    states(sh, "lineedit", 7, 7, {"normal": RAISED, "focused": (RAISED, ACCENT, 2.0),
                                  "disabled": over(0.5, RAISED, BG)})
    # Floating surfaces: the ground with a hairline edge.
    states(sh, "menu", 10, 10, {"normal": (BG, LINE, 1.0)})
    states(sh, "tooltip", 8, 8, {"normal": (BG, LINE, 1.0)})
    # Rows of a menu and of a view: the accent under the pointer in a menu,
    # as the bar's menus have it; a view lifts the row the pointer is over
    # and puts the selection in the accent.
    # The corners are as large as the frames: frame.expansion rounds a part
    # only while it is small enough to become a pill, so it cannot give a
    # set radius. A view's selection takes "pressed" while the view has the
    # keyboard and "toggled" while not (QUIET and UNFOCUSED above).
    states(sh, "menuitem", 6, 6, {"normal": None, "focused": ACCENT, "pressed": ACCENT, "toggled": ACCENT})
    states(sh, "itemview", 5, 5, {"normal": None, "focused": HOVER, "pressed": QUIET, "toggled": UNFOCUSED})
    states(sh, "menubaritem", 5, 5, {"normal": None, "focused": HOVER, "pressed": PRESS, "toggled": PRESS})
    # Tabs: bare until hovered; the selected one a step above the hover.
    states(sh, "tab", 7, 7, {"normal": None, "focused": SEPARATOR, "pressed": HOVER, "toggled": HOVER})
    # Grouped settings sit in a well, below the raised controls in them.
    states(sh, "group", 10, 10, {"normal": WELL})
    # Keyboard focus anywhere else: the accent ring alone. Kvantum asks for
    # it without a state (focus-top, focus-topleft...).
    frame(sh, "focus", 6, 6, None, ACCENT, 2.0, interior=False)
    # Pills: scroll bar thumbs, slider and progress grooves.
    states(sh, "scrollbarslider", 5, 5, {"normal": THUMB, "focused": THUMB_HOT, "pressed": THUMB_HOT})
    states(sh, "slider", 2, 2, {"normal": TRACK, "toggled": ACCENT, "disabled": SEPARATOR})
    states(sh, "progress", 3, 3, {"normal": TRACK})
    states(sh, "progress-pattern", 3, 3, {"normal": ACCENT, "disabled": ACCENT_OFF})
    # A splitter is the one line left inside a window: a separator.
    sh.element("splitter-normal", 1, 8, [rect(0, 0, 1, 8, SEPARATOR)])
    sh.element("header-separator", 1, 8, [rect(0, 0, 1, 8, SEPARATOR)])
    # A column header, in the view's own ground. Kvantum fills a QHeaderView
    # from its view itself, but Dolphin's is a graphics item its rows scroll
    # under (kitemlistheaderwidget.cpp), and only this covers them: bare, they
    # read through its words (the user, 2026-11-06). A style sheet cannot do
    # it: Qt styles no scroll area's viewport (unstylable() in
    # qstylesheetstyle.cpp), and that is the widget Dolphin paints it with.
    # Dolphin also draws the margins beside the columns as disabled, which
    # Kvantum paints at 70%. Only the view's stripes and the last 2 px of a
    # selected row lie under them, so those show faintly there, and nothing
    # in a theme takes that 30% back.
    for state in ("normal", "focused", "pressed", "toggled"):
        sh.element(f"header-{state}", 4, 4, [rect(0, 0, 4, 4, BG)])
    # A menu's rule: one pixel in the middle of menu_separator_height.
    sh.element("menuitem-separator", 10, 9, [rect(0, 4, 10, 1, SEPARATOR)])
    # Frames left bare: window panels, toolbars, title bars, spin buttons,
    # popup shadows (Hyprland draws none for popups, and a drawn one would
    # be a band of clicks that land on nothing).
    for element in ("common-normal", "dock-normal", "tabframe-normal", "toolbar-normal", "titlebar-normal",
                    "titlebar-focused", "spin-normal", "spin-focused", "spin-pressed", "menu-shadow",
                    "menu-shadow-hint", "tooltip-shadow", "tooltip-shadow-hint"):
        frame(sh, element, 4, 0, None)
    bare(sh, "grip-normal", "grip-focused", "grip-pressed", "sizegrip-normal", "splitter-grip-normal",
         "splitter-grip-focused", "splitter-grip-pressed", "slider-topglow-normal", "slider-bottomglow-normal",
         "slider-tick-normal", "toolbar-handle", "tab-tear", "menuitem-tearoff-normal", "menuitem-tearoff-focused",
         "button-default-indicator")

    text_for = {"normal": FG, "focused": FG, "pressed": FG, "disabled": MUTED}
    for direction in ("up", "down", "left", "right"):
        for state, colour in text_for.items():
            glyph(sh, f"arrow-{direction}-{state}", 12, [chevron(direction, colour)])
        # On a highlighted menu row the arrow takes the row's text colour.
        for state in ("focused", "pressed", "toggled"):
            if direction in ("left", "right"):
                glyph(sh, f"menuitem-{direction}-{state}", 12, [chevron(direction, INK)])
    for state, colour in text_for.items():
        glyph(sh, f"arrow-plus-{state}", 12, [bar_line(colour, True), bar_line(colour, False)])
        glyph(sh, f"arrow-minus-{state}", 12, [bar_line(colour, True)])
        # A tree's branches: Kvantum asks the expander for plus (closed) and
        # minus (open); they are drawn as chevrons, as the bar's lists.
        glyph(sh, f"texp-plus-{state}", 12, [chevron("right", DIM if state == "normal" else colour)])
        glyph(sh, f"texp-minus-{state}", 12, [chevron("down", DIM if state == "normal" else colour)])
        for direction in ("up", "down", "left", "right"):
            glyph(sh, f"texp-{direction}-{state}", 12, [chevron(direction, DIM if state == "normal" else colour)])

    box = {"normal": over(0.18, FG, BG), "focused": over(0.24, FG, BG), "pressed": over(0.30, FG, BG),
           "disabled": over(0.09, FG, BG)}
    on = {"normal": ACCENT, "focused": ACCENT_HOT, "pressed": ACCENT_HOT, "disabled": ACCENT_OFF}
    for state in box:
        glyph(sh, f"checkbox-{state}", 16, [rounded_box(1, 1, 14, 14, 4, box[state])])
        glyph(sh, f"checkbox-checked-{state}", 16, [rounded_box(1, 1, 14, 14, 4, on[state]), check_mark(INK)])
        glyph(sh, f"checkbox-tristate-{state}", 16, [rounded_box(1, 1, 14, 14, 4, on[state]),
                                                     bar_line(INK, True, size=16, stroke=2)])
        glyph(sh, f"radio-{state}", 16, [circle(8, 8, 7, box[state])])
        glyph(sh, f"radio-checked-{state}", 16, [circle(8, 8, 7, on[state]), circle(8, 8, 2.75, INK)])

    # The slider's handle: a disc of the text colour, as the bar's sliders.
    knob = {"normal": FG, "focused": "#ffffff", "pressed": "#ffffff", "disabled": MUTED}
    for state, colour in knob.items():
        glyph(sh, f"slidercursor-{state}", 16, [circle(8, 8, 7, colour)])

    for state, (face, ink) in {"normal": (None, DIM), "focused": (HOVER, FG),
                               "pressed": (PRESS, FG), "disabled": (None, MUTED)}.items():
        shapes = [circle(6, 6, 6, face)] if face else []
        glyph(sh, f"tab-close-{state}", 12, shapes + [cross(ink, stroke=1.4)])

    # Seldom seen, never missing: a dial and the buttons of a window inside
    # a window (QMdiArea).
    glyph(sh, "dial", 32, [circle(16, 16, 15, TRACK)])
    glyph(sh, "dial-handle", 32, [circle(16, 6, 3, FG)])
    sh.element("dial-notches", 32, 32, [])
    for state, colour in text_for.items():
        glyph(sh, f"mdi-close-{state}", 12, [cross(colour)])
        glyph(sh, f"mdi-minimize-{state}", 12, [bar_line(colour, True)])
        glyph(sh, f"mdi-maximize-{state}", 12, [rounded_box(2.5, 2.5, 7, 7, 1.5, colour), rounded_box(3.7, 3.7, 4.6, 4.6, 0.6, BG)])
        glyph(sh, f"mdi-restore-{state}", 12, [rounded_box(3.5, 3.5, 5, 5, 1, colour), rounded_box(4.6, 4.6, 2.8, 2.8, 0.4, BG)])
        glyph(sh, f"mdi-shade-{state}", 12, [chevron("up", colour)])
        glyph(sh, f"mdi-menu-{state}", 12, [chevron("down", colour)])
    return sh.text()


def build_kvconfig():
    return f"""\
# Written by build.py; edit that, not this.
[%General]
author=dotfiles-desktop
comment=The bar's look for Qt applications
x11drag=none
alt_mnemonic=true
left_tabs=false
attach_active_tab=false
mirror_doc_tabs=false
group_toolbar_buttons=false
toolbar_item_spacing=2
toolbar_interior_spacing=3
spread_progressbar=true
progressbar_thickness=6
composite=true
menu_shadow_depth=0
menu_separator_height=9
tooltip_shadow_depth=0
shadowless_popup=true
spread_menuitems=false
splitter_width=1
scroll_width=10
scroll_min_extent=36
scroll_arrows=false
transient_scrollbar=true
transient_groove=false
slider_width=4
slider_handle_width=16
slider_handle_length=16
check_size=16
inline_spin_indicators=true
vertical_spin_indicators=false
combo_as_lineedit=true
combo_menu=true
scrollable_menu=true
animate_states=true
respect_DE=true
no_inactiveness=true
spread_header=true
remove_extra_frames=true
groupbox_top_label=true
fill_rubberband=true
menubar_mouse_tracking=true
transparent_menutitle=true

[GeneralColors]
window.color={BG}
base.color={BG}
alt.base.color={RAISED}
button.color={RAISED}
light.color={RAISED_HOVER}
mid.light.color={RAISED_HOVER}
dark.color={WELL}
mid.color={LINE}
shadow.color=#000000
highlight.color={ACCENT}
inactive.highlight.color={ACCENT}
tooltip.base.color={BG}
text.color={FG}
window.text.color={FG}
button.text.color={FG}
disabled.text.color={MUTED}
tooltip.text.color={FG}
highlight.text.color={INK}
link.color={LINK}
link.visited.color={VISITED}
progress.indicator.text.color={FG}

[Hacks]
respect_darkness=true
transparent_ktitle_label=true
transparent_menutitle=true
normal_default_pushbutton=true
no_selection_tint=true
kcapacitybar_as_progressbar=true

[PanelButtonCommand]
frame=true
frame.element=button
frame.top=7
frame.bottom=7
frame.left=7
frame.right=7
interior=true
interior.element=button
indicator.element=arrow
indicator.size=12
text.normal.color={FG}
text.focus.color={FG}
text.press.color={FG}
text.toggle.color={FG}
text.shadow=false
text.margin.top=0
text.margin.bottom=0
text.margin.left=5
text.margin.right=5
text.iconspacing=6
min_width=+8

[PanelButtonTool]
inherits=PanelButtonCommand
frame.element=tbutton
interior.element=tbutton
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
text.margin.left=2
text.margin.right=2
min_width=0

[ToolbarButton]
inherits=PanelButtonTool

[Dock]
inherits=PanelButtonCommand
frame=false
interior=false

[DockTitle]
inherits=PanelButtonCommand
frame=false
interior=false
text.normal.color={DIM}
text.focus.color={FG}
text.bold=false
text.margin.top=4
text.margin.bottom=4
text.margin.left=6
text.margin.right=6

[IndicatorSpinBox]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=arrow
indicator.size=12

[RadioButton]
inherits=PanelButtonCommand
frame=false
interior.element=radio
text.margin.top=2
text.margin.bottom=2
text.margin.left=4
text.margin.right=4

[CheckBox]
inherits=PanelButtonCommand
frame=false
interior.element=checkbox
text.margin.top=2
text.margin.bottom=2
text.margin.left=4
text.margin.right=4

[Focus]
inherits=PanelButtonCommand
frame=true
frame.element=focus
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
interior=false

[GenericFrame]
inherits=PanelButtonCommand
frame=false
interior=false
frame.top=0
frame.bottom=0
frame.left=0
frame.right=0

[LineEdit]
inherits=PanelButtonCommand
frame.element=lineedit
interior.element=lineedit
text.margin.left=2
text.margin.right=2

[DropDownButton]
inherits=PanelButtonCommand
indicator.element=arrow-down

[IndicatorArrow]
indicator.element=arrow
indicator.size=12

[ToolboxTab]
inherits=PanelButtonCommand

[Tab]
inherits=PanelButtonCommand
frame.element=tab
interior.element=tab
indicator.element=tab
text.normal.color={DIM}
text.focus.color={FG}
text.toggle.color={FG}
text.margin.left=8
text.margin.right=8

[TabFrame]
inherits=PanelButtonCommand
frame=false
interior=false

[TabBarFrame]
inherits=GenericFrame

[TreeExpander]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=texp
indicator.size=12

[HeaderSection]
inherits=PanelButtonCommand
frame=false
interior=true
interior.element=header
text.normal.color={DIM}
text.focus.color={FG}
text.press.color={FG}
text.margin.top=4
text.margin.bottom=4

[SizeGrip]
indicator.element=sizegrip

[Toolbar]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=toolbar
text.margin=0

[StatusBar]
inherits=Toolbar

[Slider]
inherits=PanelButtonCommand
frame.element=slider
interior.element=slider
frame.top=2
frame.bottom=2
frame.left=2
frame.right=2

[SliderCursor]
inherits=PanelButtonCommand
frame=false
interior.element=slidercursor

[Progressbar]
inherits=PanelButtonCommand
frame.element=progress
interior.element=progress
frame.top=3
frame.bottom=3
frame.left=3
frame.right=3
text.normal.color={FG}
text.focus.color={FG}
text.bold=false

[ProgressbarContents]
inherits=PanelButtonCommand
frame=true
frame.element=progress-pattern
interior.element=progress-pattern
frame.top=3
frame.bottom=3
frame.left=3
frame.right=3

[ItemView]
inherits=PanelButtonCommand
frame.element=itemview
interior.element=itemview
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5
text.margin=0
text.normal.color={FG}
text.focus.color={FG}
text.press.color={INK}
text.toggle.color={INK}

[Splitter]
inherits=PanelButtonCommand
frame=false
interior.element=splitter
indicator.element=splitter-grip

[Scrollbar]
inherits=PanelButtonCommand
indicator.element=arrow
indicator.size=10

[ScrollbarSlider]
inherits=PanelButtonCommand
frame.element=scrollbarslider
interior.element=scrollbarslider
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5
indicator.element=grip

[ScrollbarGroove]
inherits=PanelButtonCommand
frame=false
interior=false

[MenuItem]
inherits=PanelButtonCommand
frame=true
frame.element=menuitem
interior.element=menuitem
indicator.element=menuitem
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
text.normal.color={FG}
text.focus.color={INK}
text.press.color={INK}
text.toggle.color={INK}
text.margin.top=0
text.margin.bottom=0
text.margin.left=2
text.margin.right=2
min_height=24

[MenuBarItem]
inherits=PanelButtonCommand
frame.element=menubaritem
interior.element=menubaritem
frame.top=5
frame.bottom=5
frame.left=5
frame.right=5
text.margin.top=0
text.margin.bottom=0

[MenuBar]
inherits=PanelButtonCommand
frame=false
interior=false

[TitleBar]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.element=mdi
text.normal.color={DIM}
text.focus.color={FG}

[ComboBox]
inherits=PanelButtonCommand

[ToolbarComboBox]
inherits=ComboBox

[ToolbarLineEdit]
inherits=LineEdit

[Menu]
inherits=PanelButtonCommand
frame.element=menu
interior.element=menu
frame.top=10
frame.bottom=10
frame.left=10
frame.right=10
text.margin=0

[GroupBox]
inherits=GenericFrame
frame=true
frame.element=group
interior=true
interior.element=group
frame.top=10
frame.bottom=10
frame.left=10
frame.right=10
text.margin=0
text.normal.color={FG}

[ToolTip]
inherits=GenericFrame
frame=true
frame.element=tooltip
interior=true
interior.element=tooltip
frame.top=8
frame.bottom=8
frame.left=8
frame.right=8
text.margin=0
text.normal.color={FG}

[Window]
interior=false

[Dialog]
inherits=Window
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when the files differ from what would be written")
    parser.add_argument("--out", type=pathlib.Path, default=HERE / NAME, help="the theme's directory")
    args = parser.parse_args()
    files = {args.out / f"{NAME}.svg": build_svg(), args.out / f"{NAME}.kvconfig": build_kvconfig()}
    if args.check:
        stale = [p for p, text in files.items() if not p.is_file() or p.read_text() != text]
        for p in stale:
            print(f"kvantum: {p} differs from what build.py writes", file=sys.stderr)
        return 1 if stale else 0
    args.out.mkdir(parents=True, exist_ok=True)
    for p, text in files.items():
        p.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
