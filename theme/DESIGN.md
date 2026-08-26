<!--
This is a design, not an implementation. Nothing in the repository does any of
it yet. It was written on 2026-08-26 from a survey of every place a colour is
currently written, and it stays here so the survey does not have to be redone.

Implementing it means writing bin/theme and the templates it renders, and
regenerating every consumer from the palette. Until then the colours live where
section 1 says they live, spread across the files listed in the survey.
-->

# Theme system design

## 1. What is being built

A generator: colours are written in one place and every other file is produced
from it. The only file written by hand is the palette, and inside it a value
like `#7aa2f7` is filed under what it does, "primary accent", rather than under
what it looks like, "blue". The generator reads that role table and translates
it into the formats KDE, GTK, hyprlock, Hyprland, kitty, tmux, zsh, fcitx5,
swappy, slurp, fuzzel and the quickshell bar each read. There can be several
palettes, chosen by name. Switching is not an edit to the repository; it moves
one link to point at a set of outputs that was built beforehand. There is no
matugen-style step that extracts colours from a wallpaper. A person picks the
colours and the machine only copies them out.

```
 written by hand (tracked)
   theme/palettes/spaceduck.json
   theme/palettes/macos-dark.json
   theme/templates/*.in
          │
          │  theme build            reads a palette, writes each consumer's format
          ▼
 generated (tracked, marked)
   theme/out/spaceduck/
   theme/out/macos-dark/
     palette.json   kdeglobals        Spaceduck.colors   gtk-colors.css
     gtk4.css       hyprlock.conf     hypr-palette.lua   swappy.config
     slurp.env      fuzzel-theme.ini  kitty.conf         tmux.conf
     fzf.env        fcitx5-theme.conf
          │
          │  theme set <name>       touches nothing in the repository
          │
          ├─► consumers that follow a single link
          │     ~/.local/state/theme/current ──► theme/out/<name>/
          │     kitty, tmux, zsh (fzf, caps lock), capture.sh (slurp)
          │
          ├─► consumers that need a copy
          │     ~/.config/kdeglobals
          │     ~/.config/gtk-3.0/colors.css
          │     ~/.config/gtk-4.0/colors.css
          │     ~/.config/gtk-4.0/gtk.css
          │     ~/.config/hypr/palette.conf
          │     ~/.config/hypr/palette.lua
          │     ~/.config/swappy/config
          │     ~/.config/fuzzel/theme.ini
          │     ~/.local/share/color-schemes/<Label>.colors
          │     ~/.local/share/fcitx5/themes/custom/theme.conf
          │     ~/.local/state/theme/palette.json
          │
          └─► signals
                plasma-apply-colorscheme   repaints Qt/KDE apps at once
                qs ipc call theme reload   repaints the quickshell bar at once
                fcitx5-remote -r           repaints the candidate window at once
                tmux source-file           repaints the status line at once
                hyprctl eval               window borders, effect unconfirmed
```

The split between `theme build` and `theme set` is the point. `build` runs only
when a palette changes and its results are committed. `set` runs every day and
leaves no change in the repository at all. The worry the survey raised, that
switching themes would dirty the working tree every time, disappears with that
separation.

---

## 2. Palette format

### 2.1 How the roles were chosen

A role names what a colour does. "Blue" is an appearance; "primary accent" is a
role. Naming by appearance means that moving to a light theme, or a green one,
puts green inside something called `blue`, and from that moment the name lies.

There are 17 roles, in three groups.

**Seven for surfaces and text.** The skeleton every theme has to have.

| Role | What it does | Where the value comes from today |
|---|---|---|
| `bg` | The ground. Bar background, window background, list view background, kitty background | `Theme.qml:84` bg |
| `surface` | A face laid on the ground. Pills, buttons, title bars, the inside of a tooltip border, input fields | `Theme.qml:85` bgAlt |
| `border` | Edges. GTK `borders_breeze`, the hyprlock input border, the slurp selection border, tmux pane edges | `hyprlock.conf:45` |
| `fg` | Text on the ground | `Theme.qml:86` fg |
| `dim` | Faded text. Inactive entries, placeholders, pills that are off | `Theme.qml:87` muted |
| `fill` | A bright face with no meaning attached. Tooltip background | `Theme.qml:114` beige |
| `ink` | Text laid on a coloured face. Pill labels, the selected row, tooltip text | `Theme.qml:115` ink |

`ink` is separate from `bg` not because the values differ today but because the
roles do. In a light theme `bg` moves toward white and `ink` stays near black.
It is also the second most referenced role, at 14 uses. `border` is separate
from `dim` so that a theme with no visible edges, one that sets its borders to
`bg`, remains possible.

**Four that carry meaning.** These four are demanded by name. `kdeglobals` wants
`ForegroundNegative` / `ForegroundNeutral` / `ForegroundPositive` and GTK wants
`error_color_breeze` / `warning_color_breeze` / `success_color_breeze`, so three
of them cannot be removed.

| Role | What it does |
|---|---|
| `accent` | The primary accent. Selection background, focus ring, links, the Hyprland active window border, the launcher's selected row, bluetooth connected |
| `positive` | All is well. Network connected, charging, menu check marks, the volume OSD |
| `caution` | Take note. Battery at 30% or below, load at 65% or above, the brightness OSD, Hangul input state |
| `critical` | Something is wrong. Battery at 15% or below, load at 85% or above, caps lock, an alarm ringing, log out in the power menu, a failed hyprlock authentication |

**Six for telling things apart.** These carry no meaning and have one job:
looking distinct from each other side by side. A bar with nine status pills on
it needs them, or every pill is the same colour. Which number goes where is a
rule rather than a value, so that stays in `Theme.qml` and the palette supplies
only six colours.

| Role | Where it is assigned |
|---|---|
| `tone1` | The media pill, the memory load base, visited links |
| `tone2` | The focused window chip |
| `tone3` | The workspace move indicator |
| `tone4` | The clock and system badge, hover decoration, links, the hyprlock authentication tick |
| `tone5` | The CPU load base |
| `tone6` | The quiet default pill, battery normal, the hyprlock date label |

**What 17 roles leave behind.** Of the 22 slots in `Theme.qml` today, these go.

- `red` (line 88), `green` (89) and `blue` (91) are referenced nowhere in the
  repository. Deleted.
- `capsLock` (103) holds the same value as `accentRed` and has been kept in step
  by hand with `-b '#f7768e' -f '#0f111b'` in
  `dotfiles-terminal/zsh/config/caps-lock.zsh:111`. It becomes `critical` plus
  `ink`. Since the generator also writes the file `caps-lock.zsh` reads, the
  manual synchronisation between the two repositories disappears entirely. This
  is where the confession in the comment at `Theme.qml:100-102` stops being
  needed.
- `accentTeal` (108) is used in two places, the volume OSD and battery normal.
  Volume goes to `positive` and battery normal to `tone6`. Charging is
  `positive` and normal is `tone6`, so the two states stay distinguishable.
- `purple` (92, the media pill) and `accentPurple` (111, memory load) are both
  purple and never sit next to each other on screen. They merge into `tone1`.

**Sixteen slots that are not roles.** ANSI 0 through 15 are a contract, not
roles. `ls`, `git` and `vim` point at "colour 2" by index and believe it is
green, so those sixteen cannot be derived from the role table. They live in the
palette file as a separate `ansi` array. Only kitty consumes it, and indexes 0
through 15 of p10k's 256-colour numbering follow from it.

### 2.2 File format

The path is `~/workspace/dotfiles-desktop/theme/palettes/<name>.json`.

