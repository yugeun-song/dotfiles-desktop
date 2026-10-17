# dotfiles-desktop

A Wayland desktop on Hyprland with a status bar written in QML for
quickshell. The tracked files are one laptop's settings, kept as the preset.
Within the platform below, whatever another machine differs in (outputs,
GPUs, cameras, missing optional tools) is detected and adapted to, or
reported; outside it, the installer refuses rather than half-apply.

## Premise

| Part | Expected |
|---|---|
| Distribution | Arch Linux, the one tested. Recognised by `/etc/os-release` ID, then ID_LIKE: the Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE and Gentoo families, whose package managers the installer's hints name; Void and Alpine are recognised but boot without systemd. Library paths (Qt plugins, VA-API drivers, polkit agents, bash loadables) are looked for in each family's layout |
| Init | systemd, with the user manager running the session's units |
| Compositor | Hyprland 0.56 or later, which reads `hyprland.lua` (hypridle, hyprlock and hyprpaper still read hyprlang `.conf` files) |
| Shell | quickshell (`qs`) for the bar and every panel |
| Terminal | kitty, configured by [dotfiles-terminal](https://github.com/yugeun-song/dotfiles-terminal) |
| KDE pieces | Breeze (GTK theme, icons), plasma-integration (Qt platform theme), the SpaceduckDark colour scheme; hyprpolkitagent or polkit-kde-agent |
| Also expected | fcitx5 (Hangul), PipeWire, Inter, Pretendard and CaskaydiaCove Nerd Font |

`./install.sh` stops before writing anything when the distribution is not
one of these, the system was not booted with systemd, Hyprland is missing or
older than 0.56, quickshell is missing, this checkout's Hyprland config does
not load, or XDG_CONFIG_HOME, XDG_DATA_HOME or XDG_STATE_HOME differs
between the shell and the systemd user manager. Each reason comes with its
fix. Everything else is optional: its doctor line names what is absent, and
each script degrades on its own.

## Layout

```
hypr/hyprland.lua    entry point; loads hypr/config/, then ~/.config/hypr/local.lua
                     if present (untracked, never installed)
hypr/config/         env, general, monitors (output policy), rules, keybinds, execs
hypr/scripts/        what keys and units call: capture, lock, session, power,
                     camera, monitor overrides, the nested self-test
hypr/*.conf          hypridle, hyprlock, hyprpaper (seeded)
hypr/monitor_settings.lua   the output preset; monitor_settings.local.lua beside
                     it holds one machine's deviations (untracked)
quickshell/bar/      the bar and its panels
systemd/user/        the session target, one unit per long-running program
dbus/                fcitx5's D-Bus activation, pointed at its unit
bin/                 bar and unlock (to ~/.local/bin), recover-desktop (to ~/)
camera/              the camera switch, its polkit action and udev rule (root's)
keyfeed/             the key overlay's reader and its polkit action (root's)
fontconfig/          font chain (to /etc/fonts/local.conf)
gtk/ kde/ fcitx5/    seeded settings: GTK, Qt/KDE colours, Korean input
tuigreet/            the greeter's look (only when greetd runs tuigreet)
theme/               colour notes (DESIGN.md) and the cursor theme builder
tests/               tests/run.sh; --e2e and --vm add the slower suites
```

## Install

```sh
./install.sh           # install, or update after a pull
./install.sh --check   # what is behind or in conflict; writes nothing
./install.sh --force   # install, overwriting conflicts without asking
```

Exit status: 0 everything is in place; 1 stopped, or finished with steps left
undone (listed at the end, each with its command); 2 usage.

Each step prints as a tree, one `✓` per file written, and a step with
nothing to do as one dim line; colour only on a terminal, never under
`NO_COLOR`. An update writes only files that differ and reloads only their
owner: the bar when its tree changed, Hyprland when its config did, the user
manager when a unit did. The `Spaceduck-Sky` cursor theme is rebuilt only
when its scripts or the Oxygen_White theme it is drawn from changed, and
sudo is asked for only when one of root's files differs.

Files are copied, never linked: **nothing edited here runs until the
installer runs again**, and a running unit keeps its old code until it
restarts. A *mirror* (the Hyprland config and scripts, the quickshell tree,
`bin/`, the units, the D-Bus service, the Spotify flags, the output preset)
is overwritten on every run, file by file. A *seed* (fcitx5, GTK, KDE,
hypridle, hyprlock, hyprpaper) is copied once and then left to its program,
which rewrites it: a newer version from here replaces it only while the
installed copy is still one this repository wrote. One its program changed
stays and is listed by `--check`; copy a change back here to keep it, or
delete the installed file to take this one.

A target whose content this repository did not write (another program
changed it, or it was there first) is a **conflict**. The installer shows a
coloured diff with both sides' line numbers and asks: `y` overwrites, `n`
keeps it and stops there (what came before stays installed), `a` overwrites
this and every later conflict. Without a terminal the answer is `n`;
`--force` answers `a`. "Written by this repository" means: the same as the
source, the content recorded in `~/.local/state/dotfiles-desktop/installed`
by an earlier run, or any version committed in this checkout. Files the
repository dropped are removed only if it put them there; anything else in a
mirrored directory is left and pointed out.

Root's files (`/etc/fonts/local.conf`, `/etc/tuigreet/config.toml` under
tuigreet, the camera switch's three, the key reader's two) are shown before
sudo is asked for, since this checkout's content, which any program of the
user's could have changed, becomes root's: each file with what changes and
where its content comes from (`as on origin/main`, `committed, not on
origin/main`, `not committed`). Diffs show at once for content not as on the
upstream branch and for a copy this repository did not write (kept beside it
as `.bak-<time>`); `d` shows the rest. One answer covers them all: `y` asks
sudo and writes, `n` leaves them listed as undone. Without a terminal they
wait, unless `--force`. Where they are not so already, the installer
disables `kde-baloo`, masks the drkonqi coredump units (they crash-loop
without a display) and enables `hypridle`.

