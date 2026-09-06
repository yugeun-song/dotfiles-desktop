-- Key bindings.
--
-- Three conventions run through this file.
--
-- Vim keys and arrow keys are always bound together. Muscle memory does not
-- transfer between machines, and a binding that only works one way is a
-- binding you have to think about.
--
-- Anything that opens a program goes through a script with a list of
-- candidates rather than naming one binary, so the key still works on a
-- machine that has the second choice installed and reports itself on a
-- machine that has none of them.
--
-- Nothing here talks to a program that is not in this repository's package
-- list. Bindings that existed only to drive another shell's overlays are
-- gone rather than left pointing at something that will never answer.

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
-- Super on its own. This has to be a release binding: pressing Super is what
-- makes the SUPER modifier active, so on press the mask is still empty and a
-- press binding carrying SUPER cannot match its own key. Measured here, the
-- release fires for a lone tap and stays silent both for Super held with
-- another key and for a long press, which is exactly the wanted meaning.
--
-- It goes through a script rather than hl.dsp.global because a release
-- binding delivers the shortcut as a release, and a toggle that acts on the
-- press edge would never see it.
for _, key in ipairs({ "SUPER_L", "SUPER_R" }) do
    hl.bind("SUPER + " .. key, hl.dsp.exec_cmd(shellkey .. " launcher"),
        { release = true, description = "Application launcher" })
end
-- The power button, now that logind is told to ignore it. The short press is
-- a userspace input event and this is what reads it; the four second
-- hardware override is below any of this and stays the way out of a wedged
-- machine.
hl.bind("XF86PowerOff", hl.dsp.global("quickshell:powerMenu"),
    { description = "Session menu" })
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:powerMenu"),
    { description = "Session dialog" })
hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd("systemd-cat -t session-start " .. scripts .. "/session-start.sh"),
    { description = "Restart anything in the session that died" })

--##! Window focus
-- Hyprland's own movefocus wraps: from the leftmost window, left lands on the
-- rightmost. So ask first whether anything is that way, and do nothing if not.
-- Which window to land on is still Hyprland's to decide.
--
-- In here rather than scripts/focus-walk.sh, for the reason the workspace walk
-- below is: the script asked hyprctl and then told hyprctl, and a second press
-- inside that gap stepped from an answer one window old, which is the wrap
-- this exists to prevent. A callback cannot be split that way.
--
-- This API never raises. A filter key it does not know is dropped, a selector
-- it cannot resolve gives an empty list, a rejected dispatcher argument gives
-- nil, and dispatching nil is silent -- each one a key that quietly stops
-- working. Hence the checks below, all of which end in the compositor's own
-- step plus one notification. Wrapping is bad; a dead key is worse.

-- A veto, not a target: anything further left counts, diagonals included.
-- Strict, so a window centred exactly on the focused one is not left of it.
local beyond = {
    l = function(w, cx, cy) return w.at.x + w.size.x / 2 < cx end,
    r = function(w, cx, cy) return w.at.x + w.size.x / 2 > cx end,
    u = function(w, cx, cy) return w.at.y + w.size.y / 2 < cy end,
    d = function(w, cx, cy) return w.at.y + w.size.y / 2 > cy end,
}

-- Separate from the binding so the pcall there wraps the compositor calls and
-- the arithmetic on what they return, and nothing else.
local function anything_beyond(dir)
    local active = hl.get_active_window()
    -- No focused window is not a failure. There is simply nowhere to step from.
    if active == nil then
        return false
    end

    -- The object, not its id: a filter key set to nil is a filter key that is
    -- not there, and the query then widens to every workspace instead of
    -- failing. Caught here so it cannot read as somewhere to go.
    local ws = active.workspace
    if ws == nil then
        return false
    end

    local cx = active.at.x + active.size.x / 2
    local cy = active.at.y + active.size.y / 2
    local past = beyond[dir]

    -- hidden is tested here rather than asked for in the filter: it is a window
    -- field and not a filter field, so the key would be dropped and the query
    -- would answer as though nothing had been asked.
    local seen_active = false
    for _, w in ipairs(hl.get_windows({ workspace = ws, mapped = true })) do
        if w.address == active.address then
            seen_active = true
        end
        if not w.hidden and past(w, cx, cy) then
            return true
        end
    end

    -- A list without the focused window is not a list of this workspace -- the
    -- shape an unresolvable filter comes back in. Read as an answer it means
    -- eighteen dead keys, so it is raised onto the fallback below instead.
    if active.mapped and not seen_active then
        error("the window query did not return the focused window", 0)
    end
    return false