```json
{
  "name": "spaceduck",
  "label": "Spaceduck",
  "scheme": "dark",

  "roles": {
    "bg":       "#0f111b",
    "surface":  "#1b1c36",
    "border":   "#686f9a",
    "fg":       "#ecf0c1",
    "dim":      "#686f9a",
    "fill":     "#ecf0c1",
    "ink":      "#0f111b",

    "accent":   "#7aa2f7",
    "positive": "#9ece6a",
    "caution":  "#e0af68",
    "critical": "#f7768e",

    "tone1":    "#bb9af7",
    "tone2":    "#7a5ccc",
    "tone3":    "#f2ce00",
    "tone4":    "#7dcfff",
    "tone5":    "#ff9e64",
    "tone6":    "#c0caf5"
  },

  "ansi": [
    "#000000", "#e33400", "#5ccc96", "#b3a1e6",
    "#00a3cc", "#f2ce00", "#7a5ccc", "#686f9a",
    "#686f9a", "#e33400", "#5ccc96", "#b3a1e6",
    "#00a3cc", "#f2ce00", "#7a5ccc", "#f0f1ce"
  ]
}
```

Slots 3 and 5 of the `ansi` array holding purple and yellow is not a typo. As
`dotfiles-terminal/kitty/spaceduck.conf:13-15` records, the original author
swapped yellow and purple deliberately, and without reproducing that swap the
result is not spaceduck. Because the palette holds an array, the swap is
expressed in the values themselves and the generator never has to know there is
a story behind it.

`scheme` is `"dark"` or `"light"`. Only when switching to a palette whose value
is `"light"` does `gsettings set org.gnome.desktop.interface color-scheme
default` need to run. Otherwise the field does nothing.

`name` is both the file name and the argument to `theme set`. `label` is the
name shown in the KDE colour scheme list and becomes the file name of
`~/.local/share/color-schemes/<label with spaces removed>.colors`.

**Two palette values move, stated up front.** `accent` is `#7aa2f7`, so the
Hyprland active window border changes from today's `#5ccc96`
(`hypr/config/general.lua:25`). And the hyprlock caps lock colour changes from
today's `#f2ce00` (`hypr/hyprlock.conf:50`) to `critical`, `#f7768e`. Both
settle a palette split the survey pointed at, in one direction. To settle it the
other way, write `#5ccc96` as `accent`, and then the launcher's selected row and
the KDE selection background turn green along with it. That decision is exactly
why the role table exists.

---

## 3. The generator

### 3.1 Where it lives and what it takes

The file is `~/workspace/dotfiles-desktop/bin/theme`, beside `bin/bar` and
`bin/unlock`, and `install.sh` links it to `~/.local/bin/theme`.

```
theme list                    lists the palettes and which one is current
theme show [name]             prints the role table with its values; the current theme if no argument
theme build [name...]         builds theme/out/<name>/ from a palette. Modifies the repository
theme set <name>              puts theme/out/<name>/ where it is read from, and signals
theme check                   checks the outputs still match the palette; exits non-zero if not
theme sync-fallback           rewrites the fallback block in Theme.qml from theme/palettes/spaceduck.json
```

`theme set --reload-hypr` is for asking explicitly for `hyprctl reload`. Why it
is not the default is in 3.6.

### 3.2 The skeleton, and reading a palette

```bash
#!/usr/bin/env bash
#
# Writes every consumer's colour file from a single palette.
#
# build modifies the repository and set does not. That distinction is the whole
# of this script. If changing a theme means leaving a commit behind, nobody
# changes it.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PALETTES="$SRC/theme/palettes"
TEMPLATES="$SRC/theme/templates"
OUT="$SRC/theme/out"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

ROLE_NAMES=(bg surface border fg dim fill ink
            accent positive caution critical
            tone1 tone2 tone3 tone4 tone5 tone6)

die() { echo "theme: $*" >&2; exit 1; }

# Unpacks a palette into R_<role> shell variables and an ANSI array. A missing
# role is caught here. Letting an empty string reach sed further down writes a
# file with a colour silently absent, and that is a failure only a look at the
# screen would find.
load_palette() {
    local file="$PALETTES/$1.json"
    [[ -f "$file" ]] || die "no such palette: $1"

    NAME=$(jq -r '.name' "$file")
    LABEL=$(jq -r '.label' "$file")
    SCHEME=$(jq -r '.scheme' "$file")
    [[ "$NAME" == "$1" ]] || die "$file: name is \"$NAME\", expected \"$1\""

    local role value
    for role in "${ROLE_NAMES[@]}"; do
        value=$(jq -r --arg r "$role" '.roles[$r] // empty' "$file")
        [[ "$value" =~ ^#[0-9a-fA-F]{6}$ ]] \
            || die "$file: role $role is missing or not #rrggbb"
        printf -v "R_$role" '%s' "$value"
    done

    mapfile -t ANSI < <(jq -r '.ansi[]' "$file")
    (( ${#ANSI[@]} == 16 )) || die "$file: ansi must have exactly 16 entries"

    SCHEME_ID=${LABEL// /}
}

# "#rrggbb" -> "r,g,b". Only kdeglobals and .colors want decimal RGB.
rgb() {
    local h="${1#\#}"
    printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}
```

### 3.3 Template substitution

Every consumer that only needs colours dropped into place goes through one
substitution function. In a template `@bg@` becomes `#0f111b`, `@raw:bg@`
becomes `0f111b` without the hash, and `@pango:dim@` becomes `##686f9a`, which
is what hyprlock's markup wants.

```bash
# Expands one template to standard output.
render() {
    local src="$1" role args=()
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        args+=(-e "s|@$role@|$value|g")
        args+=(-e "s|@raw:$role@|${value#\#}|g")
        args+=(-e "s|@pango:$role@|#$value|g")
    done
    args+=(-e "s|@name@|$NAME|g" -e "s|@label@|$LABEL|g" -e "s|@scheme@|$SCHEME|g")
    local i
    for i in "${!ANSI[@]}"; do
        args+=(-e "s|@ansi$i@|${ANSI[$i]}|g")
        args+=(-e "s|@raw:ansi$i@|${ANSI[$i]#\#}|g")
    done
    sed "${args[@]}" "$src"
}

# Everything generated leaves through this function. The first three lines are
# the marker, and the hash on the third covers the whole body. Section 5 uses
# that value.
emit() {
    local dest="$1" comment="$2" body
    body=$(cat)
    local sum
    sum=$(printf '%s\n' "$body" | sha256sum | cut -d' ' -f1)
    mkdir -p "$(dirname "$dest")"
    {
        printf '%s generated by bin/theme from theme/palettes/%s.json\n' "$comment" "$NAME"
        printf '%s hand edits are lost on the next build: edit the palette instead\n' "$comment"
        printf '%s theme-body-sha256: %s\n' "$comment" "$sum"
        printf '%s\n' "$body"
    } > "$dest.tmp"
    mv -T "$dest.tmp" "$dest"
}
```

### 3.4 The first hard one: the kdeglobals colour block

The colour part of `kde/kdeglobals` is 92 fields but only 10 distinct values.
Seven blocks differ in exactly two fields (`BackgroundNormal`,
`BackgroundAlternate`) and are identical in the other ten. That is too much
repetition to write by hand and a very simple rule to generate. It is where a
generator wins by the widest margin.

