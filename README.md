# dotfiles-desktop

Desktop configuration for a Wayland session on Hyprland, with a status bar
written in QML for quickshell. The tracked files are one laptop's settings,
kept as the preset; whatever the machine at hand differs in is detected and
adapted to, or reported, rather than assumed.

## Layout

```
hypr/hyprland.lua    entry point; loads hypr/config/, then ~/.config/hypr/local.lua
                     if present (untracked, never installed)
hypr/config/         Hyprland configuration in Lua: env, general, outputs, rules,
                     keybinds, execs
hypr/scripts/        what the keybinds and the units call: capture, lock, session,
                     power, monitor overrides, the nested self-test
hypr/*.conf          hypridle, hyprlock and hyprpaper (seeded, see Install)
hypr/monitor_settings.lua
                     the output preset: scales, auto_scale, main, workspaces,
                     keep_internal; monitor_settings.local.lua beside it holds
                     one machine's deviations (untracked)
quickshell/bar/      the status bar and every panel it opens
systemd/user/        the session target, one unit per long-running program, and
                     the slice the launcher's programs run in
dbus/                fcitx5's D-Bus activation, pointed at its unit
bin/                 bar and unlock (to ~/.local/bin), recover-desktop (to ~/)
fontconfig/          font chain: Inter for Latin, Pretendard for Hangul
gtk/ kde/            GTK settings; Qt and KDE colours, so dialogs match the bar
tuigreet/            the greeter's appearance, installed only when greetd runs it
fcitx5/              Korean input configuration
node/ iex/           REPL helpers (hex, bin, oct) for node and IEx
theme/               colour system notes and the cursor theme builder
```

## Outputs

`hypr/config/monitors.lua` decides which screens are on, inside the compositor
(no watcher process): with an external attached both screens are on, shutting
the lid turns the panel off, and alone the panel is the desktop. It follows
hotplug and the lid through Hyprland's events, re-applies on every reload,
turns the panel back on when nothing is enabled, and never lights and darkens
outputs in one commit (that once wedged the compositor with no output).
`hypr/scripts/monitors-selftest.sh` exercises it in a nested compositor; run
it on a visible workspace, since Hyprland applies monitor rules only when
some output draws a frame.

**Preset and detection.** `hypr/monitor_settings.lua` holds the tracked
values, every field documented there: a scale per display named by its
description, `auto_scale` targets, `main` (which external takes 0x0 and the
workspaces), `workspaces` (see below) and `keep_internal`. Another machine's
deviations go in the untracked `monitor_settings.local.lua`, same fields,
winning per field. An entry for a display that is not there is inert; a
display the preset does not name gets its values from itself: the highest
refresh rate and, at that rate, the largest resolution (`highrr`), and the
scale step (1 to 3 in quarters, then 2.5, 3) that keeps the logical size
integral and lands the logical width nearest 1920 for a panel or 2560 for an
external (2880x1800 runs at 1.5, a 4K panel at 2, a 1440p monitor at 1, a 4K
one at 1.5). `hyprctl repl 'return MONITORS.describe()'` prints where every
value came from.

**Workspaces.** `workspaces = "dynamic"` is Hyprland's own behaviour and the
code's default: nothing is bound, a workspace opens where it is asked for and
stays. The preset says `"panel-first"`: workspace 1 on the built-in panel,
2 to 100 on the main external, so the panel is a side screen. `"blocks"`
also gives each further external ten of its own (11-20, 21-30). The main
external is the preset's `main` if it is lit, else the largest logical area,
then name order. One rule per id, because a range selector binds existing
workspaces but not one being created; 100 is the ceiling the keybinds share.

**The Displays panel.** `Super+O`, or the laptop's display key, opens it: the
outputs as numbered rectangles (Identify flashes the numbers), the layout
presets (laptop only, external only, extend left or right, mirror) with the
current one marked, the workspace scheme (preset, panel first, blocks,
dynamic), and for the selected output power, mode, scale, rotation and side.
Apply writes `~/.local/state/hypr/monitor-overrides` through
`hypr/scripts/monitor-override.sh` (`show | set < lines | clear | revert`) and
re-evaluates; a 30 s countdown reverts unless Keep is pressed (Esc reverts at
once), so a mode the screen cannot show undoes itself. The file is one line
per override, `<selector> TAB <field> TAB <value>`: the selector is the
description as `hyprctl monitors` prints it with commas removed, or
`name:<connector>`, or `*` for the desk-wide `workspaces` line. The policy
keeps the last word: the panel goes off only beside a lit external, an
external only while another output stays lit, external-off is suspended while
the lid is shut, and a mode the output does not list falls back to automatic.

