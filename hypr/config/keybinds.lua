-- Key bindings. Conventions: vim keys and arrows are bound together; apps
-- launch through launch.sh with a candidate list, so a key works with any
-- installed alternative and reports when none is; nothing binds to a program
-- outside this repository's package list.
-- Hyprland fires EVERY binding on a key, not the first match: never bind one
-- key twice.

local scripts   = HOME .. "/.config/hypr/scripts"
local terminal  = scripts .. "/terminal.sh"
local capture   = scripts .. "/capture.sh"
local launch    = scripts .. "/launch.sh"
local clipboard = scripts .. "/clipboard.sh"
local shellkey  = scripts .. "/shell-global.sh"

local app = {
    browser  = launch .. " 'google-chrome-stable' 'firefox' 'chromium' 'brave' 'librewolf'",
    files    = launch .. " 'dolphin' 'nautilus' 'nemo' 'thunar' '" .. terminal .. " -e yazi'",
    code     = launch .. " 'code' 'codium' 'cursor' 'zed' 'kate' '" .. terminal .. " -e nvim'",
    editor   = launch .. " 'kate' 'gnome-text-editor' '" .. terminal .. " -e nvim'",
    office   = launch .. " 'onlyoffice-desktopeditors' 'libreoffice' 'wps'",
    mixer    = launch .. " 'pavucontrol-qt' 'pavucontrol'",
    settings = launch .. " 'systemsettings' 'gnome-control-center'",
    tasks    = launch .. " 'plasma-systemmonitor' 'gnome-system-monitor' '" .. terminal .. " -e btop'",
}

--##! Apps
hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(app.files), { description = "File manager" })
hl.bind("SUPER + W", hl.dsp.exec_cmd(app.browser), { description = "Browser" })
hl.bind("SUPER + C", hl.dsp.exec_cmd(app.code), { description = "Code editor" })
hl.bind("SUPER + X", hl.dsp.exec_cmd(app.editor), { description = "Text editor" })
hl.bind("SUPER + I", hl.dsp.exec_cmd(app.settings), { description = "Settings" })
hl.bind("CTRL + SUPER + V", hl.dsp.exec_cmd(app.mixer), { description = "Volume mixer" })
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd(app.tasks), { description = "Task manager" })
hl.bind("CTRL + SUPER + SHIFT + ALT + W", hl.dsp.exec_cmd(app.office), { description = "Office" })

--##! Shell surfaces
-- Lone Super tap. Must be a release bind: on press the SUPER mask is not set
-- yet. Fires only for a short tap without another key. Through a script, not
-- hl.dsp.global, which would deliver a release the press-edge toggle ignores.
for _, key in ipairs({ "SUPER_L", "SUPER_R" }) do
    hl.bind("SUPER + " .. key, hl.dsp.exec_cmd(shellkey .. " launcher"),
        { release = true, description = "Application launcher" })
end
-- Needs logind HandlePowerKey=ignore. The 4 s hardware override still works.
hl.bind("XF86PowerOff", hl.dsp.global("quickshell:powerMenu"),
    { description = "Session menu" })
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:powerMenu"),
    { description = "Session dialog" })
hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd("systemd-cat -t session-start " .. scripts .. "/session-start.sh"),
    { description = "Restart anything in the session that died" })

--##! Window focus
-- movefocus wraps at the edge; this vetoes the step when nothing lies that
-- way and otherwise lets Hyprland pick the target, which stays on this
-- workspace (window_direction_monitor_fallback is off in general.lua). A Lua
-- callback, not a hyprctl script, so rapid presses cannot race on a stale
-- answer.
-- Unknown filter keys are dropped silently, a bad dispatcher argument returns
-- nil (logged, but the bind still registers) and dispatching nil is a no-op,
-- so every failure falls back to the plain step plus one notification:
-- wrapping beats a dead key.