```bash
# Six of the seven blocks have this shape. Only the two backgrounds vary.
kde_block() {
    local section="$1" normal="$2" alternate="$3"
    cat <<EOF
[Colors:$section]
BackgroundNormal=$(rgb "$normal")
BackgroundAlternate=$(rgb "$alternate")
DecorationFocus=$(rgb "$R_accent")
DecorationHover=$(rgb "$R_tone4")
ForegroundNormal=$(rgb "$R_fg")
ForegroundActive=$(rgb "$R_accent")
ForegroundInactive=$(rgb "$R_dim")
ForegroundLink=$(rgb "$R_tone4")
ForegroundVisited=$(rgb "$R_tone1")
ForegroundNegative=$(rgb "$R_critical")
ForegroundNeutral=$(rgb "$R_caution")
ForegroundPositive=$(rgb "$R_positive")

EOF
}

# The selection block is the one that differs. Its background is painted in the
# accent, so every piece of text on it flips to ink. The three colours that
# carry meaning do not flip: an error message has to still read as an error
# inside a selected row.
kde_selection_block() {
    cat <<EOF
[Colors:Selection]
BackgroundNormal=$(rgb "$R_accent")
BackgroundAlternate=$(rgb "$R_accent")
DecorationFocus=$(rgb "$R_accent")
DecorationHover=$(rgb "$R_tone4")
ForegroundNormal=$(rgb "$R_ink")
ForegroundActive=$(rgb "$R_ink")
ForegroundInactive=$(rgb "$R_ink")
ForegroundLink=$(rgb "$R_ink")
ForegroundVisited=$(rgb "$R_ink")
ForegroundNegative=$(rgb "$R_critical")
ForegroundNeutral=$(rgb "$R_caution")
ForegroundPositive=$(rgb "$R_positive")

EOF
}

# The whole colour part. The .colors file and kdeglobals call the same function,
# which structurally removes the hazard the survey pointed at: two files drifting
# apart, and the screen jumping the moment the scheme is reapplied by name.
kde_colors() {
    cat <<EOF
[General]
ColorScheme=$SCHEME_ID
Name=$LABEL

EOF
    kde_block Window        "$R_bg"      "$R_surface"
    kde_block View          "$R_bg"      "$R_surface"
    kde_block Button        "$R_surface" "$R_bg"
    kde_selection_block
    kde_block Tooltip       "$R_surface" "$R_bg"
    kde_block Complementary "$R_surface" "$R_bg"
    kde_block Header        "$R_surface" "$R_bg"

    cat <<EOF
[WM]
activeBackground=$(rgb "$R_surface")
activeForeground=$(rgb "$R_fg")
inactiveBackground=$(rgb "$R_bg")
inactiveForeground=$(rgb "$R_dim")
activeBlend=$(rgb "$R_accent")
inactiveBlend=$(rgb "$R_dim")

[ColorEffects:Disabled]
Color=$(rgb "$R_dim")
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0
IntensityEffect=0

[ColorEffects:Inactive]
ChangeSelectionColor=false
Enable=false
Color=$(rgb "$R_dim")
ColorAmount=0
ColorEffect=0
ContrastAmount=0
ContrastEffect=0
IntensityAmount=0
IntensityEffect=0
EOF
}

# The file that becomes ~/.config/kdeglobals. Everything that is not a colour
# comes from a template. theme/templates/kdeglobals.head holds lines 1-34 and
# 168-177 of today's kde/kdeglobals: fonts, widgetStyle, the icon theme and the
# sound theme.
build_kdeglobals() {
    { cat "$TEMPLATES/kdeglobals.head"; echo; kde_colors; } \
        | emit "$OUT/$NAME/kdeglobals" '#'
}

# The registered copy of the colour scheme. No application reads it. It exists
# to put a name in the System Settings list, and to give
# plasma-apply-colorscheme something to find by that name.
build_kde_scheme() {
    kde_colors | emit "$OUT/$NAME/$SCHEME_ID.colors" '#'
}
```

### 3.5 The second hard one: the quickshell palette

Producing the file is the cheapest part on the bar's side: the `roles` object
can be lifted out as it is.

```bash
build_quickshell() {
    jq --arg name "$NAME" --arg scheme "$SCHEME" \
       '{ name: $name, scheme: $scheme, roles: .roles }' \
       "$PALETTES/$NAME.json" > "$OUT/$NAME/palette.json.tmp"
    mv -T "$OUT/$NAME/palette.json.tmp" "$OUT/$NAME/palette.json"
}
```

The format takes no comments, so the marker goes in as a JSON key rather than
through `emit`. One more `_generated` field from `jq` does it, and `Theme.qml`
ignores keys it does not know.

The hard part is what to do to `Theme.qml`. The survey's recommendation stands:
read the palette at run time. The fallback for a file that is missing or half
written stays in the QML as a literal, and to stop that literal drifting from
`theme/palettes/spaceduck.json` it is wrapped in a marker block and generated
too. This block alone is written by `sync-fallback` rather than `set`, and it is
committed.