The shell, terminal, prompt and REPL helpers live in dotfiles-terminal. No
file is installed by both repositories.

## Outputs

`config/monitors.lua` decides which screens are on, inside the compositor:
with an external attached both are on, the lid turns the panel off, alone
the panel is the desktop, and the lid shut with no other display lit locks
the session (`lock_on_lid` in the preset). It follows hotplug and the lid,
re-applies on every reload, lights the panel when nothing is lit, and never
lights and darkens outputs in one commit (that once wedged the compositor).

`hypr/monitor_settings.lua` holds the preset (scales per display
description, `auto_scale`, `main`, `workspaces`, `keep_internal`,
`lock_on_lid`);
`monitor_settings.local.lua` overrides it per field on another machine. A
display the preset does not name gets its highest refresh rate and the scale
step that lands its logical width nearest 1920 (panel) or 2560 (external).
`hyprctl repl 'return MONITORS.describe()'` shows where every value came
from. Workspaces: `dynamic` (Hyprland's own), `panel-first` (the preset: 1 on
the panel, 2-100 on the main external) or `blocks` (ten per further
external).

`Super+O` opens the Displays panel: layout presets, the workspace scheme,
and per output power, mode, scale, rotation, side and screensaver. Apply
writes `~/.local/state/hypr/monitor-overrides` (one `selector TAB field TAB
value` line each) through `scripts/monitor-override.sh`, then a 30 s
countdown reverts unless Keep is pressed; the deadline survives a reload, a
crash or a power-off. The lid and power keys assume logind ignores them
(`HandleLidSwitch=ignore` and variants, `HandlePowerKey=ignore`), set outside
this repository.

## Session

Every long-running program (bar, fcitx5, hyprpaper, clipboard watchers,
polkit agent, hypridle) is a user unit under `hyprland-session.target`.
`scripts/session-start.sh` imports the compositor's environment and starts
it; `hyprland-session-watch.service` stops it when the compositor's lock file
goes. `HYPRLAND_NO_SD_TARGET` keeps Hyprland 0.57 from starting the target
before the import. `Ctrl+Super+R` starts whatever died. Units restart always
(SIGTERM counts as success), capped at five starts in two minutes.

