<!--
A design, not an implementation: bin/theme, theme/palettes/ and
theme/templates/ do not exist yet. Written 2026-08-26 from a survey of every
place a colour is written; re-checked against the tree 2026-09-23 (section 0).
Until it is built, colours live where the tables below say.
References name files and symbols, not line numbers: those move.
-->

# Theme system design

## 0. Drift since the survey (checked 2026-09-23)

| Then | Now |
|---|---|
| Bar was a row of coloured pills | Bar is mostly monochrome (`bg`/`fg`/`muted`); accents survive in menus and alerts; the OSD is monochrome too |
| Hyprland active border `#5ccc96` (green) | `rgba(ecf0c1ff)`, the bar's `fg`, on purpose (`hypr/config/general.lua`). Pinned-window rule is `fg` + `muted` (`hypr/config/rules.lua`) |
| hyprlock carried 13 palette literals | hyprlock is black and white only (`rgba(ffffff..)`, `rgba(000000..)`); not a palette consumer |
| Five `Qt.rgba(1, 1, 1, a)` literals | Four: `PopupMenu.qml` (2), `Launcher.qml`, `PowerMenu.qml`. `Osd.qml`'s is gone |
| `Theme.qml` rules `batteryColor`, `loadColor` | Gone. Hand-written rules now: `weatherColor()`, and the `ink`-vs-`fg` pick by WCAG contrast |
| `Pill.qml` 90 ms `ColorAnimation` | `Pill.qml` is gone; the 90 ms `ColorAnimation` lives in `StatusItem.qml`, `MediaChip.qml`, `SystemBadge.qml`, `Workspaces.qml` |
| slurp ran with no colours | `hypr/scripts/capture.sh` already takes `SLURP_BORDER`, `SLURP_FILL`, `SLURP_DIM`, `SLURP_FONT` from the environment |
| kded6 `gtkconfig` on | Already off via `kde/kded6rc` (for the cursor, not for colour); option B in 3.5 is half done |
| zshrc fzf colours were Catppuccin | `FZF_DEFAULT_OPTS` in `dotfiles-terminal/zsh/zshrc` now uses spaceduck values |
| matugen leftovers on the host | Gone except `~/.config/xsettingsd/xsettingsd.conf`; `~/.config/kdedefaults/kdeglobals` no longer exists |
| 22 colour slots in `Theme.qml` | 28 (see 2.1 for the added ones) |

---

## 1. What is being built

A generator. The only hand-written colour file is a palette, which files each
value under its role ("primary accent"), not its look ("blue"). The generator
translates the role table into every consumer's format. Several palettes may
exist, chosen by name. No colours are extracted from wallpapers.

```
 hand written (tracked)       theme/palettes/<name>.json, theme/templates/*.in
        │  theme build        reads a palette, writes each consumer's format
        ▼
 generated (tracked, marked)  theme/out/<name>/
        │  theme set <name>   touches nothing in the repository
        ├─► through one link  ~/.local/state/theme/current ──► theme/out/<name>/
        │                     kitty, tmux, zsh (fzf, caps lock), capture.sh (slurp)
        ├─► copied            kdeglobals, <Label>.colors, gtk-3.0/4.0 css,
        │                     hypr/palette.lua, swappy, fuzzel, fcitx5, palette.json
        └─► signals           qs ipc (bar), plasma-apply-colorscheme (Qt/KDE),
                              fcitx5-remote -r, tmux source-file, hyprctl eval
```

Rule: `build` runs only when a palette changes and its output is committed;
`set` runs any time and never dirties the tree.

---

## 2. Palette

### 2.1 Roles

Name by role, never by appearance: a light or green theme would otherwise put
green inside something called `blue`. 17 roles.

**Surfaces and text (7)**

| Role | Job | spaceduck | Source today |
|---|---|---|---|
| `bg` | Ground: bar, windows, views, kitty | `#0f111b` | `Theme.bg`, kitty `background` |
| `surface` | Face on the ground: buttons, title bars, inputs | `#1b1c36` | `Theme.bgAlt` (no QML user left) |
| `border` | Edges: GTK `borders_breeze`, slurp, tmux panes | `#686f9a` | pinned-window inactive border |
| `fg` | Text on the ground; Hyprland active border | `#ecf0c1` | `Theme.fg`, kitty `foreground` |
| `dim` | Faded text, off states, placeholders | `#686f9a` | `Theme.muted` |
| `fill` | Bright face with no meaning (key caps) | `#ecf0c1` | `Theme.beige` |
| `ink` | Text on a coloured face | `#0f111b` | `Theme.ink` |