end

-- Once per kind of failure, not once a press: the same break is reached again
-- on the next keystroke. A local, so a reload re-arms it.
local walk_warned = {}

local function walk_warn(tag, text)
    if walk_warned[tag] then
        return
    end
    walk_warned[tag] = true
    pcall(function()
        hl.notification.create({ text = "hypr: " .. text, duration = 15000 })
    end)
end

local function focus_walk(mode, dir)
    -- Built once at load, so a renamed dispatcher is a call on nil that
    -- --verify-config catches. A rejected argument is not: it just returns nil,
    -- and hl.dispatch takes nil silently, so that one is caught here.
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
        -- The check is the fragile half, so one that throws falls through to
        -- the step: a wrong destination beats a key that stopped working.
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

local vim_dir   = { H = "l", J = "d", K = "u", L = "r" }
local arrow_dir = { Left = "l", Down = "d", Up = "u", Right = "r" }

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
hl.bind("SUPER + BracketLeft", focus_walk("focus", "l"))
hl.bind("SUPER + BracketRight", focus_walk("focus", "r"))

--##! Window state
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind("SUPER + SHIFT + ALT + Q", hl.dsp.exec_cmd("hyprctl kill"),
    { description = "Pick a window to kill" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    { description = "Fullscreen" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "Maximize" })
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3, action = "toggle" }),
    { description = "Tell the window it is fullscreen without making it so" })
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind("SUPER + P", hl.dsp.window.pin(), { description = "Pin window" })
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true, description = "Split ratio" })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag window" })
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

--##! Workspaces
-- The number row and the keypad, and only one binding each.
--
-- Binding the number row a second time by keycode looks harmless and is not.
-- Hyprland fires every binding on a key, so the workspace was switched twice,
-- and with workspace_back_and_forth on the second switch returns to where it
-- started. The key then appears to do nothing at all.
for i = 1, 10 do
    local n = i % 10
    hl.bind("SUPER + " .. n, hl.dsp.focus({ workspace = i }),
        { description = "Workspace " .. i })
    hl.bind("SUPER + ALT + " .. n, hl.dsp.window.move({ workspace = i, follow = false }),
        { description = "Send window to workspace " .. i })

end

-- The keypad is not bound, and the twenty lines that used to try are gone.
--
-- They read `hl.bind("SUPER + code:" .. numpad_code[i], ...)`, which is the
-- hyprlang spelling. The Lua bind takes a string and does not parse `code:` out
-- of it, so all twenty registered with an empty key AND an empty keycode and
-- could never fire: `hyprctl binds` showed 22 entries with neither field set.
-- Nothing reported it. Passing a table instead is worse -- `bind: bad argument
-- 1: expected string, got table` on every line, and the whole loop is dropped.
--
-- Binding them by keysym is possible but not equivalent: the keypad sends
-- KP_End/KP_Down/... with NumLock off and KP_1/KP_2/... with it on, so it would
-- take both sets and would then fire twice on any layout where they coincide,
-- which is the double-fire this section's comment above warns about.

-- Walking the workspaces by number. The vertical pair jumps five at a time,
-- which is what makes this usable once there are more workspaces than fingers.
--
-- Not Hyprland's own r+n and r-n, because those wrap: left from the first
-- workspace lands on the last one. That is a jump across the whole set at the
-- exact moment the intent was to find out there is nothing further left.
--
-- And not through a script either, which is what this used to be and is no
-- longer in the tree. It asked hyprctl and then told hyprctl, and a wheel flick
-- put a second invocation inside that gap: both read the same workspace, both
-- aimed at the same target, and the pair moved one step. Measured, two "+1"
-- walks from 2 landed on 3. A callback cannot be split that way.
--
-- By number rather than over the workspaces that exist, because an empty one to
-- the right is somewhere to go: Hyprland creates it on arrival.
local MIN_WORKSPACE = 1
local MAX_WORKSPACE = 100

