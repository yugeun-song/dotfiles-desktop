-- Zoom's windows. Zoom lays out its own windows (the meeting, its panels, the
-- share toolbar and its notices), so they all float, kept as Zoom draws them
-- where the compositor's look only gets in the way (the user, 2026-11-06: make
-- it Hyprland-friendly). Here and not with Zoom's install, the user's call the
-- same day: these rules answer this desktop's settings (no focus on
-- activation, blur and borders, the bar's height) and hold however Zoom is
-- installed; without Zoom they match nothing.
--
-- Not fixed from here: a docked panel in a meeting. The meeting window grows
-- itself to hold Participants or Chat, Hyprland (0.57.1, and main on
-- 2026-11-05) takes no size from a floating Wayland window, and the panel stays
-- cut off until Hyprland sends one (a manual resize, Super+D or Super+F). Tiled
-- is worse: Zoom ignores a tiled size and draws its old one, the rest grey.

local ZOOM = "^(Zoom|zoom)$"

hl.window_rule({
    name = "zoom-float",
    match = { class = ZOOM },
    float = true,
})

-- Zoom brings its panels forward (Participants, Chat, the meeting) by asking
-- to be activated, and Hyprland refuses that to a window that is not focused
-- (misc.focus_on_activate is off): a click on the toolbar's Participants or
-- Chat left the panel behind the other windows, as if nothing happened, until
-- a fullscreen toggle stacked the windows again (the user, 2026-11-06).
hl.window_rule({
    name = "zoom-activate",
    match = { class = ZOOM },
    focus_on_activate = true,
})

-- Zoom's helpers carry internal lowercase titles (as_toolbar for the share
-- toolbar, zoom_linux_float_video_window for the share preview, menu window,
-- zoom) or none, unlike its windows (Zoom Workplace, Meeting chat,
-- Participants): drawn as Zoom draws them, no border, no blur behind their
-- clear parts, no shadow, rounding or animation, and taking no focus as they
-- appear. The share toolbar's window is far larger than its bar, to hold its
-- menus, and its framed, frosted rest read as an empty box (2026-11-06).
-- Nor by asking: under the rule above, the share preview's request pulled
-- the screen back to Zoom's workspace from wherever the user had gone, and
-- a shared screen shows the meeting that view (measured in a nested
-- Hyprland, 2026-11-06). This rule comes later, so it wins for these.
hl.window_rule({
    name = "zoom-helpers",
    match = { class = ZOOM, title = "^[a-z0-9_ ]*$" },
    decorate = false,
    no_blur = true,
    no_shadow = true,
    rounding = 0,
    no_anim = true,
    no_dim = true,
    no_initial_focus = true,
    focus_on_activate = false,
})

-- The share toolbar at the top of its screen, just under the bar, as Zoom
-- places it elsewhere. Not pinned: pinned at first (2026-11-06), it followed
-- the user to every workspace and sat over their windows there, which the
-- user did not want ("why does it keep following the workspaces?").
hl.window_rule({
    name = "zoom-share-toolbar",
    match = { class = ZOOM, title = "^as_toolbar$" },
    move = "((monitor_w-window_w)/2) 44",
})

-- The panels a meeting opens beside itself while it shares, docked on the
-- right of their screen: participants above, chat below.
hl.window_rule({
    name = "zoom-participants",
    match = { class = ZOOM, title = "^Participants.*$" },
    size = "440 (monitor_h*0.40)",
    move = "(monitor_w-window_w-16) 52",
})

hl.window_rule({
    name = "zoom-chat",
    match = { class = ZOOM, title = "^Meeting chat$" },
    size = "440 (monitor_h*0.46)",
    move = "(monitor_w-window_w-16) (monitor_h-window_h-16)",
})

-- The home window keeps the size it was left at; its title names the account
-- ("Zoom Workplace - Free account").
hl.window_rule({
    name = "zoom-main-size",
    match = { class = ZOOM, title = "^Zoom Workplace.*$" },
    persistent_size = true,
})

hl.window_rule({
    name = "zoom-meeting-idle",
    match = { class = ZOOM, title = "^(Zoom Meeting|Zoom Webinar|Meeting)$" },
    idle_inhibit = "always",
})
