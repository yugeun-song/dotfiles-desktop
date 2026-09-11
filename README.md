# dotfiles-desktop

Desktop-side configuration for a Wayland session built on Hyprland with a
status bar written in QML for quickshell.

## Layout

```
hypr/config/      Hyprland configuration in Lua: keybinds, rules, env, outputs
hypr/scripts/     what the keybinds and the units call: capture, lock, session
quickshell/bar/   the status bar, written from scratch
systemd/user/     the session target, one unit per long-running program, and
                  the slice the launcher's programs run in
dbus/             fcitx5's D-Bus activation, pointed at its unit
bin/              commands on $PATH: bar, unlock
fontconfig/       font chain: Inter for latin, Pretendard for Hangul
gtk/              GTK 3 and 4 settings
kde/              Qt and KDE colours, so file dialogs match the bar
tuigreet/         the greeter's appearance, installed only when greetd runs it
fcitx5/           Korean input configuration
theme/            design notes for the colour system
```

## Outputs and the session

Which screens are on is decided inside the compositor, by
`hypr/config/monitors.lua`: any external output becomes the desktop and the
built-in panel goes off; with none, the panel is the desktop; `keep_internal`
in the settings, or a file named `~/.config/hypr/keep-internal`, means both.
It reacts to hotplug through Hyprland's own events, re-applies itself on every
reload, and turns the panel back on if it ever finds nothing enabled. There is
no watcher process. `hypr/scripts/monitors-selftest.sh` exercises all of it in
a nested compositor.

What describes one machine -- the scale of its panel, whether it wants both
screens -- lives in `hypr/monitor_settings.lua`, which is not tracked. Copy
`hypr/monitor_settings_example.lua` to that name and edit it; the example
documents every field and carries the values in use on the machine this was
written on. Without the file, or with a broken one, the policy runs on its
defaults and says so in a notification. The compositor does not watch the
file; `hyprctl reload` after editing it.

The lid binding assumes logind leaves the lid switch alone, which is a system
file this repository does not install:

    # /etc/systemd/logind.conf.d/10-lid.conf
    [Login]
    HandleLidSwitch=ignore
    HandleLidSwitchExternalPower=ignore
    HandleLidSwitchDocked=ignore

Everything with a process behind it -- the bar, fcitx5, hyprpaper, the
clipboard watchers, the polkit agent, hypridle -- is a systemd user unit under
`hyprland-session.target`. The compositor starts the target through
`hypr/scripts/session-start.sh` and a watch on its lock file stops it, so a
logout leaves nothing behind and a unit that goes down comes back on its own.
`Ctrl+Super+R` runs the start script again, which starts whatever died.

They restart on anything but a stop, not only on a failing exit: systemd counts
SIGTERM and exit 0 as success, so a bar killed by a stray `pkill` used to go
quietly to inactive with nothing failed. Five starts in two minutes is still
the ceiling, and `bar --restart` clears it first, because a unit that has hit
it refuses `restart` too.

    systemctl --user status hyprland-session.target
    journalctl --user -u bar.service -f
    journalctl --user -t session-start

When the desktop is there and cannot be seen, `~/recover-desktop` from a text
console (Ctrl+Alt+F2) finds the compositor, removes outputs no connector
backs, turns DPMS on, asks for the built-in panel and restarts what died. It
ends nothing unless told to with `--logout` or `--kill`. A lock screen that
will not go away is `unlock`'s job.

## The bar

A menu bar, in the macOS sense: two groups and what is playing between them.

```
left     arch badge, the ten workspaces, the focused window's application
centre   what is playing, in the bar's own type
right    input method, caps lock, alarm, network, bluetooth,
         cpu, memory, battery, notifications, weather, clock
```

No `File / Edit / View` after the application name. Wayland has no global menu
protocol, so a bar can only show what an application exported over D-Bus, which
Qt and KDE applications do and Chrome, Firefox and the terminals do not.

Status items are glyphs and short readouts, not coloured chips. Colour appears
only past a limit -- CPU and memory at 90%, the battery at 10% -- and it is the
one red the calendar marks Sunday with. Everything else is the foreground.

The workspaces are the ten the current one falls in, so the row is the same
width whatever is open. Scrolling it walks them; the indicator slides and
stretches, faster ahead than behind.

Every dimension derives from one number, `Theme.scale`, which is derived from
how large a logical pixel physically is on the screen the bar is drawn on --
the millimetres the panel reports over the logical pixels across it, so the
compositor's scale is already inside the answer and must not be applied again.
Sizing from the logical resolution alone got a 1.5x laptop backwards, and so
did multiplying that density by `devicePixelRatio`, which Qt rounds up to the
next integer. Set `BAR_SCALE` to override it.