local function workspace_walk(mode, step)
    return function()
        local active = hl.get_active_workspace()
        if active == nil then
            return
        end

        -- A special workspace has a negative id. Stepping from one would land
        -- on whatever number happens to be next, which is not a step from
        -- anywhere the user is.
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

-- The sheet reads these descriptions back out of the compositor, and a step
-- reads as a direction there, so the sign is kept even where Lua would drop it.
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

-- Scroll up goes to the previous workspace. The opposite of the upstream
-- default, and the status bar's own scroll handler matches it; a bar that
-- scrolls the other way from the compositor is worse than neither.
--
-- The same clamped walk the keyboard uses, and for the same reason: a wheel is
-- where the overlapping invocations came from in the first place, because a
-- flick delivers notches faster than a round trip to hyprctl completes.
hl.bind("SUPER + mouse_up", workspace_walk("focus", -1),
    { description = "Previous workspace" })
hl.bind("SUPER + mouse_down", workspace_walk("focus", 1),
    { description = "Next workspace" })
-- The Ctrl pair keeps "r-1" and "r+1". Cycling the open workspaces is what
-- they are for, so wrapping is the behaviour rather than the bug, and it is
-- the deliberate way back to the far end now that nothing else wraps.
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "r-1" }),
    { description = "Previous open workspace" })
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "r+1" }),
    { description = "Next open workspace" })
-- Carrying a window, on the other hand, is a step and not a cycle: dragging a
-- window off the first workspace should stop there rather than fling it to the
-- last one.
hl.bind("SUPER + SHIFT + mouse_up", workspace_walk("move", -1))
hl.bind("SUPER + SHIFT + mouse_down", workspace_walk("move", 1))

--##! Scratchpad
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("special"), { description = "Scratchpad" })
hl.bind("CTRL + SUPER + S", hl.dsp.workspace.toggle_special("special"))
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special("special"))
hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special", follow = false }),
    { description = "Send window to scratchpad" })

--##! Zoom
-- Clamped here rather than left to the compositor, which will happily zoom
-- to a value you cannot read your way back out of.
local function zoom_by(step)
    local current = hl.get_config("cursor:zoom_factor")
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
-- The sheet reads the bindings back out of the compositor rather than keeping
-- its own copy, so this list is whatever is actually bound at the moment it is
-- opened. A binding without a description does not appear; that is what the
-- description field is for.
hl.bind("SUPER + slash", hl.dsp.global("quickshell:cheatsheet"),
    { description = "Show every key binding" })
hl.bind("SUPER + SHIFT + slash", hl.dsp.global("quickshell:cheatsheet"))

hl.bind("SUPER + N", hl.dsp.global("quickshell:notifications"),
    { description = "Show the notification history" })

hl.bind("SUPER + Y", hl.dsp.global("quickshell:keyOverlay"),
    { description = "Show the keys being pressed" })