Lines 84 through 115 of `quickshell/bar/services/Theme.qml` become this.

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The palette lives outside this repository's QML, because switching themes
    // has to be writing one file rather than editing tracked source. It is in
    // state rather than config because it is generated, and because putting it
    // inside the config directory makes quickshell's own watcher restart the
    // entire shell.
    readonly property string palettePath:
        (Quickshell.env("XDG_STATE_HOME") ?? `${Quickshell.env("HOME")}/.local/state`)
        + "/theme/palette.json"

    // Declared before palette. This is to make it impossible for an eagerly
    // evaluated binding to reference an id that does not exist yet.
    FileView {
        id: paletteFile

        path: root.palettePath
        // Read synchronously. Reading asynchronously draws the first frame from
        // the fallback and then re-runs 85 colour bindings, and the 90 ms colour
        // animation at Pill.qml:38-43 turns that into a smear of colour right
        // after startup.
        blockLoading: true
        watchChanges: true

        onFileChanged: {
            paletteFile.reload();
            root.palette = root.readPalette();
        }

        // A missing file means only that theme set has never run. Any other
        // failure means the colours on screen cannot be trusted.
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[theme] palette load failed:", error);
        }
    }

    // The definite path, called by bin/theme set right after it swaps the file
    // in. mv -T changes the inode, and whether the watcher follows that is
    // unconfirmed; this covers that uncertainty.
    IpcHandler {
        target: "theme"

        function reload(): void {
            paletteFile.reload();
            root.palette = root.readPalette();
        }
    }

    property var palette: root.readPalette()

    function readPalette(): var {
        try {
            return JSON.parse(paletteFile.text())?.roles ?? ({});
        } catch (e) {
            return ({});
        }
    }

    // ------------------------------------------------------------------
    // The literals below are the fallback for when no palette could be read,
    // and they are a complete spaceduck set in their own right. Do not edit
    // them by hand. bin/theme sync-fallback rewrites them from
    // theme/palettes/spaceduck.json and bin/theme check catches any drift.
    // ------------------------------------------------------------------
    // THEME-FALLBACK-BEGIN
    readonly property color bg:       root.palette.bg       ?? "#0f111b"
    readonly property color surface:  root.palette.surface  ?? "#1b1c36"
    readonly property color border:   root.palette.border   ?? "#686f9a"
    readonly property color fg:       root.palette.fg       ?? "#ecf0c1"
    readonly property color dim:      root.palette.dim      ?? "#686f9a"
    readonly property color fill:     root.palette.fill     ?? "#ecf0c1"
    readonly property color ink:      root.palette.ink      ?? "#0f111b"
    readonly property color accent:   root.palette.accent   ?? "#7aa2f7"
    readonly property color positive: root.palette.positive ?? "#9ece6a"
    readonly property color caution:  root.palette.caution  ?? "#e0af68"
    readonly property color critical: root.palette.critical ?? "#f7768e"
    readonly property color tone1:    root.palette.tone1    ?? "#bb9af7"
    readonly property color tone2:    root.palette.tone2    ?? "#7a5ccc"
    readonly property color tone3:    root.palette.tone3    ?? "#f2ce00"
    readonly property color tone4:    root.palette.tone4    ?? "#7dcfff"
    readonly property color tone5:    root.palette.tone5    ?? "#ff9e64"
    readonly property color tone6:    root.palette.tone6    ?? "#c0caf5"
    // THEME-FALLBACK-END
}
```

And the side that rewrites the fallback block.

```bash
sync_fallback() {
    load_palette spaceduck
    local qml="$SRC/quickshell/bar/services/Theme.qml"
    local body="" role
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        body+=$(printf '    readonly property color %-8s root.palette.%-8s ?? "%s"\n' \
                       "$role:" "$role" "$value")
        body+=$'\n'
    done
    awk -v block="$body" '
        /THEME-FALLBACK-BEGIN/ { print; printf "%s", block; skip = 1; next }
        /THEME-FALLBACK-END/   { skip = 0 }
        !skip                  { print }
    ' "$qml" > "$qml.tmp"
    mv -T "$qml.tmp" "$qml"
}
```

**Eighteen consumer QML files need editing separately.** The property names
change, so `Theme.bgAlt` becomes `Theme.surface`, `Theme.muted` becomes
`Theme.dim`, `Theme.beige` becomes `Theme.fill` and `Theme.accentIndigo` becomes
`Theme.accent`. That is a pure rename and `sed` finishes it. What has to change
alongside it is five white literals.

```
quickshell/bar/modules/PopupMenu.qml:136   Qt.rgba(1, 1, 1, 0.09)
quickshell/bar/modules/PopupMenu.qml:143   Qt.rgba(1, 1, 1, 0.1)
quickshell/bar/modules/PowerMenu.qml:211   Qt.rgba(1, 1, 1, 0.05)
quickshell/bar/modules/Osd.qml:159         Qt.rgba(1, 1, 1, 0.12)
quickshell/bar/modules/Launcher.qml:322    Qt.rgba(1, 1, 1, 0.08)
```

All five mean "a face slightly brighter than the ground", so they become
`Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.09)` and the like. In a light
theme `fg` darkens and the face darkens with it, so there is still contrast.
Left white, the face disappears entirely in a light theme.

`batteryColor` at `Theme.qml:267` and `loadColor` at `312` stay hand-written.
They are rules rather than values; only the names they reference change to the
new role names.

### 3.6 Every remaining consumer

| Consumer | File produced | Where it goes | How | Takes effect |
|---|---|---|---|---|
| Qt / KDE apps (Dolphin) | `kdeglobals` | `~/.config/kdeglobals` | copy | on the `plasma-apply-colorscheme` signal |
| KDE colour scheme entry | `<Label>.colors` | `~/.local/share/color-schemes/` | copy | never needed |
| GTK3 apps (swappy) | `gtk-colors.css` | `~/.config/gtk-3.0/colors.css` | copy | at once, via the colorreload module |
| GTK4 apps | `gtk-colors.css` | `~/.config/gtk-4.0/colors.css` | copy | on app restart |
| libadwaita apps | `gtk4.css` | `~/.config/gtk-4.0/gtk.css` | copy | on app restart |
| swappy annotation colours | `swappy.config` | `~/.config/swappy/config` | copy | next run |
| slurp overlay | `slurp.env` | through the link | read by `capture.sh` | next capture |
| hyprlock | `hyprlock.conf` | `~/.config/hypr/palette.conf` | copy | next lock |
| Hyprland borders | `hypr-palette.lua` | `~/.config/hypr/palette.lua` | copy | `hyprctl eval`, unconfirmed |
| fuzzel | `fuzzel-theme.ini` | `~/.config/fuzzel/theme.ini` | copy | next run |
| fcitx5 candidate window | `fcitx5-theme.conf` | `~/.local/share/fcitx5/themes/custom/theme.conf` | copy | on `fcitx5-remote -r` |
| kitty | `kitty.conf` | through the link | `include` | automatically, after about 0.1 s |
| tmux | `tmux.conf` | through the link | `source-file -q` | on `tmux source-file` |
| zsh fzf, caps lock | `fzf.env` | through the link | read by `zshrc` | in a new shell |
| quickshell bar | `palette.json` | `~/.local/state/theme/palette.json` | copy | on `qs ipc call` |

"Through the link" means `~/.local/state/theme/current` is a symlink to
`theme/out/<name>/` and the consumer reads an absolute path under it. When
`theme set` swaps the link, every file beneath it changes at once.

**The reason a copy is needed differs by consumer.** `~/.config/kdeglobals` is
rewritten by `plasma-apply-colorscheme` through KConfig's `QSaveFile`, and
whether that follows a symlink is unconfirmed; a real file removes the question.
`~/.config/gtk-3.0/colors.css` is watched at that exact path by
`libcolorreload-gtk-module.so` through `g_file_monitor_file`, so the path has to
stay alive rather than the inode. `~/.config/hypr/palette.lua` has to be at a
fixed path under the `CONFIG` computed at `hyprland.lua:16` for `load_module` to
find it.

**What Hyprland needs.** Palette loading goes in ahead of line 57 of
`hypr/hyprland.lua`.

```lua
-- Colours come from outside config/. This is the only hypr file bin/theme
-- writes, and putting it inside config/ would mix generated files in with the
-- hand-written ones.
local palette = CONFIG .. "/palette.lua"
if file_exists(palette) then
    local chunk = loadfile(palette)
    if chunk ~= nil then
        pcall(chunk)
    end
end
PALETTE = PALETTE or { accent = "rgba(5ccc96ff)", clear = "rgba(00000000)" }

load_module("env")
```

`hypr/config/general.lua:25-26` and `hypr/config/rules.lua:16` use that global.

```lua
            active_border = PALETTE.accent,
            inactive_border = PALETTE.clear,
```

```lua
hl.window_rule({ match = { pin = true }, border_color = PALETTE.accent .. " " .. PALETTE.clear })
```

**What hyprlock needs.** One line at the top of `hypr/hyprlock.conf`, and 13
literals become variables.

```
source = ~/.config/hypr/palette.conf
```

The generated `~/.config/hypr/palette.conf` looks like this. The two entries
that carry Pango markup hold the whole string in one variable rather than
substituting part of a value, because whether variable expansion runs inside a
string is unconfirmed and this is the side that is certain.

```
$bgColor        = rgba(@raw:surface@ff)
$fieldOuter     = rgba(@raw:border@ff)
$fieldInner     = rgba(@raw:surface@cc)
$fieldText      = rgba(@raw:fg@ff)
$fieldCheck     = rgba(@raw:tone4@ff)
$fieldFail      = rgba(@raw:critical@ff)
$fieldCapsLock  = rgba(@raw:critical@ff)
$clockColor     = rgba(@raw:fg@ff)
$dateColor      = rgba(@raw:tone6@ff)
$hostColor      = rgba(@raw:dim@ff)
$placeholderText = <span foreground="@pango:dim@">password</span>
$failText        = <span foreground="@pango:critical@">$FAIL</span>
```

**What the terminal repository needs.** `dotfiles-terminal` has to stand on its
own without `dotfiles-desktop`, so it reads its fallback first and lets the
generated file override it afterwards.

One more line after line 2 of `kitty/kitty.conf`.

```
include ./spaceduck.conf
include ~/.local/state/theme/current/kitty.conf
```

With the file absent, kitty writes one line to stderr and carries on, and
spaceduck stands. At the end of `tmux/tmux.conf`, `source-file -q`; the `-q`
passes over a missing file quietly.

```
source-file -q ~/.local/state/theme/current/tmux.conf
```

The Catppuccin values at lines 176-177 of `zsh/zshrc` are deleted. Across both
repositories that was the furthest anything strayed from the palette.

```zsh
# The colours for fzf and the caps lock segment are written by bin/theme in the
# desktop repository. Running with no colour beats running with the wrong one.
[[ -r ~/.local/state/theme/current/fzf.env ]] && source ~/.local/state/theme/current/fzf.env
```

`zsh/config/caps-lock.zsh:111` uses the variables that file defines.

```zsh
  p10k segment -c '$_capslock_on' \
    -b "${THEME_CRITICAL:-#f7768e}" -f "${THEME_INK:-#0f111b}" \
    -i $'\U000F033E' -t 'CAPS LOCK'