- `ink` is not `bg`: in a light theme `bg` goes white and `ink` stays dark.
- `border` is not `dim`: a borderless theme sets `border` to `bg`.

**Meaning (4).** Demanded by name by kdeglobals (`ForegroundNegative/Neutral/Positive`)
and GTK (`error/warning/success_color_breeze`).

| Role | Job | spaceduck | Source today |
|---|---|---|---|
| `accent` | Selection, focus ring, links, launcher row | `#7aa2f7` | `Theme.accentIndigo` |
| `positive` | OK: connected, charging, check marks | `#9ece6a` | `Theme.accentGreen` |
| `caution` | Take note: Hangul state | `#e0af68` | `Theme.accentAmber` |
| `critical` | Wrong: alerts, caps lock, critical toasts, logout, auth fail | `#f7768e` | `Theme.accentRed`, `caps-lock.zsh` |

**Distinction (6).** No meaning; only look different side by side. Which tone
goes where is a rule and stays in `Theme.qml`.

| Role | spaceduck | Source today | Assigned (survey-era bar) |
|---|---|---|---|
| `tone1` | `#bb9af7` | `Theme.accentPurple` | media pill, memory load, visited links |
| `tone2` | `#7a5ccc` | `Theme.violet` | focused window chip |
| `tone3` | `#f2ce00` | `Theme.yellow` | workspace move indicator |
| `tone4` | `#7dcfff` | `Theme.accentSky` | clock/system badge, hover, links |
| `tone5` | `#ff9e64` | `Theme.accentOrange` | CPU load |
| `tone6` | `#c0caf5` | `Theme.accentQuiet` | quiet default pill, battery normal |

The "assigned" column describes the pill bar; the current bar uses tones only in
`weatherColor()` (`accentSky`, `accentPurple`, `accentQuiet`) and `PowerMenu.qml`
/ `MediaPlayer.qml` (`accentSky`). Reassign when implementing.

The ground is spaceduck, the accents Tokyo Night (sources in `Theme.qml`). The
mix is this theme's identity; reconciling it is a new theme, not an edit.

**`Theme.qml` slots that are not roles**

| Slot | Value | Fate |
|---|---|---|
| `red`, `green`, `blue` | `#e33400`, `#5ccc96`, `#00a3cc` | Unreferenced. Delete |
| `purple` | `#b3a1e6` | Unreferenced; merges into `tone1` |
| `capsLock` | `#f7768e` | Removed from `Theme.qml`: it was an unreferenced duplicate of `accentRed`. `caps-lock.zsh` still hard-codes the same value; the generator's `critical` + `ink` replaces that cross-repo sync |
| `accentTeal` | `#73daca` | A PowerMenu item. Becomes `positive` |
| `accentSaffron` | `#e4bf58` | Added after the survey; `StatusItem` active fill. Role undecided (`caution` is closest) |
| `accentJade`, `accentAzure`, `accentViolet`, `accentRose` | `#4dcbaa`, `#6a9ae7`, `#a076db`, `#d5729d` | Added after the survey; unreferenced |
| `accentAlert` | `#ef3963` | Unreferenced; kept in `Theme.qml` as a record |

**ANSI 0-15 are a contract, not roles.** `ls`, `git`, `vim` address colours by
index. They live in a separate `ansi` array; only kitty consumes it, and p10k
indexes 0-15 follow from it.

### 2.2 File format

`theme/palettes/<name>.json`:

```json
{
  "name": "spaceduck",
  "label": "Spaceduck",
  "scheme": "dark",
  "roles": {
    "bg": "#0f111b", "surface": "#1b1c36", "border": "#686f9a", "fg": "#ecf0c1",
    "dim": "#686f9a", "fill": "#ecf0c1", "ink": "#0f111b",
    "accent": "#7aa2f7", "positive": "#9ece6a", "caution": "#e0af68", "critical": "#f7768e",
    "tone1": "#bb9af7", "tone2": "#7a5ccc", "tone3": "#f2ce00",
    "tone4": "#7dcfff", "tone5": "#ff9e64", "tone6": "#c0caf5"
  },
  "ansi": [
    "#000000", "#e33400", "#5ccc96", "#b3a1e6",
    "#00a3cc", "#f2ce00", "#7a5ccc", "#686f9a",
    "#686f9a", "#e33400", "#5ccc96", "#b3a1e6",
    "#00a3cc", "#f2ce00", "#7a5ccc", "#f0f1ce"
  ]
}
```