-- Any window whose centre is strictly beyond, diagonals included.
local beyond = {
    left  = function(w, cx, cy) return w.at.x + w.size.x / 2 < cx end,
    right = function(w, cx, cy) return w.at.x + w.size.x / 2 > cx end,
    up    = function(w, cx, cy) return w.at.y + w.size.y / 2 < cy end,
    down  = function(w, cx, cy) return w.at.y + w.size.y / 2 > cy end,
}

-- Separate so the caller's pcall covers exactly the compositor queries.
local function anything_beyond(dir)
    local active = hl.get_active_window()
    if active == nil then
        return false
    end

    -- A nil filter value drops the key and widens the query to all workspaces.
    local ws = active.workspace
    if ws == nil then
        return false
    end

    local cx = active.at.x + active.size.x / 2
    local cy = active.at.y + active.size.y / 2
    local past = beyond[dir]

    -- hidden is not a filter field (it would be dropped), so test it here.
    local seen_active = false
    for _, w in ipairs(hl.get_windows({ workspace = ws, mapped = true })) do
        if w.address == active.address then
            seen_active = true
        end
        if not w.hidden and past(w, cx, cy) then
            return true
        end
    end

    -- Missing focused window means the filter did not resolve; raise so the
    -- caller falls back instead of every direction key going dead.
    if active.mapped and not seen_active then
        error("the window query did not return the focused window", 0)
    end
    return false
end

-- Once per failure kind, not per press; reset on reload.
local walk_warned = {}

local function walk_warn(tag, text)
    if walk_warned[tag] then
        return
    end
    walk_warned[tag] = true
    pcall(function()
        hl.notification.create({ text = "hypr: " .. text, timeout = 15000 })
    end)
end

local function focus_walk(mode, dir)
    -- Built at load: a renamed dispatcher fails --verify-config, but a
    -- rejected argument only returns nil, so check for that here.
    local step
    if mode == "focus" then
        step = hl.dsp.focus({ direction = dir })
    else
        step = hl.dsp.window.move({ direction = dir })
    end
    if step == nil then
        return function()
            walk_warn("build", "no " .. mode .. " dispatcher for direction "
                .. dir .. ": the direction keys cannot step")
        end
    end

    return function()
        local ok, found = pcall(anything_beyond, dir)
        if ok and not found then
            return
        end
        -- A failed check falls through to the plain step.
        if not ok then
            walk_warn("check", "direction keys lost their edge check and wrap again: "
                .. tostring(found))
        end
        local sent, err = pcall(hl.dispatch, step)
        if not sent then
            walk_warn("step", "direction keys cannot step: " .. tostring(err))
        end
    end
end

-- Full words: the one-letter aliases are accepted but undocumented.
local vim_dir   = { H = "left", J = "down", K = "up", L = "right" }
local arrow_dir = { Left = "left", Down = "down", Up = "up", Right = "right" }

for key, dir in pairs(vim_dir) do
    hl.bind("SUPER + " .. key, focus_walk("focus", dir),
        { description = "Focus " .. dir })
    hl.bind("SUPER + SHIFT + " .. key, focus_walk("move", dir),
        { description = "Move window " .. dir })
end
for key, dir in pairs(arrow_dir) do
    hl.bind("SUPER + " .. key, focus_walk("focus", dir),
        { description = "Focus " .. dir })
    hl.bind("SUPER + SHIFT + " .. key, focus_walk("move", dir),
        { description = "Move window " .. dir })
end
hl.bind("SUPER + BracketLeft", focus_walk("focus", "left"))
hl.bind("SUPER + BracketRight", focus_walk("focus", "right"))

--##! Window state
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind("SUPER + SHIFT + ALT + Q", hl.dsp.exec_cmd("hyprctl kill"),
    { description = "Pick a window to kill" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    { description = "Fullscreen" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "Maximize" })
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }),
    { description = "Tell the window it is fullscreen without making it so" })
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind("SUPER + P", hl.dsp.window.pin(), { description = "Pin window" })
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true, description = "Split ratio" })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
-- mouse = true is ignored on 0.56 (the drag dispatcher handles the button
-- itself) but is what upstream's example passes, so it stays.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag window" })
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