```

**What capture.sh needs.** The `slurp -d` at `hypr/scripts/capture.sh:88` takes
colour arguments.

```sh
        # slurp has no configuration file and takes colours only as arguments.
        # With the file absent this keeps today's behaviour of running with none.
        slurp_args=(-d)
        if [[ -r "$HOME/.local/state/theme/current/slurp.env" ]]; then
            # shellcheck source=/dev/null
            . "$HOME/.local/state/theme/current/slurp.env"
            slurp_args+=(-b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w 2 -F Inter)
        fi
        geom=$(slurp "${slurp_args[@]}" 2>/dev/null) || exit 0
```

**The decision on the GTK side.** Of the two options the survey raised, B. Turn
off kded6's gtkconfig module and write `colors.css` ourselves. Two reasons: the
module replaces the `~/.config/gtk-3.0/settings.ini` symlink with a real file
(`settings.ini.bak-20260825-190746` looks like the trace of exactly that), and
the mapping it applies from kdeglobals to GTK names is not ours to control.
`install.sh` puts this in `~/.config/kded6rc`.

```ini
[Module-gtkconfig]
autoload=false
```

That the module identifier is `gtkconfig` is inferred from the file name
`/usr/lib/qt6/plugins/kf6/kded/gtkconfig.so` and was not confirmed on this
machine. Checking whether `~/.config/gtk-3.0/settings.ini` is still a symlink
after `theme set` settles it immediately.

`theme/templates/gtk-colors.css.in` defines 78 `_breeze` names.
`/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css` declares those 78 and its
remaining 4465 lines reference nothing else, so redeclaring the names alone
repaints the whole theme without writing a single rule. The GTK4 edition uses
exactly the same set of names, which was confirmed, so one file can be copied to
both places. The skeleton of the mapping:

```css
@define-color theme_fg_color_breeze @fg@;
@define-color theme_text_color_breeze @fg@;
@define-color theme_bg_color_breeze @bg@;
@define-color theme_base_color_breeze @bg@;
@define-color content_view_bg_breeze @bg@;
@define-color borders_breeze @border@;
@define-color theme_button_background_normal_breeze @surface@;
@define-color theme_button_foreground_normal_breeze @fg@;
@define-color theme_selected_bg_color_breeze @accent@;
@define-color theme_selected_fg_color_breeze @ink@;
@define-color theme_hovering_selected_bg_color_breeze @tone4@;
@define-color theme_view_hover_decoration_color_breeze @tone4@;
@define-color theme_view_active_decoration_color_breeze @accent@;
@define-color theme_titlebar_background_breeze @surface@;
@define-color theme_titlebar_foreground_breeze @fg@;
@define-color tooltip_background_breeze @surface@;
@define-color tooltip_border_breeze @border@;
@define-color tooltip_text_breeze @fg@;
@define-color link_color_breeze @tone4@;
@define-color link_visited_color_breeze @tone1@;
@define-color error_color_breeze @critical@;
@define-color warning_color_breeze @caution@;
@define-color success_color_breeze @positive@;
@define-color insensitive_fg_color_breeze @dim@;
@define-color insensitive_bg_color_breeze @surface@;
@define-color print_paper_backdrop_breeze @fill@;
/* The remaining unfocused_*, backdrop_* and insensitive_* families reuse the
   values above. Fading text because a window lost focus is turned off, for the
   same reason [ColorEffects:Inactive] is turned off in kdeglobals. */
```

The seven `theme_header_*_breeze` names defined by the live
`~/.config/gtk-3.0/colors.css` do not exist in current Breeze-Dark, which uses
`theme_titlebar_*` instead, and have no effect. They are not carried into the
new template.

`theme/templates/gtk4.css.in` declares the libadwaita names separately.
libadwaita applications ignore `gtk-theme-name` entirely and know nothing of the
`_breeze` names.

```css
@define-color window_bg_color @bg@;
@define-color window_fg_color @fg@;
@define-color view_bg_color @bg@;
@define-color view_fg_color @fg@;
@define-color headerbar_bg_color @surface@;
@define-color headerbar_fg_color @fg@;
@define-color card_bg_color @surface@;
@define-color card_fg_color @fg@;
@define-color sidebar_bg_color @surface@;
@define-color sidebar_fg_color @fg@;
@define-color popover_bg_color @surface@;
@define-color popover_fg_color @fg@;
@define-color dialog_bg_color @surface@;
@define-color dialog_fg_color @fg@;
@define-color accent_bg_color @accent@;
@define-color accent_fg_color @ink@;
@define-color accent_color @accent@;
@define-color destructive_bg_color @critical@;
@define-color destructive_fg_color @ink@;
@define-color warning_bg_color @caution@;
@define-color warning_fg_color @ink@;
@define-color success_bg_color @positive@;
@define-color success_fg_color @ink@;

