# dotfiles-desktop

Desktop-side configuration for a Wayland session built on Hyprland with a
status bar written in QML for quickshell.

## Layout

```
hypr/config/      Hyprland configuration in Lua: keybinds, rules, env, monitors
hypr/scripts/     what those keybinds call: monitor switching, capture, lock
quickshell/bar/   the status bar, written from scratch
bin/              commands on $PATH: bar, unlock
fontconfig/       font chain: Inter for latin, Pretendard for Hangul
gtk/              GTK 3 and 4 settings
kde/              Qt and KDE colours, so file dialogs match the bar
fcitx5/           Korean input configuration
theme/            design notes for the colour system
```

## The bar

```
left     arch badge, workspace numbers with a sliding indicator
centre   windows on the focused workspace, then the media pill
right    input method, caps lock, alarm, weather, network,
         bluetooth, battery, cpu, memory
```

Every dimension derives from one number, `Theme.scale`, which is itself
derived from the logical height of the screen the bar is drawn on. Set
`BAR_SCALE` to override it.

Two things are worth knowing before editing it.

Nerd Font glyphs are written as code points rather than literal characters.
The Material Design ranges live in the astral plane and are easy to corrupt
when a file is copied or re-encoded, and a corrupted one renders as tofu.

quickshell reports fractions, not percentages. `percentage`, `signalStrength`
and `battery` all arrive as 0.0 to 1.0 despite their names, so every one of
them is multiplied by 100 at the point of use. Reading one raw pins a full
battery at 1%.

## Links and copies

Two ways in, and which one a file gets is not a style choice.

A **link** is for what is written here and reloaded in place: the Hyprland
configuration, the quickshell tree, the scripts. `hyprctl reload` and a bar
restart read those straight off disk, so editing through a copy would mean
running the installer between every change. Nothing else writes to them, so
the link cannot be replaced behind anyone's back.

A **copy** is for everything a program owns. fcitx5, KDE and GTK save by
writing a temp file beside the target and rename()-ing it over, and rename()
replaces a symlink rather than following it: the first change made in one of
their settings windows turns the link into a real file, and this repository
quietly stops being what the machine reads. `p10k configure` is worse, writing
through the link and editing the repository without saying so.

So those are seeded: copied once, and left alone afterwards. The installer
says what it did, and refuses to overwrite a seeded file that has diverged.

    seeded ~/.config/fcitx5/config
    left ~/.config/kdeglobals alone: it exists and differs
      copy it back into <repo> to keep the change

**After editing a seeded file here, run `./install.sh` again** — a copy does
not update itself. To keep a change made through a program's own interface,
copy the file back into this repository.

## Install

```sh
./install.sh
```

Existing configuration is moved aside with a timestamp, never replaced.

The shell, terminal emulator and prompt are not here. They live in
[dotfiles-terminal](https://github.com/yugeun-song/dotfiles-terminal), which
has its own `install.sh` and a `bootstrap.sh` for the parts that have to be
cloned rather than installed.

## Credits

The colour palette is not original. It is a pair of published themes used
together, and the same values appear in the bar, in Qt applications and in
the shell:

- [Spaceduck](https://github.com/pineapplegiant/spaceduck) by pineapplegiant
  gives the background, foreground, greys and selection.
- [Tokyo Night](https://github.com/folke/tokyonight.nvim) by folke gives the
  blue, cyan, purple, green and orange accents.

Nothing here contains code from either project; only the colour values were
taken. The links are here so the originals can be found and because credit
for the work is due.

## Running the bar

```sh
qs -p ~/.config/quickshell/bar

BAR_PREVIEW=bottom qs -p ~/.config/quickshell/bar   # preview, reserves no space
BAR_VIZ_DEMO=1     qs -p ~/.config/quickshell/bar   # visualiser without audio
```

Preview mode anchors the bar to an edge without claiming an exclusive zone, so
it can sit alongside another shell while being worked on.