--##! Workspaces
-- Number row only, one binding per key. A second binding by keycode would
-- switch twice (and bounce back if workspace_back_and_forth is ever enabled).
for i = 1, 10 do
    local n = i % 10
    hl.bind("SUPER + " .. n, hl.dsp.focus({ workspace = i }),
        { description = "Workspace " .. i })
    hl.bind("SUPER + ALT + " .. n, hl.dsp.window.move({ workspace = i, follow = false }),
        { description = "Send window to workspace " .. i })

end

-- Keypad digits are not bound: keysyms differ with NumLock (KP_End vs KP_1),
-- so both sets would be needed and could double-fire.

-- Clamped walk by number (vertical keys step 5). Not r+n/r-n, which wrap from
-- the first workspace to the last. A callback rather than a hyprctl script, so
-- a wheel flick cannot race two steps into one. By number, not over existing
-- workspaces: Hyprland creates an empty one on arrival. The ceiling is
-- config/monitors.lua's, which binds every id up to it to the external; the
-- fallback covers a monitors module that failed to load.
local MIN_WORKSPACE = 1
local MAX_WORKSPACE = (MONITORS and MONITORS.LAST_WORKSPACE) or 100

local function workspace_walk(mode, step)
    return function()
        local active = hl.get_active_workspace()
        if active == nil then
            return
        end

        -- Special workspaces have negative ids; no step from there.
        local id = active.id
        if id < MIN_WORKSPACE then
            return
        end

        local target = id + step
        if target < MIN_WORKSPACE then
            target = MIN_WORKSPACE
        elseif target > MAX_WORKSPACE then
            target = MAX_WORKSPACE
        end
        if target == id then
            return
        end

        if mode == "focus" then
            hl.dispatch(hl.dsp.focus({ workspace = target }))
        else
            hl.dispatch(hl.dsp.window.move({ workspace = target }))
        end
    end
end

-- The cheatsheet shows these descriptions, so keep the "+" sign.
local function step_label(step)
    if step > 0 then
        return "+" .. step
    end
    return tostring(step)
end

local walk = {
    { keys = { "H", "Left",  "BracketLeft" },  step = -1 },
    { keys = { "L", "Right", "BracketRight" }, step = 1 },
    { keys = { "K", "Up" },                    step = -5 },
    { keys = { "J", "Down" },                  step = 5 },
}
for _, w in ipairs(walk) do
    for _, k in ipairs(w.keys) do
        hl.bind("CTRL + SUPER + " .. k, workspace_walk("focus", w.step),
            { description = "Workspace " .. step_label(w.step) })
        hl.bind("CTRL + SUPER + SHIFT + " .. k, workspace_walk("move", w.step),
            { description = "Send window to workspace " .. step_label(w.step) })
    end
end

hl.bind("SUPER + Page_Up", workspace_walk("focus", -1))
hl.bind("SUPER + Page_Down", workspace_walk("focus", 1))
hl.bind("SUPER + SHIFT + Page_Up", workspace_walk("move", -1))
hl.bind("SUPER + SHIFT + Page_Down", workspace_walk("move", 1))

-- Scroll up = previous workspace, opposite to upstream; the bar's scroll
-- handler must match.
hl.bind("SUPER + mouse_up", workspace_walk("focus", -1),
    { description = "Previous workspace" })
hl.bind("SUPER + mouse_down", workspace_walk("focus", 1),
    { description = "Next workspace" })
-- Ctrl cycles the open workspaces on this monitor with m-1/m+1; wrapping is
-- intended here, the one way to reach the far end. Not r-1/r+1: those walk
-- ids, empty ones included, and never wrap.
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "m-1" }),
    { description = "Previous open workspace" })
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "m+1" }),
    { description = "Next open workspace" })
