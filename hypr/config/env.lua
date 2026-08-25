-- Environment for the session.
--
-- These are set here rather than in a shell profile because they have to
-- reach every client the compositor spawns, including ones started from a
-- launcher that never sources a shell rc.

-- Toolkits need to be told to use Wayland; several still default to X11 and
-- then run through XWayland with worse input and scaling.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Qt applications otherwise draw their own title bars on top of the
-- compositor's decorations.
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Korean input. fcitx5 has to be named for each toolkit separately; a client
-- that misses this shows a keyboard that cannot type Hangul at all.
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Intel Lunar Lake uses the xe driver, not i915. VA-API lives in a different
-- package there and the wrong driver name silently disables hardware video
-- decoding rather than erroring.
hl.env("LIBVA_DRIVER_NAME", "iHD")
