-- Autostart. Every long-running program is a user unit wanted by
-- hyprland-session.target, which scripts/session-start.sh starts with the
-- compositor's environment. Spawn nothing else here: this file re-runs on
-- every reload, hyprland.start fires once per compositor.
-- Log: journalctl --user -t session-start

local start = "systemd-cat -t session-start " .. CONFIG .. "/scripts/session-start.sh"

hl.on("hyprland.start", function()
    hl.exec_cmd(start)
end)

-- Recovery from safe mode: after a crash start-hyprland loads a generated
-- config, and its "Load config" fires config.reloaded but not hyprland.start.
-- Start the session unless the target is already up for this compositor (the
-- marker names the instance it was started for). Skipped with no outputs,
-- i.e. the first load of a normal launch. `test`, not `[`: Hyprland takes a
-- leading `[` in exec for a window-rule block and strips it.
hl.on("config.reloaded", function()
    if #hl.get_monitors() == 0 then
        return
    end
    hl.exec_cmd('test "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprland-session.started-for" 2>/dev/null)" = "$HYPRLAND_INSTANCE_SIGNATURE"'
        .. ' && systemctl --user is-active --quiet hyprland-session.target || ' .. start)
end)

-- session-watch.sh also stops the target when the lock file goes; this
-- covers an exit before it notices. Guarded by the marker since every
-- Hyprland loading this config fires it, nested or second-VT ones included.
-- --no-block: shutting down must not wait on the bar.
hl.on("hyprland.shutdown", function()
    hl.exec_cmd('test "$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hyprland-session.started-for" 2>/dev/null)" = "$HYPRLAND_INSTANCE_SIGNATURE"'
        .. ' && systemctl --user --no-block stop hyprland-session.target')
end)
