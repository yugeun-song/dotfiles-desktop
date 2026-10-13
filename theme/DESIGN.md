<!--
A design, not an implementation: bin/theme, theme/palettes/ and
theme/templates/ do not exist yet; colours live where the tables below say.
Surveyed 2026-08-26 from every place a colour is written, re-checked against
the tree 2026-10-14. References name files and symbols, not line numbers.
-->

# Theme system design

## 1. What is being built

A generator. The one hand-written colour file is a palette that files each
value under its role ("primary accent"), not its look ("blue"); the generator
writes the role table in every consumer's format. Palettes are chosen by
name; none comes from a wallpaper.

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

`build` runs only when a palette changes, and its output is committed; `set`
runs any time and never dirties the tree.

---

## 2. Palette

### 2.1 Roles

Named by role, never by look: a light or green theme would otherwise put
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

`ink` is not `bg` (a light theme turns `bg` white and keeps `ink` dark), and
`border` is not `dim` (a borderless theme sets `border` to `bg`).

**Meaning (4).** Demanded by name by kdeglobals
(`ForegroundNegative/Neutral/Positive`) and GTK (`error/warning/success_color_breeze`).

| Role | Job | spaceduck | Source today |
|---|---|---|---|
| `accent` | Selection, focus ring, links, launcher row | `#7aa2f7` | `Theme.accentIndigo` |
| `positive` | OK: connected, charging, check marks | `#9ece6a` | `Theme.accentGreen` |
| `caution` | Take note: Hangul state | `#e0af68` | `Theme.accentAmber` |
| `critical` | Wrong: alerts, caps lock, critical toasts, logout, auth fail | `#f7768e` | `Theme.accentRed`, `caps-lock.zsh` |

**Distinction (6).** No meaning; they only differ side by side. Which tone
goes where is a rule and stays in `Theme.qml`.

| Role | spaceduck | Source today | Assigned (survey-era bar) |
|---|---|---|---|
| `tone1` | `#bb9af7` | `Theme.accentPurple` | media pill, memory load, visited links |
| `tone2` | `#7a5ccc` | `Theme.violet` | focused window chip |
| `tone3` | `#f2ce00` | `Theme.yellow` | workspace move indicator |
| `tone4` | `#7dcfff` | `Theme.accentSky` | clock/system badge, hover, links |
| `tone5` | `#ff9e64` | `Theme.accentOrange` | CPU load |
| `tone6` | `#c0caf5` | `Theme.accentQuiet` | quiet default pill, battery normal |

"Assigned" is the survey-era bar of coloured pills. The bar is now mostly
monochrome (`bg`, `fg`, `muted`; the OSD too), accents surviving in menus and
alerts, and tones appear only in `weatherColor()` (`accentSky`,
`accentPurple`, `accentQuiet`), `PowerMenu.qml` and `MediaPlayer.qml`
(`accentSky`). Reassign when implementing. Ground spaceduck, accents Tokyo
Night (sources in `Theme.qml`): the mix is this theme's identity, and
reconciling it is a new theme, not an edit.

**`Theme.qml`'s 27 colour literals that are not roles**

| Slot | Value | Fate |
|---|---|---|
| `red`, `green`, `blue` | `#e33400`, `#5ccc96`, `#00a3cc` | Unreferenced; delete |
| `purple` | `#b3a1e6` | Unreferenced; merges into `tone1` |
| `capsLock` | `#f7768e` | Removed (an unreferenced duplicate of `accentRed`). `caps-lock.zsh` still hard-codes the value; the generator's `critical` + `ink` replaces that cross-repo sync |
| `accentTeal` | `#73daca` | A PowerMenu item; becomes `positive` |
| `accentSaffron` | `#e4bf58` | Added after the survey; `StatusItem`'s active fill. Role undecided (`caution` is closest) |
| `accentJade`, `accentAzure`, `accentViolet`, `accentRose` | `#4dcbaa`, `#6a9ae7`, `#a076db`, `#d5729d` | Added after the survey; unreferenced |
| `accentAlert` | `#ef3963` | Unreferenced; kept as a record |

