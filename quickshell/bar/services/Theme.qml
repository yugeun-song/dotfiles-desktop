pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Palette values are taken from two published themes rather than invented:
    //   Spaceduck    https://github.com/pineapplegiant/spaceduck   (bg, fg, greys, selection)
    //   Tokyo Night  https://github.com/folke/tokyonight.nvim      (blue, cyan, purple, green, orange)

    // ---------------------------------------------------------------------
    // Every dimension is px() of one scale, so proportions hold when it changes.
    // ---------------------------------------------------------------------
    // One scale, for the reference output: the 2560x1440 desk monitor these
    // sizes were tuned on. Every window then draws itself scaled by fit() for
    // the screen it is on, so a surface keeps the share of the screen it has
    // there. Per-screen sizing in whole pixels would need px() out of this
    // singleton and every token with it; a scaled scene graph keeps text
    // vector-sharp and costs one transform.
    readonly property real baseScale: 1.12
    readonly property int referenceWidth: 2560
    readonly property int referenceHeight: 1440

    readonly property real scaleOverride: Number(Quickshell.env("BAR_SCALE") ?? 0)
    readonly property real scale: root.scaleOverride > 0 ? root.scaleOverride : root.baseScale

    // The factor a window on `screen` is drawn at: the square root of the
    // logical area ratio to the reference, so both a surface's aspect ratio
    // and the fraction of the screen it covers stay what they are on the desk
    // monitor. Density is not corrected: the panel is read from closer, and
    // the same share of the screen is what was asked for, not the same
    // millimetres. Floored at minFit, though: below the reference the share
    // shrank the bar past reading size (the 1920x1200 panel came out at 0.79,
    // an 11 px label), so a smaller screen draws at reference pixels and
    // gives up the share instead. Capped against a huge logical screen.
    // config/monitors.lua scales Hyprland's gaps, borders and rounding by
    // the same number; keep the two in step.
    readonly property real minFit: 1
    readonly property real maxFit: 2

    function fit(screen): real {
        const w = screen?.width ?? 0;
        const h = screen?.height ?? 0;
        if (w <= 0 || h <= 0)
            return 1;
        return Math.max(root.minFit, Math.min(root.maxFit, Math.sqrt((w * h) / (root.referenceWidth * root.referenceHeight))));
    }

    function px(base: real): int {
        return Math.round(base * root.scale);
    }

    readonly property int textSize:    root.px(12)
    // Menus are not short of room, so they read larger than the bar.
    readonly property int menuTextSize: root.px(14)
    // Nerd Font glyphs sit inside their em box; ask for icons larger than text.
    readonly property int iconSize:    root.px(21)
    readonly property int pillHeight:  root.px(28)
    readonly property int pillMargin:  root.px(13)
    readonly property int pillRadius:  root.px(10)
    readonly property int pillPadding: root.px(11)
    readonly property int pillGlyphGap: root.px(6)
    readonly property int gap:         root.px(6)
    // Between groups of different kinds; a gap, not a divider.
    readonly property int groupGap:    root.px(13)
    readonly property int edgeMargin:  root.px(10)
    // Wider than the left: nothing past the screen corner balances it.
    readonly property int edgeMarginRight: root.px(18)

    // ---------------------------------------------------------------------
    // The menu bar. barHeight is the room around the text, not solved from it,
    // and every other surface measures from it.
    // ---------------------------------------------------------------------
    readonly property int barHeight:   root.px(33)

    // One size, two weights: the app name differs by weight only.
    readonly property int menuBarTextSize: root.px(13)
    // One step under the title: the right side is a row of readouts, and at
    // the title's size they competed with it. Glyphs keep their own sizes.
    readonly property int statusTextSize:  root.px(12)
    // Denser on the right: a glyph carries its own padding, a word does not.
    readonly property int menuTitleGap:  root.px(16)
    readonly property int statusItemGap: root.px(9)
    // A hover highlight wider than its text, so it reads as a target.
    readonly property int menuItemPadX:  root.px(8)
    readonly property int menuItemRadius: root.px(6)
    readonly property int statusIconSize: root.px(17)
    // Per-glyph size boosts, measured off a render: some Nerd Font glyphs draw
    // well inside their em box. This one for the bell and the Bluetooth mark,
    readonly property real statusIconBoost: 1.22
    // this for the wifi arcs,
    readonly property real statusIconBoostMore: 1.32
    // and this for weather (a cloud and a sun share one box).
    readonly property real statusIconBoostWeather: 1.40

    // One line box for every word and glyph on the bar, since Inter and the
    // Nerd Font disagree on where a line's middle is. Fits the largest glyph.
    readonly property int barLineHeight: Math.round(root.statusIconSize * root.statusIconBoostWeather)
    // Wide because the battery glyph's terminal nub reaches past its outline.
    readonly property int statusGlyphGap: root.px(9)
    // Hover highlight inset, proportional to the bar height.
    readonly property int barInset: Math.max(2, Math.round(root.barHeight * 0.14))

    // Caption beside the value (two stacked lines do not fit), both in the
    // bar's text size and weight so the readouts sit level with the words
    // around them; a smaller or dimmer caption read as a different font.
    readonly property int statusCaptionGap:  root.px(6)

    // Captions are right-aligned in this width so the gap before each value
    // is equal; in Inter, CPU, RAM, BAT and CHG all differ in width.
    readonly property int statusCaptionWidth: Math.ceil(captionMetrics.width)

    TextMetrics {
        id: captionMetrics

        font.family: root.uiFont
        font.pixelSize: root.statusTextSize
        // The widest of the four the bar uses.
        text: "CHG"
    }

    // Characters of a window name, hence px(); the screen share is only a
    // ceiling (a pure share cut the laptop, where the name is set larger).
    readonly property int appNameWidth: Math.min(
        Math.round(root.referenceWidth * 0.16), root.px(228))
    readonly property int workspaceTextSize: root.px(12)
    // Same cell for one and two digits, so the row does not reflow at 10.
    readonly property int workspaceMinWidth: root.px(19)

    // Opaque, so the contents keep their contrast whatever the wallpaper.
    readonly property color menuBarBg: root.bg
    readonly property color menuBarLine: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
    readonly property color menuHover:   Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

    // ---------------------------------------------------------------------
    // Floating surfaces (tooltip, menus, toasts, overlays) use the bar's own
    // colours so they read as the bar, not as another program.
    // ---------------------------------------------------------------------
    readonly property color surfaceBg:    root.bg
    readonly property color surfaceLine:  root.menuBarLine
    readonly property color surfaceText:  root.fg
    readonly property color surfaceDim:   Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.78)
    readonly property color surfaceFaint: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.52)
    readonly property color surfaceHover: root.menuHover

    // Below muted: a radio that is off or unconnected (no reading at all),
    // as opposed to a quiet reading.
    readonly property color offTone: Qt.rgba(root.muted.r, root.muted.g, root.muted.b, 0.55)

    // A card on a same-coloured surface has no edge and a 10% hairline
    // vanishes on dark, so cards are lifted slightly instead.
    readonly property color surfaceRaised: Qt.lighter(root.bg, 1.45)
    readonly property color surfaceRaisedHover: Qt.lighter(root.bg, 1.9)
    readonly property int surfaceRadius:  root.px(16)
    readonly property int surfaceBorder:  Math.max(1, root.px(1))

    // ---------------------------------------------------------------------
    // The media chip in the bar, and the player it opens.
    // ---------------------------------------------------------------------
    // Width cap for the chip; Bar.qml narrows it further to the free room.
    readonly property int mediaChipWidth: Math.round(root.referenceWidth * 0.20)

    // Wide and shallow: a squarer card left more space above and below.
    readonly property int mediaCardWidth:  root.px(540)
    // No height token: popups are content plus popupPad on all four sides.
    // Shared with the calendar.
    readonly property int popupPad: root.px(18)
    readonly property int mediaGap:        root.px(10)

    readonly property int mediaArtSize:   root.px(52)
    readonly property int mediaTitleSize: root.px(15)
    readonly property int mediaSubSize:   root.px(12)
    readonly property int mediaTimeSize:  root.px(11)
    readonly property int mediaProgressHeight: root.px(14)

    // Graded rather than uniform: play-pause largest, skip either side of it,
    // shuffle and repeat smallest at the ends.
    readonly property int mediaControlMain: root.px(22)
    readonly property int mediaControlSkip: root.px(18)
    readonly property int mediaControlEdge: root.px(14)

    // Calendar popup. The heading-to-grid gap sets its width; the day is at
    // display size so the date reads at a glance.
    readonly property int calendarGap:         root.px(30)
    readonly property int calendarCellSize:    root.px(22)
    readonly property int calendarMonthSize:   root.px(20)
    readonly property int calendarTodaySize:   root.px(32)
    readonly property int calendarTodayLabel:  root.px(13)
    readonly property int calendarDaySize:     root.px(13)
    readonly property int calendarWeekdaySize: root.px(11)

    readonly property int chipSpacing: root.px(3)

    readonly property int mediaPadding:   root.px(12)
    readonly property int mediaItemGap:   root.px(7)

    // 22 bands (cava.conf) drawn thinner, not a wider meter.
    readonly property int vizBarWidth:   Math.max(2, root.px(3))
    readonly property int vizBarSpacing: Math.max(1, root.px(2))
    readonly property int vizPadding:    root.px(6)

    readonly property int tooltipRadius:  root.px(10)
    readonly property int tooltipPadX:    root.px(12)
    readonly property int tooltipPadY:    root.px(8)
    readonly property int tooltipGap:     root.px(12)

    readonly property int windowChipPadding:  root.px(10)

    readonly property int notifWidth:       root.px(392)
    readonly property int notifRadius:      root.px(15)
    readonly property int notifPad:         root.px(14)
    readonly property int notifStackGap:    root.px(8)
    readonly property int notifTitleSize:   root.px(19)
    readonly property int notifBodySize:    root.px(14)
    readonly property int notifLabelSize:   root.px(11)
    readonly property real notifTracking:   root.scale * 1.25

    // ---------------------------------------------------------------------
    // Displays panel (modules/Displays.qml).
    // ---------------------------------------------------------------------
    // Wide enough for five preset tiles in a row and a mode list beside its
    // label; the card still fits the laptop panel's logical width.
    readonly property int displaysWidth:         root.px(880)
    readonly property int displaysPad:           root.px(26)
    // Tall enough for a 16:10 panel beside a 16:9 desk monitor without
    // shrinking the numbers past legibility.
    readonly property int displaysCanvasHeight:  root.px(210)
    // Pictogram plus a one-line label.
    readonly property int displaysTileHeight:    root.px(96)
    // Label column of the settings rows, fitted to "Rotation".
    readonly property int displaysLabelWidth:    root.px(92)
    readonly property int displaysRowHeight:     root.px(36)
    // Long enough to glance at every screen, short enough not to linger.
    readonly property int displaysIdentifyMs:    2000
    // A dark screen needs time to be noticed and reached; twice what GNOME
    // gives, since the panel may be the screen that went dark.
    readonly property int displaysRevertSeconds: 30

    readonly property int centreWidth:      root.px(452)
    readonly property int centreRadius:     root.px(16)
    readonly property int centrePad:        root.px(13)
    readonly property int notifRowRadius:   root.px(12)
    readonly property int notifRowPad:      root.px(12)
    readonly property int notifBorder:      Math.max(2, root.px(2))
    // Toast dwell bar. Thicker than the border so it does not merge with it;
    // keep it well under notifRadius, since it clips to the corner arc.
    readonly property int notifLifeBar:     Math.max(4, root.px(4))

    // ---------------------------------------------------------------------
    // spaceduck palette, matching the kitty theme
    // ---------------------------------------------------------------------
    readonly property color bg:     "#0f111b"
    readonly property color bgAlt:  "#1b1c36"
    readonly property color fg:     "#ecf0c1"
    readonly property color muted:  "#686f9a"
    readonly property color red:    "#e33400"
    readonly property color green:  "#5ccc96"
    readonly property color yellow: "#f2ce00"
    readonly property color blue:   "#00a3cc"
    readonly property color purple: "#b3a1e6"
    readonly property color violet: "#7a5ccc"

    // ---------------------------------------------------------------------
    // Tokyo Night accents, all taking dark text.
    // ---------------------------------------------------------------------
    readonly property color accentRed:    "#f7768e"
    readonly property color accentOrange: "#ff9e64"
    readonly property color accentAmber:  "#e0af68"
    readonly property color accentGreen:  "#9ece6a"
    readonly property color accentTeal:   "#73daca"
    readonly property color accentSky:    "#7dcfff"
    readonly property color accentIndigo: "#7aa2f7"
    readonly property color accentPurple: "#bb9af7"
    readonly property color accentQuiet:  "#c0caf5"

    // Second accent set: reaches down to 55% lightness so the right group varies
    // in tone, not just hue; saturation held to 55-72% to avoid glare.
    readonly property color accentSaffron: "#e4bf58"
    readonly property color accentJade:    "#4dcbaa"
    readonly property color accentAzure:   "#6a9ae7"
    readonly property color accentViolet:  "#a076db"
    readonly property color accentRose:    "#d5729d"

    // Unused (the alert colour is accentRed); kept as a palette record.
    readonly property color accentAlert:   "#ef3963"

    readonly property color beige: "#ecf0c1"
    readonly property color ink:   "#0f111b"

    property bool barAtBottom: false

    // The families this desktop is set up with come first; a machine without
    // them takes the first installed alternative at start, since a family Qt
    // cannot find renders every icon code point as tofu and every word in
    // whatever fontconfig picks. Qt.fontFamilies() is fontconfig's list.
    function firstInstalled(candidates, fallback) {
        const families = Qt.fontFamilies();
        for (const name of candidates) {
            if (families.indexOf(name) !== -1)
                return name;
        }
        return fallback;
    }

    readonly property string uiFont: root.firstInstalled(
        ["Inter", "Inter Variable", "Noto Sans", "DejaVu Sans", "Cantarell", "Liberation Sans"], "sans-serif")

    // Any Nerd Font carries the same glyph code points; the mono cut keeps
    // the icons on one advance width.
    readonly property string iconFont: {
        const named = root.firstInstalled(
            ["CaskaydiaCove Nerd Font Mono", "Symbols Nerd Font Mono", "JetBrainsMono Nerd Font Mono",
             "FiraCode Nerd Font Mono", "Hack Nerd Font Mono"], "");
        if (named !== "")
            return named;
        const any = Qt.fontFamilies().find(f => f.endsWith("Nerd Font Mono"))
                    ?? Qt.fontFamilies().find(f => f.indexOf("Nerd Font") !== -1);
        return any ?? "monospace";
    }

    // Same file as iconFont, named for where columns must line up.
    readonly property string monoFont: root.iconFont

    // Key and modifier symbols, used by the key overlay (via KeyFeed).
    // Super is a diamond: U+2318 means Command on a Mac.
    readonly property var modSymbol: ({
        "Ctrl":  "\u2303",
        "Alt":   "\u2325",
        "Shift": "\u21E7",
        "Super": "\u2756"
    })

    // Checked against Inter; keys it has no glyph for (Home, End) stay words.
    readonly property var keySymbol: ({
        "Enter":     "\u23CE",
        "Tab":       "\u21E5",
        "Backspace": "\u232B",
        "Del":       "\u2326",
        "Esc":       "\u238B",
        "Space":     "\u2423",
        "Caps":      "\u21EA",
        "PgUp":      "\u21DE",
        "PgDn":      "\u21DF",
        "Up":        "\u2191",
        "Down":      "\u2193",
        "Left":      "\u2190",
        "Right":     "\u2192"
    })
    readonly property int workspaceCount: 10

    // Written as code points: astral-plane literals corrupt easily into tofu.
    readonly property string iconWifiOff:   String.fromCodePoint(0xF092D)
    readonly property string iconWifiDown:  String.fromCodePoint(0xF092F)
    readonly property string iconWifi1:     String.fromCodePoint(0xF0925)
    readonly property string iconWifi2:     String.fromCodePoint(0xF0926)
    readonly property string iconWifi3:     String.fromCodePoint(0xF0927)
    readonly property string iconWifi4:     String.fromCodePoint(0xF0928)
    readonly property string iconEthernet:  String.fromCodePoint(0xF0200)
    readonly property string iconBt:        String.fromCodePoint(0xF00AF)
    readonly property string iconBtOff:     String.fromCodePoint(0xF00B2)
    readonly property string iconBtLinked:  String.fromCodePoint(0xF00B1)
    // Picked for silhouette: fa-memory is a DIMM, so it does not read as a
    // second CPU die at bar size.
    readonly property string iconCpu:       String.fromCodePoint(0xF4BC)
    readonly property string iconMemory:    String.fromCodePoint(0xEFC5)
    readonly property string iconPlay:      String.fromCodePoint(0xF04B)
    readonly property string iconPause:     String.fromCodePoint(0xF04C)
    readonly property string iconNext:      String.fromCodePoint(0xF04AD)
    readonly property string iconPrev:      String.fromCodePoint(0xF04AE)
    readonly property string iconStop:      String.fromCodePoint(0xF04DB)
    readonly property string iconMusic:     String.fromCodePoint(0xF001)
    // From the font's cmap. U+F04E1 (iconSwap) is md-swap_horizontal, not a shuffle.
    readonly property string iconShuffle:   String.fromCodePoint(0xF049D)
    readonly property string iconRepeat:    String.fromCodePoint(0xF0456)
    readonly property string iconRepeatOne: String.fromCodePoint(0xF0458)
    readonly property string iconCapsLock:  String.fromCodePoint(0xF033E)
    readonly property string iconKeyboard:  String.fromCodePoint(0xF030C)
    readonly property string iconCheck:     String.fromCodePoint(0xF012C)
    readonly property string iconRestart:   String.fromCodePoint(0xF0450)
    readonly property string iconSettings:  String.fromCodePoint(0xF0493)
    readonly property string iconSwap:      String.fromCodePoint(0xF04E1)
    readonly property string iconLock:      String.fromCodePoint(0xF033E)
    readonly property string iconLogout:    String.fromCodePoint(0xF0343)
    readonly property string iconSleep:     String.fromCodePoint(0xF0904)
    readonly property string iconPower:     String.fromCodePoint(0xF0425)
    readonly property string iconSearch:    String.fromCodePoint(0xF0349)
    readonly property string iconApps:      String.fromCodePoint(0xF003C)
    readonly property string iconBrightness: String.fromCodePoint(0xF00DE)
    readonly property string iconVolume:    String.fromCodePoint(0xF057E)
    readonly property string iconVolumeMed: String.fromCodePoint(0xF0580)
    readonly property string iconVolumeLow: String.fromCodePoint(0xF057F)
    readonly property string iconVolumeOff: String.fromCodePoint(0xF0581)
    readonly property string iconAlarm:     String.fromCodePoint(0xF0020)
    readonly property string iconAlarmRing: String.fromCodePoint(0xF0E47)

    // Rendered and checked, not just found in the cmap (F0A21 exists but is a
    // window grid). One bell for every state: variants repeat the colour and
    // count, and a struck-out bell reads as "notifications off".
    readonly property string iconBell:      String.fromCodePoint(0xF009A)
    readonly property string iconClock:     String.fromCodePoint(0xF0150)
    readonly property string iconClearAll:  String.fromCodePoint(0xF0A79)
    readonly property string iconBatteryAlert: String.fromCodePoint(0xF0083)
    readonly property string iconPlug:         String.fromCodePoint(0xF06A5)

    // Replaces a status glyph that has no reading (StatusItem.unread).
    // md-help_circle_outline, name read from the cmap.
    readonly property string iconUnknown:      String.fromCodePoint(0xF0625)

    // Relative luminance, WCAG 2.1. QML colour channels are already 0..1.
    function luminance(c: color): real {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    // readableOn takes whichever text colour has more contrast; a luminance
    // threshold fails mid-range (#7aa2f7: 2.1:1 light vs 7.4:1 dark).
    function contrast(a: color, b: color): real {
        const la = root.luminance(a);
        const lb = root.luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    function readableOn(bg: color): color {
        return root.contrast(bg, root.ink) >= root.contrast(bg, root.fg)
               ? root.ink : root.fg;
    }


    // ---------------------------------------------------------------------
    // Freshness. A binding over Date.now() evaluates once and never again, so
    // such bindings read `now` from this shared clock (seconds, for expiries).
    // ---------------------------------------------------------------------
    SystemClock {
        id: tick

        precision: SystemClock.Seconds
    }

    readonly property double now: tick.date.getTime()

    // "" while the reading is fresh, else a reason that follows "No reading".
    // asOf is when a value was accepted (0 = never), not when it was requested.
    // maxAgeMs 0 means edge-triggered: silence is not staleness.
    function stale(asOf: double, maxAgeMs: int): string {
        if (asOf <= 0)
            return "Nothing has arrived yet";
        if (maxAgeMs <= 0)
            return "";
        const age = root.now - asOf;
        if (age <= maxAgeMs)
            return "";
        const seconds = Math.round(age / 1000);
        if (seconds < 90)
            return `Last read ${seconds}s ago`;
        const minutes = Math.round(seconds / 60);
        if (minutes < 90)
            return `Last read ${minutes}m ago`;
        return `Last read ${Math.round(minutes / 60)}h ago`;
    }

    // WMO codes, as weather.sh reports them. Five colour groups, coarser than
    // weatherIcon; every face stays at 7.5:1 or better.
    function weatherColor(code: int, day: bool): color {
        switch (true) {
        // Clear: the only group split by day and night.
        case code === 0:
            return day ? root.accentAmber : root.accentQuiet;
        // Cloud and fog.
        case code <= 3 || code === 45 || code === 48:
            return root.accentSky;
        // Water coming down, from drizzle to showers.
        case (code >= 51 && code <= 65) || (code >= 80 && code <= 82):
            return root.accentIndigo;
        // Frozen, which is snow and the freezing rain that behaves like it.
        case (code >= 66 && code <= 77) || code === 85 || code === 86:
            return root.fg;
        // Storm.
        case code >= 95:
            return root.accentPurple;
        default:
            return root.accentSky;
        }
    }

    // Filled Font Awesome cloud glyphs: Material's stroked set blurred at bar
    // size. Code points and names read from the cmap. Clear sky stays Material
    // because Font Awesome's only sun here, fa-sun_o, is an outline.
    function weatherIcon(code: int, day: bool): string {
        switch (true) {
        // Clear.
        case code === 0:
            return String.fromCodePoint(day ? 0xF0599   // md-weather_sunny
                                            : 0xF0594); // md-weather_night
        // Some cloud, sun or moon still showing.
        case code === 1 || code === 2:
            return String.fromCodePoint(day ? 0x0EEF0   // fa-cloud_sun
                                            : 0x0EEEF); // fa-cloud_moon
        // Overcast and fog.
        case code === 3 || code === 45 || code === 48:
            return String.fromCodePoint(0x0F0C2);       // fa-cloud
        // Drizzle, and rain that is not heavy.
        case (code >= 51 && code <= 57) || (code >= 61 && code <= 63):
            return String.fromCodePoint(0x0EF1C);       // fa-cloud_rain
        // Heavy rain and showers.
        case code === 65 || (code >= 80 && code <= 82):
            return String.fromCodePoint(0x0EF1D);       // fa-cloud_showers_heavy
        // Freezing rain and sleet: rain and ice in the same fall.
        case code === 66 || code === 67:
            return String.fromCodePoint(0x0EF1A);       // fa-cloud_meatball
        // Snow.
        case (code >= 71 && code <= 77) || code === 85 || code === 86:
            return String.fromCodePoint(0xF0598);       // md-weather_snowy
        // Storm, with or without hail.
        case code >= 95:
            return String.fromCodePoint(0x0EF2C);       // fa-cloud_bolt
        default:
            return String.fromCodePoint(0x0F0C2);       // fa-cloud
        }
    }

    function weatherText(code: int): string {
        switch (true) {
        case code === 0:
            return "Clear";
        case code === 1:
            return "Mostly clear";
        case code === 2:
            return "Partly cloudy";
        case code === 3:
            return "Overcast";
        case code === 45 || code === 48:
            return "Fog";
        case code >= 51 && code <= 55:
            return "Drizzle";
        case code === 56 || code === 57:
            return "Freezing drizzle";
        case code === 61:
            return "Light rain";
        case code === 63:
            return "Rain";
        case code === 65:
            return "Heavy rain";
        case code === 66 || code === 67:
            return "Freezing rain";
        case code === 71:
            return "Light snow";
        case code === 73:
            return "Snow";
        case code === 75:
            return "Heavy snow";
        case code === 77:
            return "Snow grains";
        case code >= 80 && code <= 82:
            return "Rain showers";
        case code === 85 || code === 86:
            return "Snow showers";
        case code === 95:
            return "Thunderstorm";
        case code === 96 || code === 99:
            return "Thunderstorm with hail";
        default:
            return "Unknown";
        }
    }

    function volumeIcon(percent: int, muted: bool): string {
        if (muted || percent <= 0)
            return root.iconVolumeOff;
        if (percent < 34)
            return root.iconVolumeLow;
        if (percent < 67)
            return root.iconVolumeMed;
        return root.iconVolume;
    }

    // Both battery runs step by ten from a base, but charging lacks a full
    // glyph and discharging an empty one, so those two are named separately.
    function batteryIcon(percent: int, charging: bool): string {
        const step = Math.max(0, Math.min(10, Math.round(percent / 10)));
        if (charging)
            return step >= 10 ? String.fromCodePoint(0xF0084) : String.fromCodePoint(0xF089B + step);
        if (step >= 10)
            return String.fromCodePoint(0xF0079);
        if (step <= 0)
            return String.fromCodePoint(0xF008E);
        return String.fromCodePoint(0xF0079 + step);
    }

    readonly property int batteryLowPercent: 10

    // Window classes do not always match an icon name. Try the class as
    // given, then lower case, then the trailing component of a reverse-DNS id
    // such as org.kde.dolphin. Returns "" when nothing in the theme matches.
    function appIcon(name: string): string {
        if (!name)
            return "";
        const tries = [name, name.toLowerCase(), name.toLowerCase().split(".").pop()];
        for (const candidate of tries)
            if (candidate && Quickshell.hasThemeIcon(candidate))
                return Quickshell.iconPath(candidate, true);
        return "";
    }

    // Sized for "100%" so the number's right edge does not move.
    readonly property int percentWidth: Math.ceil(percentMetrics.width)

    TextMetrics {
        id: percentMetrics

        font.family: root.uiFont
        font.pixelSize: root.statusTextSize
        text: "100%"
    }

    // A count: four digits, no percent sign.
    readonly property int countWidth: Math.ceil(countMetrics.width)

    TextMetrics {
        id: countMetrics

        font.family: root.uiFont
        font.pixelSize: root.textSize
        font.weight: Font.Medium
        text: "9999"
    }

    // Fixed, not measured: TextMetrics of a lone space is 0 (trailing
    // whitespace is dropped), which left "CPU:" touching "100%".
    readonly property int labelGap: root.px(5)

    function shorten(value: string, limit: int): string {
        return value.length > limit ? value.slice(0, limit - 1) + "…" : value;
    }

    // Cover art: file://, or https from these hosts only. artUrl comes from the
    // player (for a browser, the page), so fetching anything else would turn a
    // tab into a beacon or a probe into the LAN.
    readonly property var artHosts: [
        "i.scdn.co",                      // Spotify
        "i.ytimg.com",                    // YouTube, through a browser's MPRIS
        "yt3.ggpht.com",                  // YouTube channel art
        "lastfm.freetls.fastly.net",      // Last.fm, which several players use
        "coverartarchive.org"             // MusicBrainz
    ]

    function localArt(url: string): string {
        if (!url)
            return "";
        if (url.startsWith("file://"))
            return url;
        if (!url.startsWith("https://"))
            return "";
        // The authority is everything before the first slash; userinfo is
        // dropped and the port ignored, so "evil.example@i.scdn.co" and
        // "i.scdn.co.evil.example" both fail the exact match below.
        const authority = url.slice(8).split("/")[0];
        const host = authority.split("@").pop().split(":")[0].toLowerCase();
        return root.artHosts.indexOf(host) !== -1 ? url : "";
    }

    // Single alert threshold for CPU and memory load.
    readonly property real loadAlertFraction: 0.90
}