The lid and power-button bindings assume logind ignores those keys
(`HandleLidSwitch=ignore` and its Docked/ExternalPower variants,
`HandlePowerKey=ignore`, `HandlePowerKeyLongPress=poweroff` in
`/etc/systemd/logind.conf.d/`); those files are not installed from here.

## The session

Every long-running program (the bar, fcitx5, hyprpaper, the clipboard
watchers, the polkit agent, hypridle) is a systemd user unit under
`hyprland-session.target`. `hypr/scripts/session-start.sh` imports the
compositor's environment and starts the target; `hyprland-session-watch.service`
stops it when the compositor's lock file goes, so a logout leaves nothing
behind. Hyprland 0.57 would start a target of the same name itself, before
the environment is imported; `HYPRLAND_NO_SD_TARGET` in `config/env.lua` opts
out. `Ctrl+Super+R` runs the start script again, which starts whatever died.
Units use `Restart=always` (systemd counts SIGTERM as success, so a pkilled
bar would otherwise stay down) with a cap of five starts in two minutes;
`bar --restart` runs `reset-failed` first.

The tracked settings assume this laptop's stack (fcitx5, kitty, Breeze,
PipeWire, the Spaceduck-Sky cursor, Inter and a Nerd Font) and every one of
them is checked rather than relied on: `config/env.lua` names the VA-API
driver whose library is installed, the Qt platform theme whose plugin exists,
the input-method variables only with fcitx5 present and the cursor theme only
once it is built; `scripts/gsettings-apply.sh` sets the GTK theme and icons
only where they are installed; the bar takes the first installed of its
fonts, draws the distribution's own badge from `/etc/os-release`, and opens
terminal programs through `scripts/terminal.sh`, which runs the first terminal
found; the volume keys go through `scripts/volume.sh` (wpctl, then pactl,
then amixer) and the media keys through `launch.sh`, so a missing tool gives
one notification instead of a dead key.

Shut down and Restart in the session menu, and `Ctrl+Shift+Alt+Super+Delete`,
go through `hypr/scripts/session-power.sh`: under a logind delay lock it
requests the action, ends the compositor, waits for it to be gone, then lets
the transaction run. A direct `systemctl poweroff` with an external lit hung
this machine after userspace had finished; signing out first never did. It
runs as a transient user unit outside the session target, which would kill it
the moment the lock file went. `hypridle` resumes the screens through
`MONITORS.resume()`, which re-reads the lid before lighting the panel.

    systemctl --user status hyprland-session.target
    journalctl --user -u bar.service -f
    journalctl --user -t session-start
    journalctl --user -u session-power-poweroff

When the desktop runs but cannot be seen, `~/recover-desktop` from a text
console (Ctrl+Alt+F2) removes outputs no connector backs, turns DPMS on,
re-runs the policy and restarts what died; `--status` only diagnoses,
`--logout` and `--kill` end the session. A lock screen that will not go away
is `unlock`'s job.

## The bar

A menu bar, in the macOS sense: two groups and what is playing between them.

```
left     arch badge, the ten workspaces, the focused window's application
centre   what is playing
right    caps lock, input method, alarm, network, bluetooth,
         cpu, memory, battery, notifications, weather, clock
```

No `File / Edit / View` menu: Wayland has no global menu protocol. Status
items are glyphs and short readouts; colour appears only past a limit (CPU
and memory at 90%, battery at 10%). The workspace row shows the block of ten
containing the current one, so its width never changes; scrolling it walks
the workspaces. The centre chip stays centred but drops its meter, then its
title, before it would overlap the groups.

