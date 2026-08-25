# dotfiles-desktop

Desktop-side configuration for a Wayland session built on Hyprland with a
status bar written in QML for quickshell.

## Layout

```
hypr/custom/      Hyprland overrides: keybinds, rules, env, monitor switching
quickshell/bar/   the status bar, written from scratch
fontconfig/       font chain: Inter for latin, Pretendard for Hangul
gtk/              GTK 3 and 4 settings
fcitx5/           Korean input configuration
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

## Install

```sh
./install.sh
```

Existing configuration is moved aside with a timestamp, never replaced.

## Running the bar

```sh
qs -p ~/.config/quickshell/bar

BAR_PREVIEW=bottom qs -p ~/.config/quickshell/bar   # preview, reserves no space
BAR_VIZ_DEMO=1     qs -p ~/.config/quickshell/bar   # visualiser without audio
```

Preview mode anchors the bar to an edge without claiming an exclusive zone, so
it can sit alongside another shell while being worked on.
