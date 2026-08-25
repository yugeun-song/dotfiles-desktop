-- See https://wiki.hyprland.org/Configuring/Binds/
--!
--##! User
hl.bind("CTRL + SUPER + Slash",
        hl.dsp.exec_cmd("xdg-open $HOME/.config/illogical-impulse/config.json"),
        {description = "Edit shell config"})

hl.bind("CTRL + SUPER + ALT + Slash",
        hl.dsp.exec_cmd("xdg-open $HOME/.config/hypr/custom/keybinds.lua"),
        {description = "Edit extra keybinds"})

-- Add stuff here.
-- Use --! to add an extra column on the cheatsheet.
-- Use --##! to add a section in that column.
-- Add a comment after a bind to add a description, like above.

--##! Vim navigation
do
    local hjkl = { "H", "J", "K", "L" }
    local dirs = { "l", "d", "u", "r" }
    for i = 1, 4 do
        hl.bind("SUPER + " .. hjkl[i],
            hl.dsp.focus({ direction = dirs[i] }),
            { description = "Window: Focus " .. dirs[i] .. " (vim)" })
        hl.bind("SUPER + SHIFT + " .. hjkl[i],
            hl.dsp.window.move({ direction = dirs[i] }),
            { description = "Window: Move " .. dirs[i] .. " (vim)" })
    end
end

hl.bind("CTRL + SUPER + H", hl.dsp.focus({ workspace = "r-1" }),
    { description = "Workspace: Focus left (vim)" })
hl.bind("CTRL + SUPER + L", hl.dsp.focus({ workspace = "r+1" }),
    { description = "Workspace: Focus right (vim)" })
hl.bind("CTRL + SUPER + K", hl.dsp.focus({ workspace = "r-5" }),
    { description = "Workspace: Scroll -5 (vim)" })
hl.bind("CTRL + SUPER + J", hl.dsp.focus({ workspace = "r+5" }),
    { description = "Workspace: Scroll +5 (vim)" })

hl.bind("CTRL + SUPER + SHIFT + H", hl.dsp.window.move({ workspace = "r-1" }),
    { description = "Workspace: Send window left (vim)" })
hl.bind("CTRL + SUPER + SHIFT + L", hl.dsp.window.move({ workspace = "r+1" }),
    { description = "Workspace: Send window right (vim)" })

--##! Lid
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms off eDP-1"),
    { locked = true, description = "Lid: internal panel off (no suspend)" })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms on eDP-1"),
    { locked = true, description = "Lid: internal panel on" })

--##! Workspace scroll (reversed from upstream)
-- Upstream binds scroll up to the next workspace. Reversed here so that
-- scrolling up goes to the previous workspace, matching the status bar.
--
-- The unbind calls are not optional. hl.bind on a key that already has a
-- binding adds a second one, and Hyprland then fires both: upstream's +1 and
-- the -1 below cancel out and scrolling appears to do nothing.
hl.unbind("SUPER + mouse_up")
hl.unbind("SUPER + mouse_down")
hl.unbind("CTRL + SUPER + mouse_up")
hl.unbind("CTRL + SUPER + mouse_down")

hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "-1" }),
    { description = "Workspace: Focus previous (scroll up)" })
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "+1" }),
    { description = "Workspace: Focus next (scroll down)" })
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "r-1" }),
    { description = "Workspace: Focus previous in list (scroll up)" })
hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "r+1" }),
    { description = "Workspace: Focus next in list (scroll down)" })