**Sizing.** Every dimension is `Theme.px()` of one scale, tuned on the
2560x1440 desk monitor; `BAR_SCALE` overrides it. Each window then draws
itself scaled by `Theme.fit(screen)`, the square root of its screen's logical
area over the reference's, so the bar, every popup and every panel keep the
share of the screen and the aspect ratio they have on that monitor (the
1920x1200 panel gets 0.79). Text stays vector-sharp under the transform.
`config/monitors.lua` scales Hyprland's gaps, border and rounding per output
by the same factor through monitor-selector rules; blur and shadow have no
per-output form and stay global.

**Popups and notifications.** Hovering the centre chip opens the player,
hovering the clock the month; both are `PopupWindow`s anchored to the bar (a
layer surface could not overlap it). Cover art loads only from local files
and a short allowlist of hosts (`Theme.artHosts`), since a browser's
`mpris:artUrl` is chosen by the page. The bar is also the notification
server: toasts stack under its right edge, history is behind `Super+N`, a
toast dwells 5 s (20 s critical), drag right dismisses, click runs the default
action. `Super+/` lists every binding with a description, `Super+Y` shows the
keys being pressed.

Before editing the QML: Nerd Font glyphs are written as code points, because
the Material ranges are astral and turn into tofu when re-encoded; quickshell's
`percentage`, `signalStrength` and `battery` are 0.0 to 1.0 despite their
names; a `pragma Singleton` file under `services/` must import QtQuick or
quickshell 0.3.1 leaves it out of the module.

```sh
bar --restart        # pick up a QML change
bar --status         # running or not, plus the last log lines
bar --log            # follow quickshell's output
systemctl --user stop app-hyprland.slice   # close what the bar opened, not the bar
BAR_PREVIEW=bottom bar --once   # preview, reserves no space
BAR_VIZ_DEMO=1     bar --once   # visualiser without audio
```

`--once` runs quickshell in the foreground outside its unit; two copies of one
config cannot run together, so stop the unit or point `BAR_CONFIG_DIR` at a
copy. Programs opened from the launcher and the pills run in
`app-hyprland.slice` through `scripts/app-scope.sh`, so `bar --restart` leaves
them alone and they still end with the session.

## Install

```sh
./install.sh           # install; ends with a doctor line
./install.sh --check   # list what is behind, exit 1 if anything is
```

Files are copied, never linked, so **nothing edited here runs until
`./install.sh` runs again**, and a running unit keeps its old code until it
is restarted. A **mirror** is what this repository authors (the Hyprland
config and scripts, the quickshell tree, `bin/`, the units, the D-Bus service,
the REPL helpers, the Spotify launcher flags, the output preset and its local
file): overwritten every run, pruned of files the repository dropped, and a
unit whose first line is `# dotfiles-desktop` is removed once its source is
gone. A **seed** is what a program owns (fcitx5, GTK, KDE, hypridle, hyprlock,
hyprpaper): copied once, never overwritten, reported when it has diverged. To
keep a change a program made, copy the file back here; to push one out,
delete the installed file and run the installer again.

The installer also parse-checks the Hyprland config (with the preset) and
refuses to copy anything that does not load, since a mirror reloads the
running compositor; asks for sudo once for `/etc/fonts/local.conf` and, only
under tuigreet, `/etc/tuigreet/config.toml`, keeping `.bak-<timestamp>`
copies; builds the `Spaceduck-Sky` cursor theme (bitmaps, so the colour is
baked in); disables `kde-baloo` and masks the drkonqi coredump units, which
crash-loop without a display; runs `daemon-reload`, enables `hypridle` and
reloads Hyprland. Its doctor line names the fonts and tools the desktop uses
that this machine lacks; every script degrades on its own without them, but
only says so when its key is pressed.

The shell, terminal emulator and prompt live in
[dotfiles-terminal](https://github.com/yugeun-song/dotfiles-terminal), which
has its own `install.sh`. Its `zshenv` and `bashrc` source
`~/.config/profile.d/*.sh`, which is how `node.sh` adds the REPL helpers
(`hex`, `bin`, `oct`) to a bare node REPL only; `~/.iex.exs` does the same for
IEx.

## Credits

The palette combines two published themes, used in the bar, in Qt
applications and in the shell: [Spaceduck](https://github.com/pineapplegiant/spaceduck)
by pineapplegiant (background, foreground, greys, selection) and
[Tokyo Night](https://github.com/folke/tokyonight.nvim) by folke (the blue,
cyan, purple, green and orange accents). Only the colour values were taken.