The centre chip is the one thing measured against the groups rather than the
screen: it stays centred on the screen, but a 1920 panel does not leave a fifth
of its width free between status items drawn at laptop scale, so the chip is
capped by the room they are not using and drops its meter, then its title,
before it will overlap them.

### What hovering opens

The chip in the centre opens the player: art, title, a draggable position bar,
and the transport. The clock opens the month.

Both are anchored popups rather than layer surfaces. A layer surface is placed
after every other surface's exclusive zone whatever its exclusion mode, so
nothing can be drawn over the bar; the chip is part of the bar's own window and
only the cards float. `services/Media.qml` holds the hover state, because
neither surface can see the other's pointer.

Cover art is loaded from local files and from a short list of cover-art hosts
over TLS, and from nowhere else. `mpris:artUrl` is chosen by the player, and
for a browser that means by the page, so fetching it as given would make any
open tab a beacon running out of the shell.

The bar is also the notification server. Toasts stack under its right edge and
everything is kept behind `SUPER + N`. A toast dwells five seconds, twenty at
critical urgency, and the thin bar along its bottom edge is that dwell running
out. Drag one right to dismiss it; click it to run its default action.

Critical toasts leave on their own too. The convention that urgency 2 waits to
be acknowledged assumes a server with nowhere else to put the notification, and
this one has the history panel.

Two things are worth knowing before editing it.

Nerd Font glyphs are written as code points rather than literal characters.
The Material Design ranges live in the astral plane and are easy to corrupt
when a file is copied or re-encoded, and a corrupted one renders as tofu.

quickshell reports fractions, not percentages. `percentage`, `signalStrength`
and `battery` all arrive as 0.0 to 1.0 despite their names, so every one of
them is multiplied by 100 at the point of use. Reading one raw pins a full
battery at 1%.

## Mirrors and seeds

Two ways in, and which one a file gets is not a style choice.

A **mirror** is for what is written here: the Hyprland configuration, the
quickshell tree, the scripts, the two commands in `bin/`. Every run copies the
repository over the installed path and deletes anything under it the repository
no longer has.

These were links once, because a link makes an edit live without running
anything. What a link also does is make the installed path resolve back into the
working tree: the old monitor script walked up from its own location and read
the repository's preset file rather than the installed one, and a directory
replaced under a watcher is a crash rather than a reload.

**Nothing edited here runs until `./install.sh` is run again**, and a unit
already running keeps the old code until it is restarted. A fix that was
committed, pushed and never installed cost a login once. `./install.sh --check`
names every path that is behind and exits 1.

The installer parse-checks the Hyprland configuration first, through
`hypr/scripts/verify-config.sh`, and refuses to install one that does not load:
the mirrors reload the running compositor, and a module that throws while
loading takes the session to emergency mode. A machine without Hyprland yet
gets a warning and an unchecked copy, which is how it is first run.

A **seed** is for everything a program owns. fcitx5, KDE and GTK save by writing
a temp file beside the target and rename()-ing it over, and rename() replaces a
symlink rather than following it: the first change made in one of their settings
windows turns the link into a real file, and this repository quietly stops being
what the machine reads. `p10k configure` is worse, writing through the link and
editing the repository without saying so.

Seeded files are copied once and left alone afterwards. The installer says what
it did, and refuses to overwrite one that has diverged.

    seeded ~/.config/fcitx5/config
    left ~/.config/kdeglobals alone: it exists and differs
      copy it back into <repo> to keep the change

To keep a change made through a program's own interface, copy the file back into
this repository. To push one out, delete the installed file and run the
installer again.

## Install

```sh
./install.sh
```

Mirrored paths are overwritten on every run, and anything under them the
repository no longer has is deleted. Seeded paths are left alone once they
exist, and are not backed up either. The only file kept with a timestamp is
`/etc/fonts/local.conf`.

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
bar --restart        # pick up a QML change
bar --log            # follow quickshell's output

systemctl --user stop app-hyprland.slice   # close what the bar opened, not the bar

BAR_PREVIEW=bottom bar --once   # preview, reserves no space
BAR_VIZ_DEMO=1     bar --once   # visualiser without audio
```

Preview mode anchors the bar to an edge without claiming an exclusive zone, so
it can sit alongside another shell while being worked on. `--once` runs
quickshell in the foreground outside its unit; two copies of one config cannot
run at the same time, so stop the unit first or point `BAR_CONFIG_DIR` at a
copy.

`bar --restart` no longer closes what the launcher and the pills opened: those
run in `app-hyprland.slice` through `quickshell/bar/scripts/app-scope.sh`. They
still end with the session, because the slice is `PartOf` its target.
