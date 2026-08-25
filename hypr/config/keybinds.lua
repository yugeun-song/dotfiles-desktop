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
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:powerMenu"),
    { description = "Session dialog" })
hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd(scripts .. "/session-autostart.sh"),
    { description = "Restart anything in the session that died" })

--##! Window focus
local vim_dir   = { H = "l", J = "d", K = "u", L = "r" }
local arrow_dir = { Left = "l", Down = "d", Up = "u", Right = "r" }

for key, dir in pairs(vim_dir) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dir }),
        { description = "Focus " .. dir })
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }),
        { description = "Move window " .. dir })
end
for key, dir in pairs(arrow_dir) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dir }),
        { description = "Focus " .. dir })
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }),
        { description = "Move window " .. dir })
end
hl.bind("SUPER + BracketLeft", hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + BracketRight", hl.dsp.focus({ direction = "r" }))

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
local numpad_code = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }

for i = 1, 10 do
    local n = i % 10
    hl.bind("SUPER + " .. n, hl.dsp.focus({ workspace = i }),
        { description = "Workspace " .. i })
    hl.bind("SUPER + ALT + " .. n, hl.dsp.window.move({ workspace = i, follow = false }),
        { description = "Send window to workspace " .. i })

    hl.bind("SUPER + code:" .. numpad_code[i], hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + ALT + code:" .. numpad_code[i], hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Walking the workspaces that actually exist rather than by number. The
-- vertical pair jumps five at a time, which is what makes this usable once
-- there are more workspaces than fingers.
local walk = {
    { keys = { "H", "Left",  "BracketLeft" },  focus = "r-1", send = "r-1" },
    { keys = { "L", "Right", "BracketRight" }, focus = "r+1", send = "r+1" },
    { keys = { "K", "Up" },                    focus = "r-5", send = "r-5" },
    { keys = { "J", "Down" },                  focus = "r+5", send = "r+5" },
}
for _, w in ipairs(walk) do
    for _, k in ipairs(w.keys) do
        hl.bind("CTRL + SUPER + " .. k, hl.dsp.focus({ workspace = w.focus }),
            { description = "Workspace " .. w.focus })
        hl.bind("CTRL + SUPER + SHIFT + " .. k, hl.dsp.window.move({ workspace = w.send, follow = true }),
            { description = "Send window to workspace " .. w.send })
    end
end

hl.bind("SUPER + Page_Up", hl.dsp.focus({ workspace = "r-1" }))
hl.bind("SUPER + Page_Down", hl.dsp.focus({ workspace = "r+1" }))
hl.bind("SUPER + SHIFT + Page_Up", hl.dsp.window.move({ workspace = "r-1" }))
hl.bind("SUPER + SHIFT + Page_Down", hl.dsp.window.move({ workspace = "r+1" }))

-- Scroll up goes to the previous workspace. The opposite of the upstream
-- default, and the status bar's own scroll handler matches it; a bar that
-- scrolls the other way from the compositor is worse than neither.
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "-1" }),
    { description = "Previous workspace" })
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "+1" }),
    { description = "Next workspace" })
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "r-1" }),
    { description = "Previous open workspace" })
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "r+1" }),
    { description = "Next open workspace" })
hl.bind("SUPER + SHIFT + mouse_up", hl.dsp.window.move({ workspace = "r-1" }))
hl.bind("SUPER + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "r+1" }))

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
hl.bind("SUPER + code:82", function() zoom_by(-0.3) end, { repeating = true })
hl.bind("SUPER + code:86", function() zoom_by(0.3) end, { repeating = true })

--##! Capture
hl.bind("Print", hl.dsp.exec_cmd(capture .. " screen"),
    { description = "Capture: focused monitor" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(capture .. " region"),
    { description = "Capture: drag a region" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(capture .. " window"),
    { description = "Capture: focused window" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(capture .. " region-edit"),
    { description = "Capture: region, then annotate" })
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
-- Brightness is bound twice. The first hands the key to the shell, which
-- knows the difference between a backlight device and a monitor on DDC and
-- draws the readout. The second runs only when the shell is not there, so a
-- crashed bar costs the readout and not the key.
local shell_alive = "pgrep -x quickshell >/dev/null 2>&1"

hl.bind("XF86MonBrightnessUp", hl.dsp.global("quickshell:brightnessUp"),
    { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessUp",
    hl.dsp.exec_cmd(shell_alive .. " || brightnessctl --class backlight -q s 5%+"),
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("quickshell:brightnessDown"),
    { locked = true, repeating = true, description = "Brightness down" })
hl.bind("XF86MonBrightnessDown",
    hl.dsp.exec_cmd(shell_alive .. " || brightnessctl --class backlight -q s 5%-"),
    { locked = true, repeating = true })

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
hl.bind("CTRL + SHIFT + ALT + SUPER + Delete", hl.dsp.exec_cmd("systemctl poweroff"),
    { description = "Shut down" })

--##! Lid
-- The panel goes dark, the session does not go to sleep.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms off eDP-1"),
    { locked = true, description = "Lid: internal panel off" })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms on eDP-1"),
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