**ANSI 0-15 are a contract, not roles.** `ls`, `git` and `vim` address
colours by index. They live in a separate `ansi` array that only kitty
consumes; p10k's indexes 0-15 follow from it.

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

- `ansi` slots 3 and 5 hold purple and yellow on purpose: spaceduck's author
  swapped them (the disclaimer in `dotfiles-terminal/kitty/spaceduck.conf`).
  The array carries the swap; the generator knows nothing of it.
- `scheme` (`dark`/`light`) only drives gsettings `color-scheme`.
- `name` = file name = `theme set` argument. `label` is the KDE scheme name;
  without spaces it is the `.colors` file name and `ColorScheme` id.
- On adoption the KDE selection and the launcher row become `accent`. The
  Hyprland border stays `fg` on purpose (`rgba(ecf0c1ff)` in
  `hypr/config/general.lua`; the pin rule in `hypr/config/rules.lua` is `fg` +
  `dim`).

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
| `theme check` | Outputs and the `Theme.qml` fallback match the palettes; non-zero otherwise |
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

92 colour fields, 10 distinct values. One function, `kde_colors`, feeds both
files so they cannot drift (reapplying a scheme by name would make the screen
jump). `kdeglobals` = `theme/templates/kdeglobals.head` (today's
`kde/kdeglobals` minus colours: `[General]` fonts and `widgetStyle`,
`[Icons]`, `[KDE]`, `[Sounds]`) + `kde_colors`; the `.colors` copy exists only
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
`ChangeSelectionColor=false`, Color `dim`, all amounts and effects 0 (no
fading of unfocused windows).

### 3.4 Quickshell bar

`palette.json` = `{ name, scheme, roles, _generated }` via `jq`; JSON has no
comments, so the marker is the `_generated` key, and `Theme.qml` reads only
`.roles`. `Theme.qml` changes:

- Reads `${XDG_STATE_HOME:-~/.local/state}/theme/palette.json` at run time
  with a `FileView` declared before `palette` (no eager binding may see a
  missing id). State, not config: it is generated, and a file inside the
  quickshell config dir makes the watcher restart the whole shell.
- `blockLoading: true`: an async load paints the first frame from the
  fallback, then the `ColorAnimation`s (90-160 ms, in `StatusItem`,
  `SystemBadge`, `MediaPlayer`, `Workspaces`, `MediaChip`,
  `NotificationCentre`) smear every colour at startup.
- `watchChanges: true` plus an `IpcHandler { target: "theme"; reload() }`,
  which `theme set` calls: whether the watcher follows an inode swap
  (`mv -T`) is unconfirmed.
- `onLoadFailed`: quiet on `FileNotFound` (never set), a warning otherwise.
  `readPalette()`: `JSON.parse(text)?.roles ?? {}`, `{}` on any exception.
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