- `ansi` slots 3 and 5 hold purple and yellow deliberately: spaceduck's author
  swapped them (`dotfiles-terminal/kitty/spaceduck.conf` disclaimer). The array
  carries the swap; the generator knows nothing of it.
- `scheme` (`dark`/`light`) only drives gsettings `color-scheme`.
- `name` = file name = `theme set` argument. `label` is the KDE scheme name;
  spaces removed it is the `.colors` file name / `ColorScheme` id.
- Value change on adoption: the KDE selection and launcher row are `accent`.
  The Hyprland border is `fg` (section 0), not `accent`.

---

## 3. The generator

### 3.1 Interface

`bin/theme`, beside `bin/bar` and `bin/unlock`; `install.sh` mirrors it to
`~/.local/bin/theme`.

| Command | Does |
|---|---|
| `theme list` | Palettes, and which is current |
| `theme show [name]` | Role table with values (current if omitted) |
| `theme build [name...]` | Writes `theme/out/<name>/`. Modifies the repo |
| `theme set <name> [--reload-hypr]` | Installs `theme/out/<name>/`, signals. `hyprctl reload` only when asked (3.7) |
| `theme check` | Outputs and `Theme.qml` fallback match the palettes; non-zero otherwise |
| `theme sync-fallback` | Rewrites the `Theme.qml` fallback block from `spaceduck.json` |

### 3.2 Core functions