-- Carrying a window is a clamped step, not a cycle.
hl.bind("SUPER + SHIFT + mouse_up", workspace_walk("move", -1))
hl.bind("SUPER + SHIFT + mouse_down", workspace_walk("move", 1))

--##! Scratchpad
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("special"), { description = "Scratchpad" })
hl.bind("CTRL + SUPER + S", hl.dsp.workspace.toggle_special("special"))
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special("special"))
hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special", follow = false }),
    { description = "Send window to scratchpad" })

--##! Zoom
-- Clamped: the compositor accepts a zoom you cannot read your way out of.
local function zoom_by(step)
    local current = hl.get_config("cursor.zoom_factor")
    local next_value = current + step
    if next_value > 3.0 then
        next_value = 3.0
    elseif next_value < 1.0 then
        next_value = 1.0
    end
    hl.config({ cursor = { zoom_factor = next_value } })
end

hl.bind("SUPER + Minus", function() zoom_by(-0.3) end, { repeating = true, description = "Zoom out" })
hl.bind("SUPER + Equal", function() zoom_by(0.3) end, { repeating = true, description = "Zoom in" })
hl.bind("SUPER + KP_Subtract", function() zoom_by(-0.3) end, { repeating = true })
hl.bind("SUPER + KP_Add", function() zoom_by(0.3) end, { repeating = true })

--##! Help
-- The cheatsheet reads live bindings; only ones with a description appear.
hl.bind("SUPER + slash", hl.dsp.global("quickshell:cheatsheet"),
    { description = "Show every key binding" })
hl.bind("SUPER + SHIFT + slash", hl.dsp.global("quickshell:cheatsheet"))

hl.bind("SUPER + N", hl.dsp.global("quickshell:notifications"),
    { description = "Show the notification history" })

hl.bind("SUPER + Y", hl.dsp.global("quickshell:keyOverlay"),
    { description = "Show the keys being pressed" })

--##! Displays
-- The output panel in the bar: presets (laptop only, external only, extend,
-- mirror), per-output mode, scale and rotation, written to the override file
-- config/monitors.lua reads. XF86Display is the laptop's own display key;
-- Super+O because Super+P is taken by pin.
hl.bind("XF86Display", hl.dsp.global("quickshell:displays"),
    { description = "Display settings" })
hl.bind("SUPER + O", hl.dsp.global("quickshell:displays"),
    { description = "Display settings" })

--##! Capture
hl.bind("Print", hl.dsp.exec_cmd(capture .. " screen"),
    { description = "Capture: focused monitor" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(capture .. " window"),
    { description = "Capture: focused window" })
-- Ctrl+Shift+S too, the common habit. Cost: apps never see it (save-as).
hl.bind("CTRL + SHIFT + S", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
-- The only capture that opens the annotator.
hl.bind("SUPER + SHIFT + ALT + S", hl.dsp.exec_cmd(capture .. " region-edit"),
    { description = "Capture a region and annotate it" })
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd(capture .. " color"),
    { description = "Capture: pick a colour" })

--##! Clipboard
hl.bind("SUPER + V", hl.dsp.exec_cmd(clipboard),
    { description = "Clipboard history" })

--##! Media
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, description = "Play/pause" })
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("playerctl next"),
    { locked = true, description = "Next track" })
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("playerctl previous"),
    { locked = true, description = "Previous track" })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, description = "Mute" })
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, description = "Mute microphone" })

--##! Hardware keys
-- locked: work on the lock screen; repeating: holding keeps stepping.
-- One binding per key with the branch inside; a second binding double-steps.

-- Shell presence from its layer surfaces, not pgrep (a fork on the input
-- thread). Prefix match: the bar uses quickshell's default namespace.
local SHELL_NAMESPACE = "quickshell"

