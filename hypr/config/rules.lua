-- Window and layer rules.

-- Client maximize requests are ignored, as in upstream's default config. Since
-- 0.49 kitty remembers whether its last closed window was maximized and asks
-- for that state on every start, so one maximized terminal made every new one
-- cover the workspace. SUPER+D still works: only the client's request is dropped.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Dialogs and pickers float.
hl.window_rule({ match = { class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland)$" }, float = true })
hl.window_rule({ match = { class = "^(org.fcitx.)" }, float = true })
hl.window_rule({ match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol)$" }, float = true })
hl.window_rule({ match = { class = "^(swappy)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File|Save File|Save As|Open Folder)" }, float = true })

hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, float = true, pin = true })

-- A pinned window keeps its border when unfocused, in the palette's cream/grey.
hl.window_rule({ match = { pin = true }, border_color = "rgba(ecf0c1ff) rgba(686f9aff)" })

-- Quickshell without layer-shell support opens an empty-class toplevel over
-- the bar that steals focus on hover; refuse it focus.
hl.window_rule({ match = { class = "^$", title = "^quickshell$" }, no_focus = true })

hl.layer_rule({ match = { namespace = "^(quickshell:launcher|quickshell:powermenu)$" }, blur = true })

-- The bar is opaque; blurring it only costs a pass.
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, blur = false })

-- Blur covers the layer's rectangle, not the rounded card, so corners showed
-- light squares.
hl.layer_rule({ match = { namespace = "^(quickshell:osd)$" }, blur = false })

-- The key strip is recreated on the other screen whenever the typing moves
-- there; a popin on each move flashed the caps already up.
hl.layer_rule({ match = { namespace = "^(quickshell:keys)$" }, no_anim = true })

-- Hyprland draws the layers of a level by descending order, so the lowest
-- order is drawn last, on top (0.56.2, Renderer.cpp arrangeLayersForMonitor).

-- The screensaver's black: a 1x1 transparent layer whose dim_around fills
-- its output with #000000 (decoration.dim_around = 1.0, general.lua). Below
-- zero so it covers every other overlay, toasts included. No animation:
-- waking is the black going at once. Never above_lock: the lock screen must
-- still draw over it, since a screensaver is not a lock.
hl.layer_rule({ match = { namespace = "^(quickshell:screensaver)$" }, dim_around = true, no_anim = true, order = -10 })

-- The Identify badges go over every other layer of their level (the
-- Displays card, the screensaver's black), so a numbered screen can always
-- be read.
hl.layer_rule({ match = { namespace = "^(quickshell:displays-identify)$" }, order = -20 })

-- The capture overlays (slurp's namespace is "selection") appear and vanish
-- at once. With the popin they came up 100 ms late, and Hyprland releases
-- every held button when an overlay that takes the keyboard maps, so a drag
-- begun before that was lost.
hl.layer_rule({ match = { namespace = "^(selection|hyprpicker)$" }, no_anim = true })

-- Idle inhibit only for fullscreen media, not a fullscreen terminal.
hl.window_rule({ match = { class = "^(mpv|vlc)$" }, idle_inhibit = "fullscreen" })