```bash
set -euo pipefail
SRC="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PALETTES="$SRC/theme/palettes"; TEMPLATES="$SRC/theme/templates"; OUT="$SRC/theme/out"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
ROLE_NAMES=(bg surface border fg dim fill ink accent positive caution critical
            tone1 tone2 tone3 tone4 tone5 tone6)
die() { echo "theme: $*" >&2; exit 1; }

# Validate every role here: an empty value reaching sed writes a file with a
# colour silently missing, found only by looking at the screen.
load_palette() {
    local file="$PALETTES/$1.json" role value
    [[ -f "$file" ]] || die "no such palette: $1"
    NAME=$(jq -r '.name' "$file"); LABEL=$(jq -r '.label' "$file"); SCHEME=$(jq -r '.scheme' "$file")
    [[ "$NAME" == "$1" ]] || die "$file: name is \"$NAME\", expected \"$1\""
    for role in "${ROLE_NAMES[@]}"; do
        value=$(jq -r --arg r "$role" '.roles[$r] // empty' "$file")
        [[ "$value" =~ ^#[0-9a-fA-F]{6}$ ]] || die "$file: role $role is missing or not #rrggbb"
        printf -v "R_$role" '%s' "$value"
    done
    mapfile -t ANSI < <(jq -r '.ansi[]' "$file")
    (( ${#ANSI[@]} == 16 )) || die "$file: ansi must have exactly 16 entries"
    SCHEME_ID=${LABEL// /}
}

rgb() { local h="${1#\#}"; printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }

# @role@ -> #rrggbb, @raw:role@ -> rrggbb, @pango:role@ -> ##rrggbb (hyprlock markup),
# @ansiN@ / @raw:ansiN@, @name@ @label@ @scheme@.
render() {
    local src="$1" role i args=()
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        args+=(-e "s|@$role@|$value|g" -e "s|@raw:$role@|${value#\#}|g" -e "s|@pango:$role@|#$value|g")
    done
    args+=(-e "s|@name@|$NAME|g" -e "s|@label@|$LABEL|g" -e "s|@scheme@|$SCHEME|g")
    for i in "${!ANSI[@]}"; do
        args+=(-e "s|@ansi$i@|${ANSI[$i]}|g" -e "s|@raw:ansi$i@|${ANSI[$i]#\#}|g")
    done
    sed "${args[@]}" "$src"
}

# Every generated file leaves through here: 3-line marker (5.2), atomic rename.
emit() {
    local dest="$1" comment="$2" body sum
    body=$(cat); sum=$(printf '%s\n' "$body" | sha256sum | cut -d' ' -f1)
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

### 3.3 kdeglobals and `<Label>.colors`

92 colour fields, 10 distinct values. One function `kde_colors` feeds both
files, so they cannot drift (reapplying a scheme by name would otherwise jump
the screen). `kdeglobals` = `theme/templates/kdeglobals.head` (the non-colour
parts of today's `kde/kdeglobals`: `[General]` fonts and `widgetStyle`,
`[Icons]`, `[KDE]`, `[Sounds]`) + `kde_colors`. The `.colors` copy exists only
to be listed in System Settings and found by `plasma-apply-colorscheme`.

`[General]`: `ColorScheme=$SCHEME_ID`, `Name=$LABEL`.

| Block | BackgroundNormal | BackgroundAlternate |
|---|---|---|
| Window, View | `bg` | `surface` |
| Button, Tooltip, Complementary, Header | `surface` | `bg` |
| Selection | `accent` | `accent` |

| Field (all blocks) | Normal blocks | Selection |
|---|---|---|
| DecorationFocus | `accent` | `accent` |
| DecorationHover | `tone4` | `tone4` |
| ForegroundNormal | `fg` | `ink` |
| ForegroundActive | `accent` | `ink` |
| ForegroundInactive | `dim` | `ink` |
| ForegroundLink | `tone4` | `ink` |
| ForegroundVisited | `tone1` | `ink` |
| ForegroundNegative / Neutral / Positive | `critical` / `caution` / `positive` | same (meaning must survive selection) |

`[WM]`: activeBackground `surface`, activeForeground `fg`, inactiveBackground
`bg`, inactiveForeground `dim`, activeBlend `accent`, inactiveBlend `dim`.
`[ColorEffects:Disabled]`: Color `dim`, ContrastAmount 0.65, ContrastEffect 1,
others 0. `[ColorEffects:Inactive]`: `Enable=false`,
`ChangeSelectionColor=false`, Color `dim`, all amounts/effects 0 (no fading of
unfocused windows).

### 3.4 Quickshell bar

`palette.json` = `{ name, scheme, roles, _generated }` via `jq`. JSON has no
comments, so the marker is the `_generated` key; `Theme.qml` reads only `.roles`.

`Theme.qml` changes:

- Reads `${XDG_STATE_HOME:-~/.local/state}/theme/palette.json` at run time with
  a `FileView`. State, not config: it is generated, and a file inside the
  quickshell config dir makes quickshell's watcher restart the whole shell.
- Declare the `FileView` before `palette` so no eager binding sees a missing id.
- `blockLoading: true`: async load paints the first frame from the fallback,
  then the 90 ms `ColorAnimation`s smear every colour at startup.
- `watchChanges: true` plus an `IpcHandler { target: "theme"; reload() }`.
  `theme set` calls the IPC because whether the watcher follows an inode swap
  (`mv -T`) is unconfirmed.
- `onLoadFailed`: stay quiet on `FileNotFound` (never set), warn otherwise.
- `readPalette()`: `JSON.parse(text)?.roles ?? {}`, `{}` on any exception.
- Each role: `readonly property color <role>: root.palette.<role> ?? "<spaceduck value>"`,
  between `// THEME-FALLBACK-BEGIN` and `// THEME-FALLBACK-END`. Only
  `sync-fallback` writes that block (committed); `check` guards it.

```bash
sync_fallback() {
    load_palette spaceduck
    local qml="$SRC/quickshell/bar/services/Theme.qml" body="" role
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        body+=$(printf '    readonly property color %-8s root.palette.%-8s ?? "%s"\n' "$role:" "$role" "$value")
        body+=$'\n'
    done
    awk -v block="$body" '
        /THEME-FALLBACK-BEGIN/ { print; printf "%s", block; skip = 1; next }
        /THEME-FALLBACK-END/   { skip = 0 }
        !skip                  { print }' "$qml" > "$qml.tmp"
    mv -T "$qml.tmp" "$qml"
}
```

Consumer QML: a `sed` rename (`bgAlt`→`surface`, `muted`→`dim`,
`beige`→`fill`, `accentIndigo`→`accent`, and the 2.1 mappings). The four
`Qt.rgba(1, 1, 1, a)` literals become `Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, a)`:
left white, the face vanishes in a light theme. `Theme.qml`'s own derived
colours (`menuBarLine`, `menuHover`, `surfaceDim`, ...) already follow `fg`.
Rules (`weatherColor()`, the contrast pick) stay hand-written; only names change.

### 3.5 Other consumers