The session menu (power key, `Ctrl+Alt+Delete`, the bar's power glyph) is the
bar's, drawn over the screensaver's black; with the bar down those keys
restart it and say so. `Ctrl+Shift+Alt+Super+Delete` powers off without it.
Power-off and restart go through `scripts/session-power.sh`, which ends the
compositor before the transaction: a direct `systemctl poweroff` with an
external lit hung this machine. From a text console, `~/recover-desktop`
repairs a desktop that runs but cannot be seen (`--status` only diagnoses),
and `unlock` clears a stuck
lock screen. On the lock screen itself, `Ctrl+Alt+Shift+U` starts a new
locker when hyprlock has crashed: the way out is the password, never an
unlock without one.

The clipboard history (`Super+V`, cliphist) lives in `$XDG_RUNTIME_DIR`, a
tmpfs gone at logout, and `cliphist-expire.timer` drops entries after half
an hour to an hour; entries a password manager marks secret are never
stored. The installer removes a history an older setup left in
`~/.cache/cliphist`.

    journalctl --user -u bar.service -f
    journalctl --user -t session-start

## The bar

```
left     distribution badge, the ten workspaces, the focused window's application
centre   what is playing
right    cameras off, caps lock, input method, alarm, network, bluetooth,
         cpu, memory, battery, notifications, weather, clock, session
```

Glyphs and short readouts; colour only past a limit (CPU and memory at 90%,
battery at 10%). Each screen has its own bar: what is playing, readouts and
the clock are shared; the workspace mark and window name are the screen's
own; popups open under the pointer; the key overlay follows the keyboard.
Summoned panels open on the focused monitor. Every size is `Theme.px()` of
one scale tuned on 2560x1440 and drawn scaled by `Theme.fit(screen)`, the
square root of the screen's logical area over that reference's, floored at
1; `monitors.lua` and `scripts/lock-fit.sh` apply the same factor to gaps,
borders and the lock screen.

The bar is the notification server (history `Super+N` for a day, a toast
dwells 5 s, critical 20 s; images are declined, nothing draws them).
`Super+/` lists every binding. Cover art loads only from
local files and `Theme.artHosts`. Weather refetches when a link comes up and
again when NetworkManager's check sees the internet answer, so a boot without
network shows it within seconds of connecting; a click fetches at once.

The bar writes no core file when it crashes and keeps no detailed log
(window titles, track titles); `systemctl --user set-environment
BAR_DETAILED_LOGS=1` and `bar --restart` bring the log back for chasing a
bug.

**Key overlay** (`Super+Y`): `keyfeed/keyfeed.py`, installed as root's
`/usr/local/libexec/keyfeed`, reads the keyboards. pkexec asks for an
administrator's password every time the bar starts it (`Super+Y`, a login
with the overlay on, a bar restart); it opens the keyboards as root, then
runs as nobody with the `input` group alone, so the user needs no group
that would let every program read the keyboards. The switch persists in
`~/.local/state/quickshell/bar/keyoverlay`. The reader holds no keyboard
open, so nothing typed is read or queued anywhere, while the session is
locked, while another console is in front, and while a password is being
typed: a polkit, pinentry, askpass, keyring or wallet window has the focus,
or the focused window's terminal reads with its echo off (sudo, su, ssh,
passwd, `read -s`; `scripts/echowatch.py` reads two terminal flags, never a
key). What it does read it zeroes once decoded. Keys go nowhere but the
overlay (no socket, no file, no log line, at most five chords for under a
second, each scrubbed as it leaves).

In Hangul mode a letter is drawn as the jamo Dubeolsik types for it (`R`
as ㄱ, `Shift+R` as ⇧ㄲ), and as the letter while Ctrl, Alt or Super is
held, since fcitx5 passes a shortcut on untouched. The bar asks fcitx5 at
each letter rather than trusting its last poll, which can be 0.3 s old, so
the first letter after a switch is drawn in the right script; the question
(a line to `scripts/inputmethod.py`) carries no key.

**Screensaver**: off unless a display gets a time in the Displays panel.
After that long with nothing done on the display it goes exact black
(`dim_around`, no modeset) while someone works elsewhere, and DPMS-off once
the seat is idle; it never locks or suspends. A window that inhibits idle, an
open Displays panel or a screen share holds it off. Times live in
`~/.local/state/quickshell/bar/screensaver`.

**Badge**: the mark of the distribution `/etc/os-release` names (its ID,
else the first ID_LIKE word with a mark, else Tux). A click opens Automatic
and every mark the icon font has, 40 with a current Nerd Font; the pick
persists in `~/.local/state/quickshell/bar/badge`. Lock and sign out are in
the session menu.

