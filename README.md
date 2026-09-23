# dotfiles-desktop

Desktop configuration for a Wayland session on Hyprland, with a status bar
written in QML for quickshell.

## Layout

```
hypr/hyprland.lua    entry point; loads hypr/config/, then ~/.config/hypr/local.lua
                     if present (untracked, never installed)
hypr/config/         Hyprland configuration in Lua: keybinds, rules, env, outputs
hypr/scripts/        what the keybinds and the units call: capture, lock, session
hypr/*.conf          hypridle, hyprlock and hyprpaper (seeded, see below)
hypr/monitor_settings_example.lua
                     template for the untracked per-machine output settings
quickshell/bar/      the status bar
systemd/user/        the session target, one unit per long-running program, and
                     the slice the launcher's programs run in
dbus/                fcitx5's D-Bus activation, pointed at its unit
bin/                 bar and unlock (to ~/.local/bin), recover-desktop (to ~/)
fontconfig/          font chain: Inter for Latin, Pretendard for Hangul
gtk/                 GTK 3 and 4 settings
kde/                 Qt and KDE colours, so file dialogs match the bar
tuigreet/            the greeter's appearance, installed only when greetd runs it
fcitx5/              Korean input configuration
node/                node REPL helpers and the profile.d drop-in that loads them
iex/                 the same helpers for IEx, as ~/.iex.exs
theme/               colour system notes and the cursor theme builder
```

## REPL helpers

`hex`, `bin` and `oct` in the node REPL and in IEx print a value in that base.
They take integers, floats, booleans (1 and 0) and a single character, read as
its code point, so `hex('a') - 43` is 54. Anything else is an error.

They exist only in an interactive REPL. IEx reads `~/.iex.exs` only when it
starts a shell. For node, `~/.config/profile.d/node.sh` adds
`--require "$HOME/.config/node/repl.js"` to `NODE_OPTIONS`, and `repl.js` defines
nothing unless node was started as a bare REPL. Scripts, `-e`, `-p`, piped
input and workers are left alone. `node.sh` removes the flag again when node
or `repl.js` is missing, so a missing file never breaks node.

`node.sh` depends on the shell sourcing `~/.config/profile.d/*.sh`, which
dotfiles-terminal's `zshenv` and `bashrc` do.

## Outputs and the session

`hypr/config/monitors.lua` decides which screens are on, inside the compositor:
any external output becomes the desktop and the built-in panel goes off; with
none, the panel is the desktop. `keep_internal` in the settings, or a file
named `~/.config/hypr/keep-internal`, keeps both. It follows hotplug through
Hyprland's events, re-applies on every reload, and turns the panel back on if
nothing is enabled. There is no watcher process.
`hypr/scripts/monitors-selftest.sh` exercises it in a nested compositor.

Per-machine values (panel scale, keep_internal) go in the untracked
`hypr/monitor_settings.lua`: copy `hypr/monitor_settings_example.lua`, which
documents every field, and edit it. Without the file, or with a broken one, the
policy runs on defaults and says so in a notification. The file is not watched;
run `./install.sh` (which mirrors it) or `hyprctl reload` after editing.

The lid and power-button bindings assume logind leaves those keys alone. These
system files are not installed from here:

    # /etc/systemd/logind.conf.d/10-lid.conf
    [Login]
    HandleLidSwitch=ignore
    HandleLidSwitchExternalPower=ignore
    HandleLidSwitchDocked=ignore

    # /etc/systemd/logind.conf.d/20-powerkey.conf
    [Login]
    HandlePowerKey=ignore
    HandlePowerKeyLongPress=poweroff

Every long-running program (the bar, fcitx5, hyprpaper, the clipboard
watchers, the polkit agent, hypridle) is a systemd user unit under
`hyprland-session.target`. The compositor starts the target through
`hypr/scripts/session-start.sh`; `hyprland-session-watch.service` stops it when
the compositor's lock file goes away, so a logout leaves nothing behind.
`Ctrl+Super+R` runs the start script again, which starts whatever died.

The units use `Restart=always` (fcitx5 is `on-failure`): systemd counts SIGTERM
and exit 0 as success, so a bar killed by a stray `pkill` would otherwise stay
down. Most units cap at five starts in two minutes; a unit at that limit also
refuses `restart`, so `bar --restart` runs `reset-failed` first.

    systemctl --user status hyprland-session.target
    journalctl --user -u bar.service -f
    journalctl --user -t session-start

When the desktop is running but cannot be seen, run `~/recover-desktop` from a
text console (Ctrl+Alt+F2). It removes outputs no connector backs, turns DPMS
on, re-runs the monitor policy (or enables the built-in panel if the policy is
not loaded), and restarts what died in the session target. `--status` only
diagnoses; `--logout` and `--kill` are the only modes that end the session. A
lock screen that will not go away is `unlock`'s job.

## The bar

A menu bar, in the macOS sense: two groups and what is playing between them.

```
left     arch badge, the ten workspaces, the focused window's application
centre   what is playing
right    caps lock, input method, alarm, network, bluetooth,
         cpu, memory, battery, notifications, weather, clock
```

No `File / Edit / View` menu. Wayland has no global menu protocol, and only Qt
and KDE applications export one over D-Bus.

Status items are glyphs and short readouts. Colour appears only past a limit
(CPU and memory at 90%, battery at 10%), in the red the calendar uses for
Sunday.

The workspace row shows the block of ten containing the current one, so its
width never changes. Scrolling it walks the workspaces.