| Consumer | Output | Installed at | How | Takes effect |
|---|---|---|---|---|
| Qt/KDE apps | `kdeglobals` | `~/.config/kdeglobals` | copy | `plasma-apply-colorscheme` |
| KDE scheme list | `<Label>.colors` | `~/.local/share/color-schemes/` | copy | n/a |
| GTK3 (incl. swappy UI) | `gtk-colors.css` | `~/.config/gtk-3.0/colors.css` | copy | at once (colorreload module) |
| GTK4 | `gtk-colors.css` | `~/.config/gtk-4.0/colors.css` | copy | app restart |
| libadwaita | `gtk4.css` | `~/.config/gtk-4.0/gtk.css` | copy | app restart |
| swappy annotation colour | `swappy.config` | `~/.config/swappy/config` | copy | next run |
| slurp | `slurp.env` | link | sourced by `capture.sh` | next capture |
| Hyprland borders | `hypr-palette.lua` | `~/.config/hypr/palette.lua` | copy | `hyprctl eval`, unconfirmed |
| fuzzel | `fuzzel-theme.ini` | `~/.config/fuzzel/theme.ini` | copy | next run |
| fcitx5 candidates | `fcitx5-theme.conf` | `~/.local/share/fcitx5/themes/custom/theme.conf` | copy | `fcitx5-remote -r` |
| kitty | `kitty.conf` | link | `include` | ~0.1 s (`auto_reload_config`) |
| tmux | `tmux.conf` | link | `source-file -q` | `tmux source-file` |
| zsh fzf, caps lock | `fzf.env` | link | sourced by `zshrc` | new shell |
| quickshell bar | `palette.json` | `~/.local/state/theme/palette.json` | copy | `qs ipc call theme reload` |

"Link" = the consumer reads an absolute path under `~/.local/state/theme/current`.
Why some must be real files:

- `kdeglobals`: `plasma-apply-colorscheme` rewrites it via KConfig `QSaveFile`;
  symlink behaviour unconfirmed.
- `gtk-3.0/colors.css`: `libcolorreload-gtk-module.so` watches the path with
  `g_file_monitor_file`; the path must stay live.
- `hypr/palette.lua`: must sit at a fixed path under `CONFIG` (`hypr/hyprland.lua`).

**Hyprland.** Before `load_module("env")` in `hypr/hyprland.lua`:

```lua
-- The only hypr file bin/theme writes; kept out of config/ so generated and
-- hand-written files do not mix.
local palette = CONFIG .. "/palette.lua"
if file_exists(palette) then
    local chunk = loadfile(palette)
    if chunk ~= nil then pcall(chunk) end
end
PALETTE = PALETTE or { border = "rgba(ecf0c1ff)", dim = "rgba(686f9aff)", clear = "rgba(00000000)" }
```

`general.lua` then uses `active_border = PALETTE.border` (from `fg`),
`inactive_border = PALETTE.clear`; `rules.lua` pin rule uses
`PALETTE.border .. " " .. PALETTE.dim`.

**hyprlock.** Monochrome now; no template. If it takes palette colours again:
`source = ~/.config/hypr/palette.conf` at the top, and Pango markup kept whole in
one variable (e.g. `$failText = <span foreground="@pango:critical@">$FAIL</span>`),
because variable expansion inside a string is unconfirmed.

**dotfiles-terminal** must work without this repo: fallback first, generated
override second.

- `kitty/kitty.conf`: `include ./spaceduck.conf` then
  `include ~/.local/state/theme/current/kitty.conf` (missing file: one stderr
  line, spaceduck stands). Auto-reload only works if the included file existed
  at kitty start.
- `tmux/tmux.conf` end: `source-file -q ~/.local/state/theme/current/tmux.conf`.
- `zsh/zshrc`: `[[ -r ~/.local/state/theme/current/fzf.env ]] && source ...`
  (no colour beats wrong colour).
- `zsh/config/caps-lock.zsh`: `-b "${THEME_CRITICAL:-#f7768e}" -f "${THEME_INK:-#0f111b}"`.

**capture.sh.** Already reads `SLURP_BORDER` (`fg`), `SLURP_FILL` (`accent` at
`33` alpha), `SLURP_DIM` (`bg` at `99` alpha) and `SLURP_FONT` from the
environment with spaceduck defaults. `slurp.env` exports those; `capture.sh`
sources it when readable.

**GTK: option B.** Keep kded6 `gtkconfig` off (already so in `kde/kded6rc`) and
write `colors.css` ourselves: the module replaces the `settings.ini` symlink with
a real file and applies a kdeglobals→GTK mapping we do not control.