Editing the QML: Nerd Font glyphs are written as code points; quickshell's
`percentage`, `signalStrength` and `battery` run 0.0 to 1.0; a `pragma
Singleton` under `services/` must import QtQuick.

```sh
bar --restart        # pick up a QML change
bar --status         # running or not, the last log lines
bar --once           # foreground, outside the unit (stop the unit first)
systemctl --user stop app-hyprland.slice   # close what the bar opened
```

## Cameras

`Super+Alt+C`, or the laptop's camera key, turns every camera off, and again
on; a notification names each camera and how it went. The bar shows a glyph
only while cameras are off: red if the switch is off but a camera is on
anyway, amber if one stayed off after turning them on, nothing when there is
no camera at all. It reads `camera-switch status --json` on events only: the
key, udev's device events (`udevadm monitor`), the switch file, a bar start.
A reading taken while a switch is mid-action is not shown; failed reads keep
the last one and retry with backoff.

`camera/camera-switch.py` finds cameras from what the kernel publishes
(capture nodes udev classified, USB video-class interfaces), never from a
list of models; codecs, tuners, outputs and virtual devices are left alone.
Each camera goes off by the strongest means available and is checked in
sysfs afterwards:

```
platform switch  the laptop's firmware camera switch (ideapad, asus-wmi,
                 eeepc, msi-ec), tried first for every camera
usb-interface    the USB video interfaces are deauthorized; the rest of the
                 device (microphone, presence sensor) keeps working
usb-device       the whole USB device is deauthorized
unbind           the driver of a camera that is not on USB (an ISP) is unbound
module           a driver with no unbind has its module unloaded, if unused
```

A camera nothing reaches is reported as still on, never as off. The switch
persists in `/var/lib/camera-switch/off`; while it is off,
`/etc/udev/rules.d/70-camera-switch.rules` turns off any camera that appears
(plugged in, re-enumerated, at boot before its driver binds). The root-owned
copy in `/usr/local/bin` runs through pkexec with polkit actions that let
the active local session turn the cameras off without a password and on only
with an administrator's: a camera that is on belongs to every program of the
user's (udev's uaccess), so a switch they could undo silently would guard
nothing. Each missing piece of
that root step costs something the switch says (`camera-switch` lists it
under `setup`); without the root copy the keys use `~/.local/bin`'s and ask
for a password.

    camera-switch                status, no root needed; --json for programs
    camera-switch off|on|toggle  what the keys run
    journalctl -t camera-switch  every change and the means used

Not reached: a camera driven from user space through libusb, root, and at
boot a machine whose `/var` is a separate filesystem (udev reads the switch
file before it is mounted). To remove the switch, turn the cameras on and
delete the three root files.

## Checks

```sh
tests/run.sh           # shellcheck, Lua, Python, the Hyprland config, unit tests
tests/run.sh --e2e     # and the end-to-end suite (needs a running session)
tests/run.sh --vm      # and the camera switch on a real kernel
```

Nothing here touches the installed desktop. Unit tests run the bar's logic
offscreen in a copy with stand-ins (camera and weather included, on events
and timers), the installer against a temporary home, the camera switch
against a model of sysfs, and the key and override scripts against temporary
state. The e2e suite drives a copy of the bar in a nested headless Hyprland
with a virtual pointer and keyboard. `--vm` boots the running kernel under
virtme-ng with emulated USB cameras (`tests/vm/usb_camera.py`), vivid, vimc
and vim2m, and checks the switch against the real uvcvideo and udev.

## Credits

The palette combines [Spaceduck](https://github.com/pineapplegiant/spaceduck)
by pineapplegiant (background, foreground, greys, selection) and
[Tokyo Night](https://github.com/folke/tokyonight.nvim) by folke (the
accents). Only the colour values were taken.

The badge's marks are glyphs of [Font Logos](https://github.com/Lukas-W/font-logos)
(Unlicense) as Nerd Fonts ships them, drawn from the installed font by code
point; this repository holds no logo artwork. Each mark is its owner's
trademark and stands only for that distribution, as Font Logos asks; no
endorsement is implied.
