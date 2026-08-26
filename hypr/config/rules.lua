-- Window and layer rules.

-- Dialogs and pickers belong in the middle, not tiled into a corner.
hl.window_rule({ match = { class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland)$" }, float = true })
hl.window_rule({ match = { class = "^(org.fcitx.)" }, float = true })
hl.window_rule({ match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol)$" }, float = true })
hl.window_rule({ match = { class = "^(swappy)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File|Save File|Save As|Open Folder)" }, float = true })

-- Picture in picture should stay visible and out of the tiling.
hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, float = true, pin = true })

-- A pinned window keeps the accent border so it is obvious which one is
-- following you between workspaces.
hl.window_rule({ match = { pin = true }, border_color = "rgba(5ccc96ff) rgba(00000000)" })

-- The shell draws itself on a layer surface and has no business owning a
-- toplevel. One does appear if a build without layer-shell support ever
-- starts against this config: an empty-class XWayland window the width of the
-- screen that takes focus the moment the pointer crosses the bar. Refusing it
-- focus keeps the window underneath in charge while that is being sorted out.
hl.window_rule({ match = { class = "^$", title = "^quickshell$" }, no_focus = true })

-- Screen sharing selectors must never be captured by the share they are
-- selecting for.
hl.layer_rule({ match = { namespace = "^(quickshell:launcher|quickshell:powermenu)$" }, blur = true })
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, blur = false })

-- No blur on the readout. Blur is applied to the layer's rectangle, not to
-- the rounded card drawn inside it, so each corner showed a lighter square
-- poking out from behind the radius. The two overlays above cover the whole
-- screen and have no corners to give themselves away.
hl.layer_rule({ match = { namespace = "^(quickshell:osd|quickshell:tooltip|quickshell:menu)$" }, blur = false })

-- No idle inhibit from a fullscreen terminal; only from actual media.
hl.window_rule({ match = { class = "^(mpv|vlc)$" }, idle_inhibit = "fullscreen" })