@import 'colors.css';
```

### 3.7 build and set

```bash
cmd_build() {
    local names=("$@")
    (( ${#names[@]} )) || mapfile -t names < <(cd "$PALETTES" && ls *.json | sed 's/\.json$//')

    local name
    for name in "${names[@]}"; do
        load_palette "$name"
        mkdir -p "$OUT/$NAME"
        guard_hand_edits "$OUT/$NAME"

        build_kdeglobals
        build_kde_scheme
        build_quickshell
        render "$TEMPLATES/gtk-colors.css.in"    | emit "$OUT/$NAME/gtk-colors.css"     '/*!'
        render "$TEMPLATES/gtk4.css.in"          | emit "$OUT/$NAME/gtk4.css"           '/*!'
        render "$TEMPLATES/hyprlock.conf.in"     | emit "$OUT/$NAME/hyprlock.conf"      '#'
        render "$TEMPLATES/hypr-palette.lua.in"  | emit "$OUT/$NAME/hypr-palette.lua"   '--'
        render "$TEMPLATES/swappy.config.in"     | emit "$OUT/$NAME/swappy.config"      '#'
        render "$TEMPLATES/slurp.env.in"         | emit "$OUT/$NAME/slurp.env"          '#'
        render "$TEMPLATES/fuzzel-theme.ini.in"  | emit "$OUT/$NAME/fuzzel-theme.ini"   '#'
        render "$TEMPLATES/fcitx5-theme.conf.in" | emit "$OUT/$NAME/fcitx5-theme.conf"  '#'
        render "$TEMPLATES/kitty.conf.in"        | emit "$OUT/$NAME/kitty.conf"         '#'
        render "$TEMPLATES/tmux.conf.in"         | emit "$OUT/$NAME/tmux.conf"          '#'
        render "$TEMPLATES/fzf.env.in"           | emit "$OUT/$NAME/fzf.env"            '#'
        echo "built $OUT/$NAME"
    done
}

cmd_set() {
    local name="${1:?theme set <name>}"
    load_palette "$name"
    local out="$OUT/$NAME"
    [[ -d "$out" ]] || die "$out does not exist: run 'theme build $NAME' first"

    # 1. Everything that follows the single link. Atomic.
    mkdir -p "$STATE/theme"
    ln -sfn "$out" "$STATE/theme/current.new"
    mv -T "$STATE/theme/current.new" "$STATE/theme/current"

    # 2. Everything that has to be a real file. Unlike mv, install keeps the path
    #    a watcher is attached to and changes only the contents.
    install -Dm644 "$out/palette.json"       "$STATE/theme/palette.json"
    install -Dm644 "$out/kdeglobals"         "$CONFIG/kdeglobals"
    install -Dm644 "$out/gtk-colors.css"     "$CONFIG/gtk-3.0/colors.css"
    install -Dm644 "$out/gtk-colors.css"     "$CONFIG/gtk-4.0/colors.css"
    install -Dm644 "$out/gtk4.css"           "$CONFIG/gtk-4.0/gtk.css"
    install -Dm644 "$out/hyprlock.conf"      "$CONFIG/hypr/palette.conf"
    install -Dm644 "$out/hypr-palette.lua"   "$CONFIG/hypr/palette.lua"
    install -Dm644 "$out/swappy.config"      "$CONFIG/swappy/config"
    install -Dm644 "$out/fuzzel-theme.ini"   "$CONFIG/fuzzel/theme.ini"
    install -Dm644 "$out/$SCHEME_ID.colors"  "$DATA/color-schemes/$SCHEME_ID.colors"
    install -Dm644 "$out/fcitx5-theme.conf"  "$DATA/fcitx5/themes/custom/theme.conf"
    local png
    for png in arrow next prev radio; do
        [[ -e "$DATA/fcitx5/themes/custom/$png.png" ]] \
            || cp "/usr/share/fcitx5/themes/default-dark/$png.png" \
                  "$DATA/fcitx5/themes/custom/$png.png"
    done

    printf '%s\n' "$NAME" > "$STATE/theme/name"

    # 3. Signals. Every one of them may fail: the next start picks it up.
    qs -p "$CONFIG/quickshell/bar" ipc call theme reload  >/dev/null 2>&1 || true
    plasma-apply-colorscheme "$SCHEME_ID"                 >/dev/null 2>&1 || true
    fcitx5-remote -r                                      >/dev/null 2>&1 || true
    tmux source-file "$STATE/theme/current/tmux.conf"      >/dev/null 2>&1 || true

    # gsettings is touched only when the light/dark sense flips. The theme name
    # is left alone.
    if [[ "$SCHEME" == light ]]; then
        gsettings set org.gnome.desktop.interface color-scheme default  2>/dev/null || true
    else
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    fi

    apply_hypr_border
    echo "theme: $LABEL"
}

# hyprctl keyword cannot be used on this machine. The Hyprland binary carries
# "keyword can't work with non-legacy parsers. Use eval." and this configuration
# is Lua. eval is the only remaining route, and whether it actually takes effect
# at run time is unconfirmed, so the result is read back and reported.
apply_hypr_border() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl eval "hl.config({ general = { col = {
        active_border = \"rgba(${R_accent#\#}ff)\",
        inactive_border = \"rgba(00000000)\" } } })" >/dev/null 2>&1 || true

    local got
    got=$(hyprctl getoption general:col.active_border 2>/dev/null | grep -o 'ff[0-9a-f]\{6\}' | head -1)
    if [[ "$got" == "ff${R_accent#\#}" ]]; then
        return 0
    fi
    echo "theme: window border unchanged; run 'hyprctl reload' or relogin" >&2
}
```

### 3.8 What the script must not do

- **Never call `hyprctl reload` on its own.** As `hypr/config/execs.lua:5-7` and
  `hypr/scripts/session-autostart.sh:5-10` record, a reload re-runs the entire
  exec block. `hypr/scripts/auto_monitors.sh:39` notes that a reload switches
  the laptop panel it had turned off back on. Re-treading monitor configuration
  and autostart for the sake of two colours is a steep price. It runs only when
  `--reload-hypr` asks for it.
- **Never touch mode setting.** `hl.monitor`, resolutions, scales and enabling
  or disabling outputs are outside this script's remit. This machine carries
  GRUB cmdline workarounds for the `xe` driver's atomic commit problem, and
  stepping on mode setting while changing colours kills the display.
- **Never restart the bar.** `bin/bar` has no `--restart`, and `--stop`
  (`bin/bar:124-158`) takes the supervisor down with it. If the IPC call fails,
  leave it to be read at the next start.
- **Never restart fcitx5.** As `hypr/scripts/session-autostart.sh:113-115`
  records, a restart loses the input context of every client that is up.
  `fcitx5-remote -r` is a reload, not a restart.
- **Never touch `gsettings set gtk-theme`, `icon-theme` or `cursor-theme`.**
  Those three belong to `hypr/scripts/gsettings-apply.sh:44-46` and have nothing
  to do with the palette. The single line for `color-scheme` is the exception.
- **Never change the wallpaper.** `hyprpaper.conf` and
  `~/Pictures/Wallpapers/current.png` are user state. Deriving colours from the
  wallpaper is the direction this design explicitly refuses.
- **Never end the session.** Do not prompt for a logout or a relogin. Say what
  needs a restart and stop there.
- **Never quietly overwrite a generated file someone edited.** If the marker
  check in section 5 catches one, `build` stops.

---

## 4. What actually happens on a switch

The order of events from the moment `theme set macos-dark` runs.

**Step 0, validation.** Read the palette and check all 17 roles are `#rrggbb`.
If `theme/out/macos-dark/` is missing it stops here. Nothing on screen changes.

**Step 1, the link is swapped.** `~/.local/state/theme/current` points at
`theme/out/macos-dark/`. `mv -T` leaves no intermediate state.

At that moment **kitty changes.** `auto_reload_config` defaults to 0.1 seconds
(`/usr/share/doc/kitty/html/_downloads/433dadebd0bf504f8b008985378086ce/kitty.conf:2113`)
and it watches every file pulled in by `include`, so every kitty window repaints
within 0.1 s. What that looks like is the terminal background and the prompt
colours turning over together. One caveat: `kitty.conf` had to exist when kitty
started for the automatic reload to run.

From the next capture onward the **slurp overlay** comes up in the new colours.
There is no selection overlay already on screen to update, because slurp is
launched fresh for each capture.

**Step 2, the real files are copied.** Eleven files land in place. As each copy
finishes:

The moment `~/.config/gtk-3.0/colors.css` changes, **every GTK3 application
repaints without restarting.** `/usr/lib/gtk-3.0/modules/libcolorreload-gtk-module.so`
watches that one path through `g_file_monitor_file`, and
`gtk/gtk-3.0-settings.ini:13` already enables the module with
`gtk-modules=colorreload-gtk-module:...`. **This is where the capture GUI that
prompted the request follows along.** swappy is a GTK3 application, which `ldd
/usr/bin/swappy` confirms by naming `libgtk-3.so.0`, so its header bar, tool
panel and buttons all follow this one file. The colours change in place even
with the annotation window open.

When `~/.local/state/theme/palette.json` changes the **quickshell bar** follows.
Whether `FileView.watchChanges` catches an inode swap is unconfirmed, so the
definite route is the IPC call in step 4.

**Step 3, state is recorded.** The name is written to
`~/.local/state/theme/name`. `theme list` reads it on its next run.

**Step 4, four signals.**

`qs -p ~/.config/quickshell/bar ipc call theme reload` makes the bar's
`IpcHandler` re-read the palette and reassign `root.palette`. 85 colour bindings
re-evaluate, and thanks to `ColorAnimation duration: 90` at
`quickshell/bar/modules/Pill.qml:38-43` the pills cross-fade over 90 ms. No
window is rebuilt and no "Reloading configuration..." popup appears. What it
looks like is the bar changing colour smoothly.

`plasma-apply-colorscheme <SchemeId>` emits
`org.kde.KGlobalSettings.notifyChange` on `/KGlobalSettings`, and
`KDEPlasmaPlatformTheme6.so` receives it and swaps the palette of every Qt/KDE
application that is up. **A Dolphin window that was already open repaints where
it stands.** Rewriting the file alone does not do this: KConfig's
`ConfigChanged` signal is emitted only for writes that go through the KConfig
API, and a script overwriting the text emits nothing. The command does rewrite
`~/.config/kdeglobals` through KConfig, but the contents match what was just
copied, so the result is the same. It also calls `/org/kde/KWin/BlendChanges`,
which is KWin-specific and fails quietly under Hyprland.

`fcitx5-remote -r` calls `ReloadConfig` on `org.fcitx.Fcitx.Controller1`. It is
not a restart, so the input context of every client survives. The candidate
window comes up in the new colours from the next Hangul input onward.

`tmux source-file ~/.local/state/theme/current/tmux.conf` changes the status
line of every tmux session at once.

**Step 5, the Hyprland border.** Call `hyprctl eval 'hl.config({...})'`, then
read `hyprctl getoption general:col.active_border` back to see whether it took.
**Whether this route works is unconfirmed.** `hyprctl keyword` cannot be used on
this machine at all: the Hyprland binary carries `keyword can't work with
non-legacy parsers. Use eval.` and `eval is only supported with the lua config
manager`, and `parseKeyword` exists only in
`/usr/include/hyprland/src/config/legacy/ConfigManager.hpp:76`, not in the Lua
headers. If the change cannot be confirmed the script says so and stops. What
the user sees is the window border alone left in the old colour, fixable with
`hyprctl reload` or a relogin.

### What does not change without a restart

Stated plainly.

**GTK4 and libadwaita applications have to be restarted.** GTK4 dropped the
module system and the package ships no watcher equivalent to `colorreload`.
Whether GTK4 itself watches `~/.config/gtk-4.0/gtk.css` is unconfirmed; the
strings in `libgtk-4.so.1` are not enough to decide. The design assumes a
restart is needed.

**A shell has to be opened fresh.** p10k reads its configuration once at shell
start and has no reload path, so `exec zsh` or a new window is required. The
same goes for the fzf colours.

**hyprlock takes effect at the next lock.** hyprlock has no configuration reload
path. The `reload_time` and `reload_cmd` in the binary are for label widgets
like the `cmd[update:60000]` at `hyprlock.conf:74`, and `Unlocking with a
SIGUSR1` is for unlocking. No daemon is resident, so there is no signal to send.
This is not a problem: the next lock is correct.

**fuzzel and swappy's annotation colour take effect on the next run.** Both are
launched per invocation. The fuzzel binary has neither `SIGUSR` nor `inotify`.
swappy's own window is GTK3 and follows at once, but `custom_color`, the
annotation colour bound to the C key, is read at start and so waits for the next
run.

**Some windows already on screen cannot be repainted by any route.** Icons are
already rendered images, and Breeze's GTK asset PNGs are baked in Breeze blue
`#3daee9`. Section 7 is about this.

---

## 5. What gets committed

### 5.1 Tracked

```
theme/palettes/*.json          hand written. The colours a person picks
theme/templates/*.in           hand written. The output formats
theme/templates/kdeglobals.head hand written. Fonts, widgetStyle, the parts that are not colours
bin/theme                      hand written
theme/default                  hand written. One line: the palette a fresh install picks
theme/out/<name>/*             generated, and marked
quickshell/bar/services/Theme.qml   hand written, except the generated fallback block
```

There is one reason to track `theme/out/`. `install.sh` links and copies those
contents at a moment when they have to exist already, and running `theme build`
in a freshly checked out tree needs `jq`, a dependency that could make the
install fail if it were deferred to an install step. With the outputs in the
tree `install.sh` only copies, and `theme build` is run by whoever edits a
palette.

Two lines are appended to `install.sh`.

```bash
"$SRC/bin/theme" set "$(cat "$SRC/theme/default")"
"$SRC/bin/theme" check || echo "theme: generated files do not match the palettes" >&2
```

### 5.2 The marker

If someone edits a generated file by hand, the next `theme build` erases the
edit and leaves no trace of it. That is the one trap a generator sets, and it
must not be left set.

Exactly three lines go at the head of every generated file, differing only in
the comment character the format wants.

```
# generated by bin/theme from theme/palettes/spaceduck.json
# hand edits are lost on the next build: edit the palette instead
# theme-body-sha256: 3f1c9a...  (sha256 of the whole body, 64 characters)
```

The third line is the whole of the marker. Before overwriting, `theme build`
rehashes everything from line 4 down and compares it against the recorded value.
A difference means someone edited it by hand, so it **stops**.

```bash
# Stops the build if a generated file was edited by hand. Overwriting quietly
# leaves nobody able to say where the edit went, and no thread to pull the next
# time a colour is wrong.
guard_hand_edits() {
    local dir="$1" f recorded actual
    shopt -s nullglob
    for f in "$dir"/*; do
        [[ "$(basename "$f")" == palette.json ]] && continue
        recorded=$(sed -n '3s/.*theme-body-sha256: //p' "$f")
        [[ -n "$recorded" ]] || die "$f has no marker: move it aside or delete it"
        actual=$(tail -n +4 "$f" | sha256sum | cut -d' ' -f1)
        if [[ "$recorded" != "$actual" ]]; then
            die "$f was edited by hand.
  the change is not in any palette and would be lost.
  copy what you want into $PALETTES/$NAME.json, then
  'theme build --force $NAME' to discard the file."
        fi
    done
    shopt -u nullglob
}
```

`--force` works only when a person says explicitly that the file is to be
discarded.

`palette.json` takes no comments, so its marker goes in as a JSON key. A
`_generated` object holds the same three pieces, and `Theme.qml` reads only
`.roles`, so it ignores them.

`quickshell/bar/services/Theme.qml` is hand written rather than generated, and
only the 17 lines between `THEME-FALLBACK-BEGIN` and `THEME-FALLBACK-END` are
produced. A hash marker does not guard that block; `theme check` does, comparing
the values inside it against the role table in `theme/palettes/spaceduck.json`
and failing on a difference. A second source of truth is prevented by a check
rather than by discipline.

```bash
cmd_check() {
    local failed=0 name
    for name in $(cd "$PALETTES" && ls *.json | sed 's/\.json$//'); do
        load_palette "$name"
        guard_hand_edits "$OUT/$NAME" || failed=1
    done

    # Catches the fallback block drifting from the spaceduck palette. Left to
    # drift, only a bar that failed to read the state file comes up in the old
    # colours, quietly, and nobody knows.
    load_palette spaceduck
    local qml="$SRC/quickshell/bar/services/Theme.qml" role
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        awk -v r="$role" -v v="$value" '
            /THEME-FALLBACK-BEGIN/ { inblock = 1; next }
            /THEME-FALLBACK-END/   { inblock = 0 }
            inblock && $0 ~ ("property color " r ":") {
                found = 1
                if ($0 !~ ("\"" v "\"")) exit 1
            }
            END { if (!found) exit 1 }
        ' "$qml" || { echo "Theme.qml fallback for $role is not $value" >&2; failed=1; }
    done
    return $failed
}
```

### 5.3 Not tracked

Everything under `~/.local/state/theme/`: the `current` link, `palette.json` and
`name`. All three are pure run-time state and one `theme set` restores them.

### 5.4 What has to be deleted

Leftovers from matugen currently take precedence over the repository, so GTK
applications today are painted in Material You grey-purple rather than in the
palette the repository specifies. `install.sh` points at this list without
deleting anything: a script deleting a user's files is not what this repository
is for.

```
~/.config/matugen/                 templates and configuration. The matugen package itself is already gone
~/.config/gtk-3.0/window_decorations.css and assets/
~/.config/gtk-4.0/window_decorations.css and assets/
~/.config/fuzzel/fuzzel_theme.ini  the new name is theme.ini
~/.config/qt5ct/, ~/.config/qt6ct/, ~/.config/Kvantum/
~/.local/share/color-schemes/MaterialYou*.colors   eight of them
~/.config/xsettingsd/xsettingsd.conf and the xsettingsd at PID 237453
```

`~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/colors.css` are not deleted:
`theme set` overwrites them.

`ColorScheme=BreezeDark` in `~/.config/kdedefaults/kdeglobals` has to be brought
to the new name as well. `~/.config/kdeglobals` currently says `SpaceduckDark`
and the two disagree, so any route that reapplies a scheme by name flips the
whole screen to Breeze blue. Letting `theme set` update that file too is the
safe answer.

---

## 6. The first two themes

### 6.1 spaceduck

The colours on screen today, moved into the role table. The full file is in
section 2.2. Where the values came from:

| Role | Value | Source |
|---|---|---|
| `bg` | `#0f111b` | `Theme.qml:84`, `kitty/spaceduck.conf:17` |
| `surface` | `#1b1c36` | `Theme.qml:85`, `hyprlock.conf:26` |
| `border` | `#686f9a` | `hyprlock.conf:45` |
| `fg` | `#ecf0c1` | `Theme.qml:86`, `kitty/spaceduck.conf:18` |
| `dim` | `#686f9a` | `Theme.qml:87` |
| `fill` | `#ecf0c1` | `Theme.qml:114` beige |
| `ink` | `#0f111b` | `Theme.qml:115` |
| `accent` | `#7aa2f7` | `Theme.qml:110` accentIndigo. The Hyprland border moves to this value |
| `positive` | `#9ece6a` | `Theme.qml:107` |
| `caution` | `#e0af68` | `Theme.qml:106` |
| `critical` | `#f7768e` | `Theme.qml:104`, `caps-lock.zsh:111` |
| `tone1` | `#bb9af7` | `Theme.qml:111`, having absorbed `purple` at line 92 |
| `tone2` | `#7a5ccc` | `Theme.qml:93` violet |
| `tone3` | `#f2ce00` | `Theme.qml:90` yellow |
| `tone4` | `#7dcfff` | `Theme.qml:109` accentSky |
| `tone5` | `#ff9e64` | `Theme.qml:105` accentOrange |
| `tone6` | `#c0caf5` | `Theme.qml:112` accentQuiet, taking over battery-normal from `accentTeal` |

The ground is spaceduck's own and the accents are Tokyo Night. The two lineages
the survey pointed at are carried as they are rather than reconciled, because
that is what the screen looks like today and that is this theme's identity.
Reconciling them is the work of making a new theme, not of editing spaceduck.

### 6.2 macos-dark

`~/workspace/dotfiles-desktop/theme/palettes/macos-dark.json`.

```json
{
  "name": "macos-dark",
  "label": "macOS Dark",
  "scheme": "dark",

  "roles": {
    "bg":       "#1c1c1e",
    "surface":  "#2c2c2e",
    "border":   "#3a3a3c",
    "fg":       "#f2f2f7",
    "dim":      "#8e8e93",
    "fill":     "#f2f2f7",
    "ink":      "#1c1c1e",

    "accent":   "#0a84ff",
    "positive": "#30d158",
    "caution":  "#ff9f0a",
    "critical": "#ff453a",

    "tone1":    "#bf5af2",
    "tone2":    "#5e5ce6",
    "tone3":    "#ffd60a",
    "tone4":    "#64d2ff",
    "tone5":    "#66d4cf",
    "tone6":    "#98989d"
  },

  "ansi": [
    "#1c1c1e", "#ff453a", "#30d158", "#ffd60a",
    "#0a84ff", "#bf5af2", "#64d2ff", "#d1d1d6",
    "#48484a", "#ff6961", "#58e06f", "#ffe14d",
    "#4da3ff", "#d68cf7", "#8fe0ff", "#f2f2f7"
  ]
}
```

The point is that it really is different from spaceduck. The ground loses its
navy entirely and goes to neutral graphite. The foreground goes from cream to
nearly white. The accent goes from indigo to system blue. And the `ansi` array
carries none of the yellow-purple swap spaceduck put there deliberately: yellow
sits at index 3 and purple at index 5, where they belong. That one difference is
enough to test whether two themes can share a format while holding different
conventions.

`dim` at `#8e8e93` and `tone6` at `#98989d` are both grey on purpose. macOS
tends to separate status by brightness rather than by hue, and a quiet pill
sitting in grey suits that. `ink` is `#1c1c1e`, so text on top of it still
reads.

The real test of this design comes with a third, light theme. Setting `scheme`
to `"light"` makes `theme set` flip `color-scheme` to `default`, `ink` and `bg`
part company for the first time, and the five white literals, already rewritten
in terms of `fg`, follow along.

---

## 7. What this does not do

The limits, stated plainly. How different two themes can actually be is decided
by this list.

**The Qt widget style is fixed at Breeze.** `widgetStyle=Breeze` at
`kde/kdeglobals:29` decides shape, not colour. How rounded a button's corners
are, how thick a scrollbar is, how large a checkbox is, what a tab looks like
and what curve an animation follows are all inside compiled C++. Colour can
change; shape cannot. There is effectively no replacement style in the official
repositories. Kvantum is installed but is not read under
`QT_QPA_PLATFORMTHEME=kde` (`hypr/config/env.lua:20`), and changing that makes
kdeglobals ignored wholesale, which loses the entire colour scheme.

**The GTK theme is fixed at Breeze-Dark,** for a different reason. A GTK theme
is CSS, but `/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css` is 4465 lines and
the dimensions, corner radii, margins and shadows inside it are rules rather
than colour names. Redeclaring 78 `@define-color` names swaps the colours and
leaves the rules alone. Changing the rules too would mean one 4465-line
stylesheet per theme, which is not what this design is for.

**Icon themes cannot be generated.** `breeze-dark` is thousands of SVG and PNG
files with the colour inside each one. Changing it means redrawing all of them.
matugen could not do this either, which is why the end-4 configuration took the
icon theme wholesale. Both themes use `breeze-dark` icons.

**Breeze's GTK asset PNGs do not follow.** The check marks and arrows under
`/usr/share/themes/Breeze-Dark/assets/` are images already rendered in Breeze
blue `#3daee9`. No amount of editing `colors.css` moves them. There will be
places, such as the mark inside a checked checkbox, that stay Breeze blue rather
than the theme accent.

**The p10k prompt effectively does not follow the palette.** Of the 228 colour
assignments in `dotfiles-terminal/zsh/p10k.zsh`, 222 are 256-colour indexes.
Indexes 0 through 15 follow kitty's `ansi` array, but 16 through 255 are fixed
colour-cube entries and have nothing to do with the palette. Really binding this
file would mean generating all 223 assignments, work of the same order as
writing an entire GTK stylesheet. The caps lock segment alone is bound as an
exception, because the fact that it disagreed with the bar was already written
down in a comment at `Theme.qml:100-102`.

**Notifications have nothing to paint.** No notification daemon is installed.
`pacman -Qq` shows `libnotify` and neither dunst, mako nor swaync.
`capture.sh:36-40` calls `notify-send`, and with no server that notification
appears nowhere. When a daemon is chosen it becomes a consumer.

**hyprpicker has no colours.** `capture.sh:109` calls it as `hyprpicker -a -n`,
and the tool magnifies the screen without drawing anything of its own. It has no
configuration file either. Of the three capture GUIs it is the one that stays
outside the palette.

### So how different can two themes be

**What can differ completely.** Every background, every piece of text, every
accent, window borders, the selection background, the lock screen, the 16
terminal colours, every pill on the status bar, the candidate window, every
surface of the capture editor. Flipping from a dark theme to a light one works
too.

**What stays the same.** How rounded every window is, the size and shape of
buttons, scrollbars and checkboxes, every icon, the mark inside a checkbox, the
length and curve of every animation, and the fonts. Fonts are tied together
across the five `font=` lines in `kde/kdeglobals`, the `fontconfig/local.conf`
chain and `gsettings-apply.sh:48-49`, so moving them into the palette would make
the generator write fontconfig as well. In stage one they stay hand written and
are left as an extension point.

In one sentence: the two themes are **the same desktop with all of its colours
changed**. The silhouette of a window and the feel of a button stay put; only
what is painted on them moves. A palette imitating macOS does not look like
macOS. It looks like Breeze wearing macOS colours. Going further means writing a
widget style from scratch, and that does not sit with the premise of using only
official packages.
