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

-- Idle inhibit only for fullscreen media, not a fullscreen terminal.
hl.window_rule({ match = { class = "^(mpv|vlc)$" }, idle_inhibit = "fullscreen" })