Consumer QML gets a `sed` rename (`bgAlt`→`surface`, `muted`→`dim`,
`beige`→`fill`, `accentIndigo`→`accent`, and the 2.1 mappings). The four
`Qt.rgba(1, 1, 1, a)` literals (`PopupMenu.qml` twice, `Launcher.qml`,
`PowerMenu.qml`) become `Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, a)`:
left white, the face vanishes in a light theme. The derived colours
(`menuBarLine`, `menuHover`, `surfaceDim`, ...) already follow `fg`, and the
rules (`weatherColor()`, `readableOn()`'s WCAG contrast pick of `ink` or `fg`)
stay hand-written; only names change.

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

"Link" = the consumer reads an absolute path under
`~/.local/state/theme/current`. Real files where a link is unsafe:
`kdeglobals` (`plasma-apply-colorscheme` rewrites it through KConfig
`QSaveFile`; symlink behaviour unconfirmed), `gtk-3.0/colors.css`
(`libcolorreload-gtk-module.so` watches the path with `g_file_monitor_file`,
so it must stay live) and `hypr/palette.lua` (a fixed path under `CONFIG`).

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

`general.lua` then sets `active_border = PALETTE.border` (from `fg`) and
`inactive_border = PALETTE.clear`; the `rules.lua` pin rule uses
`PALETTE.border .. " " .. PALETTE.dim`.

**hyprlock** is black and white only (`rgba(ffffff..)`, `rgba(000000..)`) and
needs no template. If it takes palette colours again:
`source = ~/.config/hypr/palette.conf` at the top, with Pango markup kept
whole in one variable (e.g. `$failText = <span foreground="@pango:critical@">$FAIL</span>`),
since variable expansion inside a string is unconfirmed.

**dotfiles-terminal** must work without this repo: fallback first, generated
override second.

- `kitty/kitty.conf`: `include ./spaceduck.conf`, then
  `include ~/.local/state/theme/current/kitty.conf` (a missing file costs one
  stderr line; spaceduck stands). Auto-reload works only if the included file
  existed at kitty start.
- `tmux/tmux.conf` end: `source-file -q ~/.local/state/theme/current/tmux.conf`.
- `zsh/zshrc` (its `FZF_DEFAULT_OPTS` already holds spaceduck values):
  `[[ -r ~/.local/state/theme/current/fzf.env ]] && source ...` (no colour
  beats wrong colour).
- `zsh/config/caps-lock.zsh`: `-b "${THEME_CRITICAL:-#f7768e}" -f "${THEME_INK:-#0f111b}"`.

**capture.sh** already reads `SLURP_BORDER` (`fg`), `SLURP_FILL` (`accent` at
`33` alpha), `SLURP_DIM` (`bg` at `99` alpha) and `SLURP_FONT` from the
environment with spaceduck defaults; `slurp.env` exports them, and
`capture.sh` sources it when readable.

**GTK: option B.** kded6 `gtkconfig` stays off (`kde/kded6rc`, done for the
cursor) and `colors.css` is written here: the module replaces the
`settings.ini` symlink with a real file and applies a kdeglobals-to-GTK
mapping nobody here controls.

`gtk-colors.css.in` redeclares Breeze-Dark's colour names; the 4465-line
`/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css` refers to nothing else, so no
rules are written. It declares 78 `*_breeze` names and references three more
it never declares: `theme_header_background_breeze`,
`theme_header_background_backdrop_breeze`, `unfocused_insensitive_color_breeze`;
the template defines all 81. kde-gtk-config's generated `colors.css` sets both
`theme_header_background*` to the button background, hence `surface` below;
neither project defines `unfocused_insensitive_color_breeze`, so mapping it to
`dim` (as `insensitive_fg_color`) is this design's choice. GTK4 Breeze-Dark
uses the same set, so one file serves both. Core mapping:

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

Each name carries the `_breeze` suffix. `unfocused_*` and `backdrop_*` reuse
the same values (no fading on focus loss, as with `[ColorEffects:Inactive]`);
the other five `theme_header_*` names in today's live `colors.css` are unused
by Breeze-Dark and are dropped.

`gtk4.css.in` covers libadwaita, which ignores `gtk-theme-name` and the
`_breeze` names, and ends with `@import 'colors.css';`:

| libadwaita name | Role |
|---|---|
| `window_bg_color`, `view_bg_color` | `bg` |
| `headerbar_bg_color`, `card_bg_color`, `sidebar_bg_color`, `popover_bg_color`, `dialog_bg_color` | `surface` |
| every matching `*_fg_color` above | `fg` |
| `accent_bg_color`, `accent_color` | `accent` |
| `destructive_bg_color` / `warning_bg_color` / `success_bg_color` | `critical` / `caution` / `positive` |
| `accent_fg_color`, `destructive_fg_color`, `warning_fg_color`, `success_fg_color` | `ink` |

### 3.6 build and set

`cmd_build [names]` (default: every palette): `load_palette`,
`guard_hand_edits` (5.2), then `kde_colors` into `kdeglobals` and
`<SCHEME_ID>.colors`, `palette.json` via `jq`, and `render | emit` for each
template with its comment leader (`/*!` for the two CSS files, `--` for
`hypr-palette.lua`, `#` for swappy, slurp, fuzzel, fcitx5, kitty, tmux, fzf).

`cmd_set <name>`:

1. `load_palette`; stop if `theme/out/<name>/` is missing (nothing on screen
   changes).
2. Swap the link atomically (`ln -sfn "$out" current.new && mv -T current.new current`):
   kitty repaints within ~0.1 s, the next slurp uses the new colours.
3. `install -Dm644` each real file to its path in 3.5 (install keeps the
   watched path and replaces the contents), and copy fcitx5's
   `arrow next prev radio` PNGs from `/usr/share/fcitx5/themes/default-dark/`
   if absent. GTK3 apps repaint as `gtk-3.0/colors.css` lands
   (`gtk/gtk-3.0-settings.ini` loads `colorreload-gtk-module`; swappy links
   `libgtk-3.so.0`, so an open swappy follows).
4. Record the name in `~/.local/state/theme/name`.
5. Signals, each `|| true` (the next start picks the change up):
   - `qs -p "$CONFIG/quickshell/bar" ipc call theme reload`: the bar re-reads
     and cross-fades through its `ColorAnimation`s; no rebuild, no popup.
   - `plasma-apply-colorscheme "$SCHEME_ID"`: emits
     `org.kde.KGlobalSettings.notifyChange`, and `KDEPlasmaPlatformTheme6.so`
     repaints running Qt apps; overwriting the file alone does not (KConfig
     signals only API writes). Its KWin `BlendChanges` call fails quietly
     under Hyprland.
   - `fcitx5-remote -r`: `ReloadConfig`, not a restart; input contexts survive.
   - `tmux source-file "$STATE/theme/current/tmux.conf"`.
   - gsettings `color-scheme`: `default` for light, `prefer-dark` otherwise.
6. `apply_hypr_border`: `hyprctl keyword` is unusable (Hyprland answers
   `keyword can't work with non-legacy parsers. Use eval.`; the config is
   Lua), so
   `hyprctl eval 'hl.config({ general = { col = { active_border = ..., inactive_border = "rgba(00000000)" } } })'`
   with `R_fg`, read back with `hyprctl getoption general:col.active_border`.
   If it did not take: `window border unchanged; run 'hyprctl reload' or relogin`.

### 3.7 What the script must not do

| Never | Why |
|---|---|
| `hyprctl reload` unless `--reload-hypr` | Drops every monitor rule and timer and re-runs the `monitors.lua` output policy (and `execs.lua`); too much churn for colours |
| Touch mode setting (`hl.monitor`, scale, enable/disable) | A modeset is what this GPU is least trusted with (`hypr/config/general.lua`) |
| Restart the bar (`bin/bar --restart`) | Drops the bar's in-memory state; the IPC reload suffices, else the next start reads the file |
| Restart fcitx5 | Costs every window its input context (`install.sh`); `-r` is a reload |
| Set gsettings `gtk-theme`, `icon-theme`, `cursor-*` | Owned by `hypr/scripts/gsettings-apply.sh`; only `color-scheme` is ours |
| Change the wallpaper | User state; deriving colours from it is rejected |
| End or offer to end the session | Say what needs a restart and stop |
| Overwrite a hand-edited generated file | `build` stops (5.2) |

---

## 4. What needs a restart

| Consumer | When | Why |
|---|---|---|
| GTK4, libadwaita | App restart | No `colorreload` equivalent; whether GTK4 watches `gtk.css` is unconfirmed |
| zsh prompt, fzf | New shell | p10k reads its config once at start |
| hyprlock | Next lock | No reload path (`reload_cmd` is for label widgets, SIGUSR1 unlocks); monochrome now anyway |
| fuzzel, swappy `custom_color` | Next run | Launched per invocation; fuzzel has no SIGUSR or inotify |
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
| `~/.local/state/theme/{current,palette.json,name}` | untracked run-time state; `theme set` recreates it |

`theme/out/` is tracked so `install.sh` only copies and never needs `jq`; it
appends:

```bash
"$SRC/bin/theme" set "$(cat "$SRC/theme/default")"
"$SRC/bin/theme" check || echo "theme: generated files do not match the palettes" >&2
```

### 5.2 Marker and checks

A rebuild would silently erase hand edits; the marker makes that impossible.
Every generated file starts with three lines (comment leader per format):

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
same three facts in its `_generated` key. `cmd_check` runs `guard_hand_edits`
over every palette's output, then checks each role's value between
`THEME-FALLBACK-BEGIN` and `END` in `Theme.qml` against `spaceduck.json` (awk:
find `property color <role>:`, require `"<value>"`); a drifted fallback would
otherwise show only when the bar fails to read the state file.

### 5.3 Host cleanup (pointed at, never deleted by `install.sh`)

Matugen leftovers once overrode the repo (GTK was Material You grey-purple).
As of 2026-10-14 only `~/.config/xsettingsd/xsettingsd.conf` remains; the
rest (`~/.config/matugen/`, `window_decorations.css` and `assets/` in
gtk-3.0/4.0, `fuzzel_theme.ini`, `qt5ct`, `qt6ct`, `Kvantum`,
`MaterialYou*.colors`, `~/.config/kdedefaults/kdeglobals`) is gone.
`gtk-3.0/gtk.css` and `gtk-4.0/colors.css` stay: `theme set` overwrites them.

---

## 6. The first two themes

**spaceduck**: today's screen in the role table (values in 2.1 and 2.2).

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

Deliberately unlike spaceduck (graphite ground, near-white text, system
blue); its `ansi` has no yellow/purple swap (3 = yellow, 5 = purple), which
tests that one format holds both conventions; `dim` and `tone6` are both grey,
since macOS separates status by brightness, not hue. A third, light theme is
the real test: `scheme: "light"` flips gsettings, `ink` and `bg` diverge, and
the `fg`-derived faces follow.

---

## 7. Limits

| Fixed | Why |
|---|---|
| Qt widget style (Breeze) | `widgetStyle=Breeze` in `kde/kdeglobals`; shape lives in compiled C++. Kvantum is ignored under `QT_QPA_PLATFORMTHEME=kde` (`hypr/config/env.lua`), and switching that drops the kdeglobals colours |
| GTK theme (Breeze-Dark) | Its 4465-line CSS carries sizes, radii and shadows as rules; only colour names are swapped |
| Icon theme (`breeze-dark`) | Colour baked into thousands of SVG and PNG files |
| Breeze GTK asset PNGs | Pre-rendered in Breeze blue `#3daee9` (checkbox marks, arrows) |
| p10k prompt | 223 of the 233 colour assignments in `dotfiles-terminal/zsh/p10k.zsh` are 256-colour indexes (16-255 are fixed), and the vi-mode segment's six are spaceduck hex literals. Only the caps-lock segment (`zsh/config/caps-lock.zsh`) is bound, because it shares the bar's `accentRed` |
| hyprpicker | Draws no colours of its own; no config |
| Fonts | Tied across the `kde/kdeglobals` `font=` lines, `fontconfig/local.conf` and `gsettings-apply.sh`; left hand-written as an extension point |

Notifications are not a separate consumer: the bar owns
`org.freedesktop.Notifications`, and its toasts read `Theme` directly.

Net: the same desktop with every colour changed (backgrounds, text, accents,
borders, selection, the 16 terminal colours, bar, candidate window, capture
editor, light or dark); shapes, icons, checkbox marks, animations and fonts
stay. A macOS palette looks like Breeze wearing macOS colours; more would
need a new widget style, which conflicts with using official packages only.