Every dimension derives from `Theme.scale`: the physical size of one logical
pixel, from the millimetres the output reports over its logical width. The
compositor's scale is already inside that number, so do not multiply by
`devicePixelRatio` (Qt rounds it up to an integer). `BAR_SCALE` overrides it.

The centre chip stays centred on the screen but is capped by the room the two
groups leave, dropping its meter and then its title before it overlaps them.

### Popups and notifications

Hovering the centre chip opens the player (art, title, seekable position,
transport); hovering the clock opens the month. Both are `PopupWindow`s anchored
to the bar, not layer surfaces: a layer surface is always placed outside other
surfaces' exclusive zones, so it could not overlap the bar.
`services/Media.qml` holds the shared hover state, since neither window sees
the other's pointer.

Cover art loads only from local files and from a short allowlist of cover-art
hosts over https (`Theme.artHosts`). A browser's `mpris:artUrl` is chosen by
the page, so fetching it as given would turn any tab into a beacon.

The bar is also the notification server. Toasts stack under its right edge and
history is behind `Super+N`. A toast dwells 5 s (20 s when critical), shown by
the bar along its bottom edge. Drag right to dismiss; click to run the default
action. Critical toasts time out too, because the history panel keeps them.

Before editing the QML:

- Nerd Font glyphs are written as code points (`String.fromCodePoint`), not
  literal characters. The Material Design ranges are astral and turn into tofu
  when a file is re-encoded.
- quickshell's `percentage`, `signalStrength` and `battery` are 0.0 to 1.0
  despite their names. Multiply by 100 at the point of use.

### Running the bar

```sh
bar --restart        # pick up a QML change
bar --status         # running or not, plus the last log lines
bar --log            # follow quickshell's output

systemctl --user stop app-hyprland.slice   # close what the bar opened, not the bar

BAR_PREVIEW=bottom bar --once   # preview, reserves no space
BAR_VIZ_DEMO=1     bar --once   # visualiser without audio
```

`--once` runs quickshell in the foreground outside its unit. Two copies of one
config cannot run together, so stop the unit first or point `BAR_CONFIG_DIR` at
a copy. Preview mode anchors to an edge without an exclusive zone.

Programs opened from the launcher and the pills run in `app-hyprland.slice`
through `quickshell/bar/scripts/app-scope.sh`, so `bar --restart` leaves them
alone. They still end with the session, because the slice is `PartOf` its
target.

## Install

```sh
./install.sh           # install
./install.sh --check   # list what is behind, exit 1 if anything is
```

Files are copied, never linked. **Nothing edited here runs until
`./install.sh` runs again**, and a running unit keeps its old code until it is
restarted.

A **mirror** is for what this repository authors: the Hyprland config and
scripts, the quickshell tree, `bin/`, the systemd units, the D-Bus service,
the node and IEx helpers, and `hypr/monitor_settings.lua` if present. Every run
overwrites them. A mirrored directory also loses files the repository no longer
has, and a unit whose first line is `# dotfiles-desktop` is removed once its
source is gone. Links were dropped because the installed path then resolved
back into the working tree, and a directory swapped under a watcher crashes it
instead of reloading.

A **seed** is for what a program owns: fcitx5, GTK, KDE, and hypridle,
hyprlock and hyprpaper configs. These programs save by renaming a temp file over
the target, which replaces a symlink instead of following it. A seed is copied
once and never overwritten; the installer reports one that has diverged.

    seeded ~/.config/fcitx5/config
    left ~/.config/kdeglobals alone: it exists and differs from <repo>/kde/kdeglobals
      whatever owns it has rewritten it; copy it back into <repo>/kde/kdeglobals to keep the change

To keep a change made in a program's settings, copy the file back here. To push
one out, delete the installed file and run the installer again.

The installer also:

- parse-checks the Hyprland config with `hypr/scripts/verify-config.sh` and
  refuses to copy anything if it does not load. Mirroring reloads the running
  compositor, and a module that throws sends the session to emergency mode. A
  machine without Hyprland gets a warning and an unchecked copy.
- asks for sudo once, up front, to write `/etc/fonts/local.conf` and, only when
  greetd runs tuigreet, `/etc/tuigreet/config.toml`. Each existing file is kept
  as `.bak-<timestamp>`. These are the only backups; mirrors and seeds get none.
- builds the `Spaceduck-Sky` cursor theme from `Oxygen_White` with
  `theme/cursor/`. XCursor themes are bitmaps, so the colour must be baked in.
- disables `kde-baloo.service` and masks KDE's drkonqi coredump units, which
  crash-loop without a Wayland display.
- runs `systemctl --user daemon-reload`, enables `hypridle.service` and
  reloads Hyprland. Running units are not restarted; the next login or
  `Ctrl+Super+R` picks up new ones.

The shell, terminal emulator and prompt live in
[dotfiles-terminal](https://github.com/yugeun-song/dotfiles-terminal), which
has its own `install.sh` and a `bootstrap.sh` for the parts that are cloned
rather than installed.

## Credits

The palette combines two published themes, used in the bar, in Qt
applications and in the shell:

- [Spaceduck](https://github.com/pineapplegiant/spaceduck) by pineapplegiant:
  background, foreground, greys and selection.
- [Tokyo Night](https://github.com/folke/tokyonight.nvim) by folke: the blue,
  cyan, purple, green and orange accents.

Only the colour values were taken, no code.