--##! Capture
hl.bind("Print", hl.dsp.exec_cmd(capture .. " screen"),
    { description = "Capture: focused monitor" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(capture .. " window"),
    { description = "Capture: focused window" })
-- Ctrl + Shift + S as well as Super + Shift + S. It is the shortcut most
-- people arrive with, and the cost is real: an application that uses it for
-- save-as never sees it again, because the compositor takes the key before
-- any window does.
hl.bind("CTRL + SHIFT + S", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
-- Editing is the exception, not the rule. Nearly every capture here is taken
-- and used as it is, and opening an annotator on each one is a window to close
-- before getting back to whatever the shot was for. This key is the one that
-- opens it, for the times a shot does need marking up.
hl.bind("SUPER + SHIFT + ALT + S", hl.dsp.exec_cmd(capture .. " region-edit"),
    { description = "Capture a region and annotate it" })
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd(capture .. " color"),
    { description = "Capture: pick a colour" })

--##! Clipboard
-- SUPER + V, which is where it was before, rather than somewhere tidier.
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
-- locked = true so they still work on the lock screen, repeating so holding
-- a key keeps stepping instead of moving one notch and stopping.
--
-- One binding per key, with the branch inside it. Hyprland runs every binding
-- on a key rather than stopping at the first, so a shell binding plus a
-- guarded fallback moved two steps whenever the guard was wrong -- and it was,
-- because it matched "quickshell" against a process named qs. One binding
-- cannot double-step whatever the guard decides. Do not add a second.

-- A layer surface, not a process: the compositor already knows, where pgrep
-- cost a fork on the thread that dispatches libinput. Prefix, because the bar
-- surface takes quickshell's default name and a default is not ours to depend
-- on; any shell surface answers the question, which is whether it is loaded.
local SHELL_NAMESPACE = "quickshell"

local function shell_is_up()
    for _, l in ipairs(hl.get_layers()) do
        if l.mapped and l.namespace:sub(1, #SHELL_NAMESPACE) == SHELL_NAMESPACE then
            return true
        end
    end
    return false
end

-- brightnessctl writes the internal panel, which monitors.lua switches off with
-- the lid. Without this a bar that died closed would dim a panel nobody can see
-- and leave it near zero. DDC is too slow to stand in at twenty-five presses a
-- second, so on an external the honest fallback is none.
--
-- Brightness.qml's isInternal() copied, not reinvented: the two have to agree
-- or the key means one thing with the bar up and another with it down.
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

-- Both questions inside pcall: a compositor that cannot answer one must not
-- cost a key that also has to work on the lock screen. Unanswerable falls to
-- brightnessctl, which is what this did before any of it. The dispatchers are
-- checked for nil too, since hl.dsp.* reports a bad argument that way.
--
-- No floor named here. brightnessctl stops at its own, and the one percent
-- Brightness.qml uses is of a maximum that differs per machine.
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

-- Volume goes straight to wpctl rather than through the shell. It works with
-- no shell running, and the shell watches Pipewire anyway, so the readout
-- appears for a change made here, by a mixer, or by an application.
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
-- Not SUPER + L: that is "focus right" above, and losing a directional key to
-- a lock screen is a poor trade.
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock" })
-- The way out of a lock screen that died. Under ext-session-lock a crashed
-- locker leaves the session locked on purpose, which is the right default and
-- also a way to be shut out of a running machine with every window still in
-- it. This is safe to bind: Hyprland refuses it while a lock client is alive
-- ("session is locked with a client, refusing"), so it can only clear a lock
-- that has nothing behind it. locked = true, because the moment it is needed
-- is the moment ordinary bindings are not being delivered.
hl.bind("CTRL + ALT + SHIFT + U", hl.dsp.exec_cmd("hyprctl eval 'hl.clear_crashed_lockscreen()'"),
    { locked = true, description = "Clear a crashed lock screen" })
hl.bind("CTRL + SHIFT + ALT + SUPER + Delete", hl.dsp.exec_cmd("systemctl poweroff"),
    { description = "Shut down" })

--##! Lid
-- The panel goes dark, the session does not go to sleep, and the keyboard
-- keeps working. logind is told to ignore the switch in
-- /etc/systemd/logind.conf.d, so this binding is the only thing that answers
-- it. The functions live in config/monitors.lua because the right action
-- depends on which outputs are enabled, and that module is what knows.
hl.bind("switch:on:Lid Switch", function() MONITORS.lid_close() end,
    { locked = true, description = "Lid: internal panel off" })
hl.bind("switch:off:Lid Switch", function() MONITORS.lid_open() end,
    { locked = true, description = "Lid: internal panel on" })

--##! Virtual machines
-- A guest that wants the Super key needs the compositor to stop taking it.
-- The escape hatch is bound inside the submap as well, or there would be no
-- way back out.
hl.define_submap("virtual-machine", function()
    hl.bind("SUPER + ALT + F1", function()
        if hl.get_current_submap() == "virtual-machine" then
            hl.dispatch(hl.dsp.submap("reset"))
        else
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end
    end, { submap_universal = true })
end)