local function shell_is_up()
    for _, l in ipairs(hl.get_layers()) do
        if l.mapped and l.namespace:sub(1, #SHELL_NAMESPACE) == SHELL_NAMESPACE then
            return true
        end
    end
    return false
end

-- Without the shell, fall back to brightnessctl only on the internal panel;
-- DDC is too slow for key repeat, so externals get nothing. Must match
-- isInternal() in quickshell/bar/services/Brightness.qml.
local INTERNAL_PREFIX = { "eDP", "LVDS", "DSI" }

local function on_internal_panel()
    local m    = hl.get_active_monitor()
    local name = m and m.name or ""
    if name == "" then
        return true
    end
    for _, prefix in ipairs(INTERNAL_PREFIX) do
        if name == prefix or name:sub(1, #prefix + 1) == prefix .. "-" then
            return true
        end
    end
    return false
end

-- Queries in pcall so a failing one cannot kill a lock-screen key; unknown
-- falls to brightnessctl. hl.dsp.* returns nil on a bad argument. No floor
-- here: brightnessctl has its own.
local function brightness(shortcut, fallback)
    local to_shell = hl.dsp.global(shortcut)
    local to_panel = hl.dsp.exec_cmd(fallback)
    return function()
        local asked, up = pcall(shell_is_up)
        if to_shell and asked and up then
            hl.dispatch(to_shell)
            return
        end
        local known, internal = pcall(on_internal_panel)
        if to_panel and (not known or internal) then
            hl.dispatch(to_panel)
        end
    end
end

hl.bind("XF86MonBrightnessUp",
    brightness("quickshell:brightnessUp", "brightnessctl --class backlight -q s 5%+"),
    { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown",
    brightness("quickshell:brightnessDown", "brightnessctl --class backlight -q s 5%-"),
    { locked = true, repeating = true, description = "Brightness down" })

-- Straight to wpctl: works without the shell, which shows the OSD from
-- PipeWire anyway.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%+"),
    { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),
    { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, description = "Mute" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, description = "Mute microphone" })
hl.bind("ALT + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true })

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

--##! Session
-- Not SUPER+L, which is focus right.
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock" })
-- Escape from a crashed locker (the session stays locked by design). Safe:
-- Hyprland refuses while a lock client is alive. locked = true, since
-- ordinary binds are not delivered then.
hl.bind("CTRL + ALT + SHIFT + U", hl.dsp.exec_cmd("hyprctl eval 'hl.clear_crashed_lockscreen()'"),
    { locked = true, description = "Clear a crashed lock screen" })
-- Through scripts/session-power.sh, which ends the compositor before the
-- shutdown transaction starts (a direct poweroff with an external output lit
-- hung this machine after userspace had finished; a sign-out first did not).
-- The script moves itself into a transient unit outside the session target,
-- since a child of this bind sits in the session scope and would not outlive
-- the compositor it waits for.
hl.bind("CTRL + SHIFT + ALT + SUPER + Delete", hl.dsp.exec_cmd(scripts .. "/session-power.sh poweroff"),
    { description = "Shut down" })

--##! Lid
-- Panel off only; no suspend. Requires logind to ignore the lid
-- (/etc/systemd/logind.conf.d, see README).
hl.bind("switch:on:Lid Switch", function() MONITORS.lid_close() end,
    { locked = true, description = "Lid: internal panel off" })
hl.bind("switch:off:Lid Switch", function() MONITORS.lid_open() end,
    { locked = true, description = "Lid: internal panel on" })

--##! Virtual machines
-- Passes Super through to a VM guest. The toggle is submap_universal, so it
-- also works inside the submap as the way back out.
hl.define_submap("virtual-machine", function()
    hl.bind("SUPER + ALT + F1", function()
        if hl.get_current_submap() == "virtual-machine" then
            hl.dispatch(hl.dsp.submap("reset"))
        else
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end
    end, { submap_universal = true })
end)