`gtk-colors.css.in` redeclares Breeze-Dark's colour names; the 4465-line
`/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css` refers to nothing else, so no
rules are written. It declares 78 `*_breeze` names and also references three it
never declares: `theme_header_background_breeze`,
`theme_header_background_backdrop_breeze`, `unfocused_insensitive_color_breeze`.
The template defines all 81. kde-gtk-config's generated `colors.css` sets both
`theme_header_background*` names to the button background, hence `surface`
below. Neither Breeze nor kde-gtk-config defines
`unfocused_insensitive_color_breeze`; mapping it to `dim` is this design's
choice, matching `insensitive_fg_color`. GTK4 Breeze-Dark uses the same set, so one file
serves both. Core mapping:

| Breeze name | Role |
|---|---|
| `theme_fg_color`, `theme_text_color`, `theme_button_foreground_normal`, `theme_titlebar_foreground`, `tooltip_text` | `fg` |
| `theme_bg_color`, `theme_base_color`, `content_view_bg` | `bg` |
| `borders`, `tooltip_border` | `border` |
| `theme_button_background_normal`, `theme_titlebar_background`, `theme_header_background*`, `tooltip_background`, `insensitive_bg_color` | `surface` |
| `theme_selected_bg_color`, `theme_view_active_decoration_color` | `accent` |
| `theme_selected_fg_color` | `ink` |
| `theme_hovering_selected_bg_color`, `theme_view_hover_decoration_color`, `link_color` | `tone4` |
| `link_visited_color` | `tone1` |
| `error_color` / `warning_color` / `success_color` | `critical` / `caution` / `positive` |
| `insensitive_fg_color`, `unfocused_insensitive_color` | `dim` |
| `print_paper_backdrop` | `fill` |

(each name carries the `_breeze` suffix). `unfocused_*` / `backdrop_*` reuse the
same values: no fading on focus loss, as with `[ColorEffects:Inactive]`. The
other five `theme_header_*` names in today's live `colors.css` are unused by
Breeze-Dark and are dropped.

`gtk4.css.in` covers libadwaita, which ignores `gtk-theme-name` and the
`_breeze` names:

| libadwaita name | Role |
|---|---|
| `window_bg_color`, `view_bg_color` | `bg` |
| `headerbar_bg_color`, `card_bg_color`, `sidebar_bg_color`, `popover_bg_color`, `dialog_bg_color` | `surface` |
| every matching `*_fg_color` above | `fg` |
| `accent_bg_color`, `accent_color` | `accent` |
| `destructive_bg_color` / `warning_bg_color` / `success_bg_color` | `critical` / `caution` / `positive` |
| `accent_fg_color`, `destructive_fg_color`, `warning_fg_color`, `success_fg_color` | `ink` |

It ends with `@import 'colors.css';`.

### 3.6 build and set

`cmd_build [names]` (default: every palette): `load_palette`, `guard_hand_edits`
(5.2), then `kde_colors` into `kdeglobals` and `<SCHEME_ID>.colors`, `palette.json`
via `jq`, and `render | emit` for each template with its comment leader:
`/*!` for the two CSS files, `--` for `hypr-palette.lua`, `#` for swappy,
slurp, fuzzel, fcitx5, kitty, tmux, fzf.

`cmd_set <name>`:

1. `load_palette`; stop if `theme/out/<name>/` is missing (nothing on screen changes).
2. Swap the link atomically: `ln -sfn "$out" current.new && mv -T current.new current`.
   kitty repaints within ~0.1 s; the next slurp uses the new colours.
3. `install -Dm644` each real file to its path in 3.5 (install keeps the watched
   path and replaces contents). Copy fcitx5 `arrow next prev radio` PNGs from
   `/usr/share/fcitx5/themes/default-dark/` if absent. GTK3 apps repaint as
   `gtk-3.0/colors.css` lands (`gtk/gtk-3.0-settings.ini` loads
   `colorreload-gtk-module`; swappy links `libgtk-3.so.0`, so its open window follows).
4. Record the name in `~/.local/state/theme/name`.
5. Signals, each `|| true` (the next start picks it up):
   - `qs -p "$CONFIG/quickshell/bar" ipc call theme reload`: bar re-reads, cross-fades 90 ms, no rebuild, no reload popup.
   - `plasma-apply-colorscheme "$SCHEME_ID"`: emits `org.kde.KGlobalSettings.notifyChange`;
     `KDEPlasmaPlatformTheme6.so` repaints running Qt apps. Overwriting the file
     alone does not: KConfig signals only API writes. Its KWin `BlendChanges`
     call fails quietly under Hyprland.
   - `fcitx5-remote -r`: `ReloadConfig`, not a restart; input contexts survive.
   - `tmux source-file "$STATE/theme/current/tmux.conf"`.
   - gsettings `color-scheme`: `default` for light, `prefer-dark` otherwise.
