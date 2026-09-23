-- Autostart. Every long-running program is a systemd user unit wanted by
-- hyprland-session.target; scripts/session-start.sh starts that target with
-- the compositor's environment. Spawn nothing else here: this file re-runs on
-- every reload, while hyprland.start fires once per compositor.
-- Output goes to the journal: journalctl --user -t session-start

local start = "systemd-cat -t session-start " .. CONFIG .. "/scripts/session-start.sh"

hl.on("hyprland.start", function()
    hl.exec_cmd(start)
end)

-- Recovery from safe mode: after a crash start-hyprland loads a generated
-- config, and "Load config" in its dialog fires config.reloaded but not
-- hyprland.start. Start the session unless the target is already up for this
-- compositor (the marker names the instance session-start.sh started it for).
-- Skipped with no outputs, i.e. the first load of a normal launch.
-- `test`, not `[`: Hyprland reads a leading `[` in exec as a window-rule block
-- and strips it, leaving the shell a line starting with `&&`.
hl.on("config.reloaded", function()
    if #hl.get_monitors() == 0 then
        return
    end
    hl.exec_cmd('test "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprland-session.started-for" 2>/dev/null)" = "$HYPRLAND_INSTANCE_SIGNATURE"'
        .. ' && systemctl --user is-active --quiet hyprland-session.target || ' .. start)
end)

-- Also stopped by scripts/session-watch.sh when the lock file goes; this
-- covers the exit before the watch notices. Guarded by the marker because
-- every Hyprland loading this config fires it, nested or second-VT included.
-- --no-block: do not wait on the bar while shutting down.
hl.on("hyprland.shutdown", function()
    hl.exec_cmd('test "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprland-session.started-for" 2>/dev/null)" = "$HYPRLAND_INSTANCE_SIGNATURE"'
        .. ' && systemctl --user --no-block stop hyprland-session.target')
end)
