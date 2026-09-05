-- Autostart.
--
-- One call in, one call out. Every long-running program in the session is a
-- systemd user unit wanted by hyprland-session.target (see systemd/user/), and
-- scripts/session-start.sh is what starts that target with the compositor's
-- environment in place. Nothing that spawns a process belongs here: Hyprland
-- re-runs this file on every `hyprctl reload`, and hyprland.start fires once
-- per compositor, which is the only reason this file can call the script
-- without checking anything first.
--
-- systemd-cat, because a process the compositor spawns has its output sent
-- to /dev/null; through it the script's messages land in the journal:
--   journalctl --user -t session-start

local start = "systemd-cat -t session-start " .. CONFIG .. "/scripts/session-start.sh"

hl.on("hyprland.start", function()
    hl.exec_cmd(start)
end)

-- The other way this configuration can come up: after a crash. start-hyprland
-- relaunches a compositor that did not exit cleanly in safe mode, which loads
-- a generated recovery configuration rather than this one, so the handler
-- above never runs. Choosing "Load config" in the safe-mode dialog reloads
-- this configuration, and hyprland.start does not fire a second time.
-- config.reloaded does, on every reload, so that case is caught here.
--
-- Whether anything needs doing is decided in one shell: the target is down,
-- or it is up but was started for another compositor -- the crashed one, whose
-- lock may still be there holding the watch -- which session-start.sh records
-- in its marker file. Otherwise the shell exits and nothing else runs, so an
-- ordinary reload costs one process. Skipped while the compositor has no
-- outputs yet, which is the first load of a normal launch, where the handler
-- above is about to do the same thing at the right moment.
--
-- `test`, not `[`: a command handed to exec that begins with `[` is read by
-- Hyprland as a block of window rules up to the `]`, and what is left --
-- here, a line beginning with `&&` -- is what the shell got. That shell
-- failed silently on every reload until a login came up with nothing started.
hl.on("config.reloaded", function()
    if #hl.get_monitors() == 0 then
        return
    end
    hl.exec_cmd('test "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprland-session.started-for" 2>/dev/null)" = "$HYPRLAND_INSTANCE_SIGNATURE"'
        .. ' && systemctl --user is-active --quiet hyprland-session.target || ' .. start)
end)

-- The target is also taken down by scripts/session-watch.sh when the
-- compositor's lock file goes. Asking here as well costs one spawn and covers
-- the exit before the watch has noticed. --no-block, because a stop job that
-- includes the bar is not something to wait on while shutting down.
--
-- Only the compositor the target was started for may stop it. This handler
-- fires in EVERY Hyprland that loads this config, a nested one or a second-VT
-- login included, and an unguarded stop there would tear the running session's
-- services down when that other compositor exits. The marker names the session
-- compositor; `test`, not `[`, because a command handed to exec that starts
-- with `[` is read as a window-rule block and stripped.
hl.on("hyprland.shutdown", function()
    hl.exec_cmd('test "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprland-session.started-for" 2>/dev/null)" = "$HYPRLAND_INSTANCE_SIGNATURE"'
        .. ' && systemctl --user --no-block stop hyprland-session.target')
end)