6. `apply_hypr_border`: `hyprctl keyword` is unusable (the binary says
   `keyword can't work with non-legacy parsers. Use eval.`; config is Lua), so
   `hyprctl eval 'hl.config({ general = { col = { active_border = ..., inactive_border = "rgba(00000000)" } } })'`
   with `R_fg`, then read `hyprctl getoption general:col.active_border` back. If
   it did not take: print `window border unchanged; run 'hyprctl reload' or relogin`.

### 3.7 What the script must not do

| Never | Why |
|---|---|
| `hyprctl reload` unless `--reload-hypr` | Drops every monitor rule and timer and re-runs the `monitors.lua` output policy (and `execs.lua`); too much churn for colours |
| Touch mode setting (`hl.monitor`, scale, enable/disable) | A modeset is the one operation this GPU is not trusted with (`hypr/config/general.lua`) |
| Restart the bar (`bin/bar --restart`) | Drops every pill's state; the IPC reload suffices, else the next start reads it |
| Restart fcitx5 | Costs every window its input context (`install.sh`); `-r` is a reload |
| Set gsettings `gtk-theme`, `icon-theme`, `cursor-*` | Owned by `hypr/scripts/gsettings-apply.sh`; only `color-scheme` is ours |
| Change the wallpaper | User state; deriving colours from it is rejected |
| End or prompt for ending the session | Say what needs a restart and stop |
| Overwrite a hand-edited generated file | `build` stops (5.2) |

---

## 4. What needs a restart

| Consumer | When | Why |
|---|---|---|
| GTK4, libadwaita | App restart | No `colorreload` equivalent; whether GTK4 watches `gtk.css` is unconfirmed |
| zsh prompt, fzf | New shell | p10k reads config once at start |
| hyprlock | Next lock | No reload path; `reload_cmd` is for label widgets, SIGUSR1 unlocks. It is monochrome now anyway |
| fuzzel, swappy `custom_color` | Next run | Launched per invocation; fuzzel has no SIGUSR/inotify |
| Rendered icons, Breeze GTK asset PNGs | Never | Baked images (section 7) |

---

## 5. Repository

### 5.1 Tracked vs not

| Path | Kind |
|---|---|
| `theme/palettes/*.json`, `theme/templates/*.in`, `theme/templates/kdeglobals.head`, `bin/theme` | hand written |
| `theme/default` | hand written; one line, the palette a fresh install sets |
| `theme/out/<name>/*` | generated, marked, tracked |
| `quickshell/bar/services/Theme.qml` | hand written except the fallback block |
| `~/.local/state/theme/{current,palette.json,name}` | untracked run-time state; `theme set` recreates |

`theme/out/` is tracked so `install.sh` only copies and never needs `jq`.
`install.sh` appends:

```bash
"$SRC/bin/theme" set "$(cat "$SRC/theme/default")"
"$SRC/bin/theme" check || echo "theme: generated files do not match the palettes" >&2
```

### 5.2 Marker and checks

Rebuilding silently erases hand edits; the marker makes that impossible. Every
generated file starts with three lines (comment leader per format):

```
# generated by bin/theme from theme/palettes/spaceduck.json
# hand edits are lost on the next build: edit the palette instead
# theme-body-sha256: <sha256 of line 4 onward>
```

```bash
guard_hand_edits() {
    local dir="$1" f recorded actual
    shopt -s nullglob
    for f in "$dir"/*; do
        [[ "$(basename "$f")" == palette.json ]] && continue
        recorded=$(sed -n '3s/.*theme-body-sha256: //p' "$f")
        [[ -n "$recorded" ]] || die "$f has no marker: move it aside or delete it"
        actual=$(tail -n +4 "$f" | sha256sum | cut -d' ' -f1)
        [[ "$recorded" == "$actual" ]] || die "$f was edited by hand.
  the change is not in any palette and would be lost.
  copy what you want into $PALETTES/$NAME.json, then
  'theme build --force $NAME' to discard the file."
    done
    shopt -u nullglob
}
```

