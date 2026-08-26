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
local wswalk    = scripts .. "/workspace-walk.sh"
local dirwalk   = scripts .. "/focus-walk.sh"

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
hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd(scripts .. "/session-autostart.sh"),
    { description = "Restart anything in the session that died" })

--##! Window focus
local vim_dir   = { H = "l", J = "d", K = "u", L = "r" }
local arrow_dir = { Left = "l", Down = "d", Up = "u", Right = "r" }

for key, dir in pairs(vim_dir) do
    hl.bind("SUPER + " .. key, hl.dsp.exec_cmd(dirwalk .. " focus " .. dir),
        { description = "Focus " .. dir })
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.exec_cmd(dirwalk .. " move " .. dir),
        { description = "Move window " .. dir })
end
for key, dir in pairs(arrow_dir) do
    hl.bind("SUPER + " .. key, hl.dsp.exec_cmd(dirwalk .. " focus " .. dir),
        { description = "Focus " .. dir })
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.exec_cmd(dirwalk .. " move " .. dir),
        { description = "Move window " .. dir })
end
hl.bind("SUPER + BracketLeft", hl.dsp.exec_cmd(dirwalk .. " focus l"))
hl.bind("SUPER + BracketRight", hl.dsp.exec_cmd(dirwalk .. " focus r"))

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
--
-- Through a script rather than Hyprland's own r+n and r-n, because those wrap:
-- left from the first workspace lands on the last one. That is a jump across
-- the whole set at the exact moment the intent was to find out there is
-- nothing further left. scripts/workspace-walk.sh clamps instead.
local walk = {
    { keys = { "H", "Left",  "BracketLeft" },  step = "-1" },
    { keys = { "L", "Right", "BracketRight" }, step = "+1" },
    { keys = { "K", "Up" },                    step = "-5" },
    { keys = { "J", "Down" },                  step = "+5" },
}
for _, w in ipairs(walk) do
    for _, k in ipairs(w.keys) do
        hl.bind("CTRL + SUPER + " .. k, hl.dsp.exec_cmd(wswalk .. " focus " .. w.step),
            { description = "Workspace " .. w.step })
        hl.bind("CTRL + SUPER + SHIFT + " .. k, hl.dsp.exec_cmd(wswalk .. " move " .. w.step),
            { description = "Send window to workspace " .. w.step })
    end
end

hl.bind("SUPER + Page_Up", hl.dsp.exec_cmd(wswalk .. " focus -1"))
hl.bind("SUPER + Page_Down", hl.dsp.exec_cmd(wswalk .. " focus +1"))
hl.bind("SUPER + SHIFT + Page_Up", hl.dsp.exec_cmd(wswalk .. " move -1"))
hl.bind("SUPER + SHIFT + Page_Down", hl.dsp.exec_cmd(wswalk .. " move +1"))

-- Scroll up goes to the previous workspace. The opposite of the upstream
-- default, and the status bar's own scroll handler matches it; a bar that
-- scrolls the other way from the compositor is worse than neither.
-- Through the same script the keyboard walk uses. "-1" and "+1" are a walk
-- that wraps, so one more notch at the first workspace crosses the whole set
-- and lands on the last, which happens at exactly the moment someone is
-- checking whether they have reached the end. The Ctrl variants below keep
-- "r-1" and "r+1" because cycling the open workspaces is what they are for.
hl.bind("SUPER + mouse_up", hl.dsp.exec_cmd(wswalk .. " focus -1"),
    { description = "Previous workspace" })
hl.bind("SUPER + mouse_down", hl.dsp.exec_cmd(wswalk .. " focus +1"),
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
-- Brightness is bound twice. The first hands the key to the shell, which
-- knows the difference between a backlight device and a monitor on DDC and
-- draws the readout. The second runs only when the shell is not there, so a
-- crashed bar costs the readout and not the key.
-- The process is named qs, not quickshell: bin/bar prefers the qs binary and
-- that is what ends up in comm. Matching only "quickshell" made this test
-- always fail, so the fallback fired alongside the shell handler and every
-- press moved two steps, all the way to a dark panel.
local shell_alive = "pgrep -x qs >/dev/null 2>&1 || pgrep -x quickshell >/dev/null 2>&1"

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
-- keeps working. Through a script because the right action depends on whether
-- an external is connected, and because `hyprctl dispatch dpms off eDP-1` is a
-- Lua parse error under this configuration: it answers ok and does nothing.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd(scripts .. "/lid.sh close"),
    { locked = true, description = "Lid: internal panel off" })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd(scripts .. "/lid.sh open"),
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
