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

-- A pinned window is the one that follows you between workspaces, and it says
-- so by keeping its border when it loses focus rather than by being a colour.
-- It was green, the last accent left on a desktop where the bar, the lock
-- screen and the window borders are all one cream and one grey.
hl.window_rule({ match = { pin = true }, border_color = "rgba(ecf0c1ff) rgba(686f9aff)" })

-- The shell draws itself on a layer surface and has no business owning a
-- toplevel. One does appear if a build without layer-shell support ever
-- starts against this config: an empty-class XWayland window the width of the
-- screen that takes focus the moment the pointer crosses the bar. Refusing it
-- focus keeps the window underneath in charge while that is being sorted out.
hl.window_rule({ match = { class = "^$", title = "^quickshell$" }, no_focus = true })

-- Screen sharing selectors must never be captured by the share they are
-- selecting for.
hl.layer_rule({ match = { namespace = "^(quickshell:launcher|quickshell:powermenu)$" }, blur = true })

-- The menu bar is opaque, so there is nothing behind it to blur and blurring
-- it would only cost a pass.
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, blur = false })

-- No blur on the readouts. Blur is applied to the layer's rectangle, not to
-- the rounded card inside it, so each corner showed a lighter square poking
-- out from behind the radius. The island is here for a second reason: it is
-- drawn pure black so it reads as a notch, and blur takes that away.
hl.layer_rule({ match = { namespace = "^(quickshell:osd|quickshell:tooltip|quickshell:menu|quickshell:island)$" }, blur = false })

-- No idle inhibit from a fullscreen terminal; only from actual media.
hl.window_rule({ match = { class = "^(mpv|vlc)$" }, idle_inhibit = "fullscreen" })