`--force` only on an explicit request to discard. `palette.json` carries the
same three facts in its `_generated` key.

`cmd_check` runs `guard_hand_edits` over every palette's output, then checks
each role's value inside `THEME-FALLBACK-BEGIN`/`END` in `Theme.qml` against
`spaceduck.json` (awk: find `property color <role>:`, require `"<value>"`,
fail if missing). A drifted fallback would otherwise only show when the bar
fails to read the state file.

### 5.3 Host cleanup (pointed at, never deleted by `install.sh`)

Matugen leftovers once overrode the repo (GTK was Material You grey-purple).
As of 2026-09-23 only `~/.config/xsettingsd/xsettingsd.conf` remains. The rest
of the original list (`~/.config/matugen/`, `window_decorations.css` and
`assets/` in gtk-3.0/4.0, `fuzzel_theme.ini`, `qt5ct`, `qt6ct`, `Kvantum`,
`MaterialYou*.colors`, `~/.config/kdedefaults/kdeglobals` with
`ColorScheme=BreezeDark`) is gone. `gtk-3.0/gtk.css` and `gtk-4.0/colors.css`
stay: `theme set` overwrites them.

---

## 6. The first two themes

**spaceduck**: today's screen in the role table (values in 2.1 / 2.2).

**macos-dark** (`theme/palettes/macos-dark.json`, label `macOS Dark`, scheme `dark`):

| Role | Value | Role | Value |
|---|---|---|---|
| `bg` | `#1c1c1e` | `critical` | `#ff453a` |
| `surface` | `#2c2c2e` | `tone1` | `#bf5af2` |
| `border` | `#3a3a3c` | `tone2` | `#5e5ce6` |
| `fg` | `#f2f2f7` | `tone3` | `#ffd60a` |
| `dim` | `#8e8e93` | `tone4` | `#64d2ff` |
| `fill` | `#f2f2f7` | `tone5` | `#66d4cf` |
| `ink` | `#1c1c1e` | `tone6` | `#98989d` |
| `accent` | `#0a84ff` | | |
| `positive` | `#30d158` | | |
| `caution` | `#ff9f0a` | | |

`ansi`: `#1c1c1e #ff453a #30d158 #ffd60a #0a84ff #bf5af2 #64d2ff #d1d1d6
#48484a #ff6961 #58e06f #ffe14d #4da3ff #d68cf7 #8fe0ff #f2f2f7`.

- Deliberately unlike spaceduck: graphite ground, near-white text, system blue.
- `ansi` has no yellow/purple swap (3 = yellow, 5 = purple): tests that one
  format holds two conventions.
- `dim` and `tone6` both grey: macOS separates status by brightness, not hue.

A third, light theme is the real test: `scheme: "light"` flips gsettings, `ink`
and `bg` diverge, and the `fg`-derived faces follow.

---

## 7. Limits

| Fixed | Why |
|---|---|
| Qt widget style (Breeze) | `widgetStyle=Breeze` in `kde/kdeglobals`; shape lives in compiled C++. Kvantum is ignored under `QT_QPA_PLATFORMTHEME=kde` (`hypr/config/env.lua`), and switching that drops kdeglobals colours |
| GTK theme (Breeze-Dark) | Its 4465-line CSS carries sizes, radii, shadows as rules; only colour names are swapped |
| Icon theme (`breeze-dark`) | Colour baked into thousands of SVG/PNG files |
| Breeze GTK asset PNGs | Pre-rendered in Breeze blue `#3daee9` (checkbox marks, arrows) |
| p10k prompt | 223 of 233 colour assignments in `dotfiles-terminal/zsh/p10k.zsh` are 256-colour indexes; 16-255 are fixed. Only the caps-lock segment is bound, because it shares the bar's `accentRed` |
| hyprpicker | Draws no colours of its own, no config |
| Fonts | Tied across `kde/kdeglobals` `font=` lines, `fontconfig/local.conf`, `gsettings-apply.sh`; left hand-written as an extension point |

Notifications are not a separate consumer: the bar owns
`org.freedesktop.Notifications` and its toasts read `Theme` directly.

Net: the same desktop with every colour changed (backgrounds, text, accents,
borders, selection, 16 terminal colours, bar, candidate window, capture editor,
light or dark). Shapes, icons, checkbox marks, animations and fonts stay. A
macOS palette looks like Breeze wearing macOS colours; more would need a new
widget style, which conflicts with using only official packages.
