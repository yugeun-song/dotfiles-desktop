pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Palette values are taken from two published themes rather than invented:
    //   Spaceduck    https://github.com/pineapplegiant/spaceduck   (bg, fg, greys, selection)
    //   Tokyo Night  https://github.com/folke/tokyonight.nvim      (blue, cyan, purple, green, orange)

    // ---------------------------------------------------------------------
    // Every dimension below is derived from one number. The base values are
    // the proportions the bar was designed at; changing scale keeps the ratio
    // between text, icon, pill height and padding intact instead of drifting
    // as individual values get nudged.
    // ---------------------------------------------------------------------
    // The bar sets this to the screen it is drawn on. Only one output is ever
    // active on this machine (config/monitors.lua disables the laptop panel while
    // an external display is attached), so a single global scale is accurate;
    // a multi-head setup would need this per bar instead of in the singleton.
    // Deterministic, rather than whichever bar finished loading last. With two
    // bars alive both wrote this, so the scale depended on load order and the
    // bar changed height between runs of the same layout: an unscaled 1800-row
    // panel winning the race took px() from 1.12 to 1.31 and every bar with it.
    // The output at the left of the layout is the main desktop and does not
    // move when a second one appears.
    //
    // It is still one scale for every bar. Sizing each bar to its own screen
    // means taking the scale out of this singleton, which px() being global
    // rules out; the note is here so the limit is known and not rediscovered.
    readonly property var referenceScreen: {
        const list = Quickshell.screens;
        if (!list || list.length === 0)
            return null;
        let best = list[0];
        for (let i = 1; i < list.length; i++) {
            const s = list[i];
            if (s.x < best.x || (s.x === best.x && s.y < best.y))
                best = s;
        }
        return best;
    }

    readonly property real baseScale: 1.12
    readonly property int referenceHeight: 1440

    // How wide a logical pixel actually is, in millimetres.
    //
    // Hyprland hands quickshell logical pixels with fractional scaling already
    // applied, so a logical pixel is not a fixed size: it is one physical
    // pixel on the 27-inch panel this was designed against and 1.5 of them on
    // the laptop's 2880x1800 at scale 1.5. Sizing from the logical resolution
    // alone therefore got the laptop backwards -- fewer rows read as "smaller
    // screen, shrink", when the truth is that every logical pixel there is
    // physically two thirds the size and the bar needed to grow.
    readonly property real referenceLogicalMm: 0.235   // 2560x1440 at 27 inches

    readonly property real logicalMm: {
        const s = root.referenceScreen;
        const density = s?.physicalPixelDensity ?? 0;   // physical px per mm
        if (!density)
            return root.referenceLogicalMm;
        return (s.devicePixelRatio > 0 ? s.devicePixelRatio : 1) / density;
    }

    // Two corrections, both deliberately partial.
    //
    // Density: a logical pixel two thirds the size wants two thirds more of
    // them, but a 14-inch screen is also read from closer than a 27-inch one,
    // and correcting in full makes a laptop bar that looks enormous. The
    // square root splits the difference, which lands the laptop about 15%
    // larger than the monitor rather than 50%.
    //
    // Resolution: what is left of the old rule, weakened, so that a genuinely
    // short panel still gets a slightly shorter bar.
    readonly property real densityFactor: Math.pow(root.referenceLogicalMm / root.logicalMm, 0.5)

    readonly property real autoScale: {
        const height = root.referenceScreen?.height ?? root.referenceHeight;
        const rows = Math.pow(height / root.referenceHeight, 0.35);
        return Math.max(0.85, Math.min(1.60, root.baseScale * rows * root.densityFactor));
    }

    readonly property real scaleOverride: Number(Quickshell.env("BAR_SCALE") ?? 0)
    readonly property real scale: root.scaleOverride > 0 ? root.scaleOverride : root.autoScale

    function px(base: real): int {
        return Math.round(base * root.scale);
    }

    readonly property int textSize:    root.px(12)
    // Menus are read at a glance and are not competing for room the way
    // the bar is, so they carry their own, larger size.
    readonly property int menuTextSize: root.px(14)
    // Nerd Font glyphs sit well inside their em box, so a glyph asked for at
    // the text size renders visibly smaller than the text beside it. The base
    // here is deliberately larger than textSize to compensate.
    readonly property int iconSize:    root.px(21)
    readonly property int pillHeight:  root.px(28)
    readonly property int pillMargin:  root.px(13)
    readonly property int pillRadius:  root.px(10)
    readonly property int pillPadding: root.px(11)
    readonly property int pillGlyphGap: root.px(6)
    readonly property int gap:         root.px(6)
    // Between groups that are different kinds of thing, rather than between
    // items of one kind. Small enough to stay a gap and not a division.
    readonly property int groupGap:    root.px(13)
    readonly property int edgeMargin:  root.px(10)
    // The right group ends at the screen corner, where a margin equal to
    // the left one reads as too tight: there is nothing beyond it to
    // balance against.
    readonly property int edgeMarginRight: root.px(18)

    // ---------------------------------------------------------------------
    // The menu bar.
    //
    // The height is the one number here that is not solved from the text: the
    // text sizes are what they are and this is the room around them. 26 was
    // the macOS menu bar at this scale and read as tight against glyphs this
    // size, so it carries a little more.
    //
    // The name stays barHeight because every other surface measures from it.
    // ---------------------------------------------------------------------
    readonly property int barHeight:   root.px(33)

    // One size, two weights. The app name is set apart by weight alone, which
    // is what macOS does.
    readonly property int menuBarTextSize: root.px(13)
    // The right side is denser because a glyph carries its own padding and a
    // word does not.
    readonly property int menuTitleGap:  root.px(16)
    readonly property int statusItemGap: root.px(9)
    // A hover highlight wider than its text, so it reads as a target.
    readonly property int menuItemPadX:  root.px(8)
    readonly property int menuItemRadius: root.px(6)
    readonly property int statusIconSize: root.px(17)
    // Some Nerd Font glyphs draw a lot smaller than their em box: the wifi
    // arcs, the bell and the weather symbols all sit well inside theirs while
    // the Bluetooth mark fills its own. Asking for one size therefore does not
    // produce one size on screen, so the small ones are asked for larger. The
    // factor is measured off a render, not derived.
    readonly property real statusIconBoost: 1.22
    // And a second step for the ones that sit further in still. The wifi arcs,
    // the Bluetooth mark and the weather glyphs all draw noticeably smaller
    // than the bell at the same size, so they are asked for larger again.
    // Both factors are measured off a render, not derived.
    readonly property real statusIconBoostMore: 1.32
    // A third step for the weather set, which draws smaller again -- a cloud
    // with a sun behind it has to fit two shapes in the box one shape gets.
    readonly property real statusIconBoostWeather: 1.40

    // The box every word and every glyph on the bar is drawn in, and centred
    // within. One height for all of them, so nothing is centred against its
    // own font's ascent and descent: Inter and the Nerd Font disagree about
    // where the middle of a line is, and a row of items each trusting its own
    // answer is a row that does not line up. Tall enough for the largest glyph
    // the bar asks for, which is a boosted one.
    readonly property int barLineHeight: Math.round(root.statusIconSize * root.statusIconBoostWeather)
    // Between a glyph and the number it belongs to. Wider than it looks like
    // it needs to be: the battery gauge ends in a terminal nub that reaches
    // further right than the outline does, so a gap sized against the outline
    // leaves the number touching it.
    readonly property int statusGlyphGap: root.px(9)
    // What the hover highlight leaves above and below itself. Derived rather
    // than fixed, so the bar keeps the same proportion of breathing room at
    // every height instead of looking tight when the bar grows.
    readonly property int barInset: Math.max(2, Math.round(root.barHeight * 0.14))

    // A caption beside a value: a small dim word, then the number. Stacked was
    // the reference's form and it is the wrong one at this bar height -- two
    // lines inside 26 units left both too small to read at a glance.
    // The caption is the same size as the value and only dimmer. Smaller as
    // well as dimmer was the first attempt and it read as a mistake: two sizes
    // an unnoticeable amount apart look like a font that failed to load rather
    // than like a label and its reading.
    readonly property int statusCaptionSize: root.px(12)
    readonly property int statusValueSize:   root.px(12)
    readonly property int statusCaptionGap:  root.px(6)

    // The captions are right-aligned inside this, so the gap after the word is
    // the same for all three. Inter is proportional: CPU, RAM and BAT are all
    // three letters and none of them is the same width, and U, M and T do not
    // carry the same right side bearing either. Left-aligned the three gaps
    // came out visibly different even though the spacing between the items was
    // identical.
    readonly property int statusCaptionWidth: Math.ceil(captionMetrics.width)

    TextMetrics {
        id: captionMetrics

        font.family: root.uiFont
        font.pixelSize: root.statusCaptionSize
        font.weight: Font.Medium
        // The widest of the four the bar uses.
        text: "CHG"
    }

    // The workspace numbers. A minimum width so single and double digits keep
    // the same cell and the row does not reflow crossing from 9 to 10.
    // A tenth of the bar, which is a tenth of the screen. Not a px() value:
    // this is a share of the room available rather than a size, so it should
    // track the screen's width and not the text scale. On this 2560 monitor it
    // is 256 logical pixels, which is a few dozen characters.
    readonly property int appNameWidth: Math.round((root.referenceScreen?.width ?? 1920) * 0.10)
    readonly property int workspaceTextSize: root.px(12)
    readonly property int workspaceMinWidth: root.px(19)

    // Opaque. It was translucent over a compositor blur for a while, and a
    // menu bar you can see the wallpaper through is a menu bar whose contents
    // change contrast as the wallpaper does. A flat surface is also one less
    // thing for the compositor to redraw.
    readonly property color menuBarBg: root.bg
    readonly property color menuBarLine: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
    readonly property color menuHover:   Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

    // ---------------------------------------------------------------------
    // Floating surfaces: the tooltip, the menus, the toasts, the overlays.
    //
    // One look for all of them, and the island is the one that set it --
    // near-black rather than the palette's blue-grey, generously rounded, and
    // separated from the desktop by a hairline instead of a coloured border.
    // Before this each surface had picked its own: the tooltip was beige with
    // dark text, the toasts were bgAlt with an accent border, the menus were
    // bgAlt with none, and nothing looked like it came from the same shell.
    //
    // Not pure black. The island is, because it is imitating a notch; a menu
    // that happens to open over a black wallpaper still has to be findable,
    // and this is dark enough to read as unlit without disappearing.
    // ---------------------------------------------------------------------
    // The bar's own colours, not a set of their own. A tooltip is the bar
    // answering a question about something on it, and a menu is the bar
    // opening; both looked like a different program's window while they had
    // their own near-black and pure white. The island keeps its own black
    // because it is imitating a notch, which is the one surface here that is
    // not the bar speaking.
    readonly property color surfaceBg:    root.bg
    readonly property color surfaceLine:  root.menuBarLine
    readonly property color surfaceText:  root.fg
    readonly property color surfaceDim:   Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.78)
    readonly property color surfaceFaint: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.52)
    readonly property color surfaceHover: root.menuHover

    // A card sitting on a surface of the same colour has no edge, and a
    // hairline border is not one either -- at a tenth opacity it disappears
    // against anything dark. This is the surface lifted just enough to
    // separate one card from the next without becoming a second colour.
    readonly property color surfaceRaised: Qt.lighter(root.bg, 1.45)
    readonly property color surfaceRaisedHover: Qt.lighter(root.bg, 1.9)
    readonly property int surfaceRadius:  root.px(16)
    readonly property int surfaceBorder:  Math.max(1, root.px(1))

    // ---------------------------------------------------------------------
    // The media chip in the bar, and the player it opens.
    // ---------------------------------------------------------------------
    // The chip is bar type at bar size; only its width is its own, capped so a
    // long title cannot reach the groups either side of it.
    readonly property int mediaChipWidth: Math.round((root.referenceScreen?.width ?? 1920) * 0.20)

    // Wide and shallow. The card holds three rows of a player, and at a
    // squarer ratio the rows had to be spread to fill it -- which is what put
    // more space above and below the content than beside it.
    readonly property int mediaCardWidth:  root.px(540)
    // No height token: a popup is as tall as its contents plus the same pad it
    // carries at the sides, so the four margins are equal by construction
    // rather than by a number that has to be re-solved whenever a row changes.
    // Shared with the calendar, which is built the same way.
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

    // The month, opened from the clock. The gap between the heading and the
    // grid is what gives this popup its width, the way the card's width token
    // does for the player: both are meant to be wider than they are tall.
    readonly property int calendarGap:         root.px(38)
    readonly property int calendarCellSize:    root.px(22)
    readonly property int calendarMonthSize:   root.px(20)
    readonly property int calendarDaySize:     root.px(13)
    readonly property int calendarWeekdaySize: root.px(11)

    readonly property int chipWidth:   root.px(27)
    readonly property int chipSpacing: root.px(3)

    readonly property int mediaMaxWidth:  root.px(420)
    readonly property int mediaPadding:   root.px(12)
    readonly property int mediaItemGap:   root.px(7)

    // Twenty-two bands rather than twelve, drawn thinner. The meter is a
    // little wider for it, not twice as wide: what the extra bands buy is
    // resolution, and a bar that grew with them would have been a different
    // widget.
    readonly property int vizBarWidth:   Math.max(2, root.px(3))
    readonly property int vizBarSpacing: Math.max(1, root.px(2))
    readonly property int vizPadding:    root.px(6)

    readonly property int tooltipRadius:  root.px(10)
    readonly property int tooltipPadX:    root.px(12)
    readonly property int tooltipPadY:    root.px(8)
    readonly property int tooltipGap:     root.px(12)

    readonly property int windowChipPadding:  root.px(10)
    readonly property int windowTitleWidth:   root.px(260)
    readonly property int windowNameWidth:    root.px(130)

    readonly property int notifWidth:       root.px(392)
    readonly property int notifRadius:      root.px(15)
    readonly property int notifPad:         root.px(14)
    readonly property int notifStackGap:    root.px(8)
    readonly property int notifTitleSize:   root.px(19)
    readonly property int notifBodySize:    root.px(14)
    readonly property int notifLabelSize:   root.px(11)
    readonly property real notifTracking:   root.scale * 1.25

    readonly property int centreWidth:      root.px(452)
    readonly property int centreRadius:     root.px(16)
    readonly property int centrePad:        root.px(13)
    readonly property int notifRowRadius:   root.px(12)
    readonly property int notifRowPad:      root.px(12)
    readonly property int notifBorder:      Math.max(2, root.px(2))
    // The dwell bar along the bottom of a toast. Four rather than the border's
    // two: at two it read as part of the border. Keep it well under
    // notifRadius -- the strip is a window onto a corner arc, and a taller one
    // climbs further up that arc than the eye reads as a bar.
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
    // Accent set for the status pills. The background stays spaceduck, but
    // the accents come from a wider palette so seven pills sitting in a row
    // stay tellable apart. Every one of these takes dark text.
    //
    // capsLock is not a free choice: it is copied from the p10k caps_lock
    // segment in ~/.config/zsh/caps-lock.zsh so the prompt and the bar agree.
    // ---------------------------------------------------------------------
    readonly property color capsLock: "#f7768e"
    readonly property color accentRed:    "#f7768e"
    readonly property color accentOrange: "#ff9e64"
    readonly property color accentAmber:  "#e0af68"
    readonly property color accentGreen:  "#9ece6a"
    readonly property color accentTeal:   "#73daca"
    readonly property color accentSky:    "#7dcfff"
    readonly property color accentIndigo: "#7aa2f7"
    readonly property color accentPurple: "#bb9af7"
    readonly property color accentQuiet:  "#c0caf5"

    // A second set for the status pills on the right. The accents above all sit
    // between 61% and 86% lightness, so eight of them in a row read as one
    // pastel family however far apart their hues are. These reach down to 55%,
    // which is the axis that was missing: the group varies in tone as well as
    // in hue.
    //
    // Saturation is deliberately not maxed. At full chroma the same hues were
    // garish against a dark desktop; pulled back to 55-72% they keep the tonal
    // spread without the glare.
    readonly property color accentSaffron: "#e4bf58"
    readonly property color accentJade:    "#4dcbaa"
    readonly property color accentAzure:   "#6a9ae7"
    readonly property color accentViolet:  "#a076db"
    readonly property color accentRose:    "#d5729d"

    // One colour for "this reading has left its normal range", shared by the
    // battery, the CPU load and the memory load so that the meaning is read
    // from the colour rather than from which pill is wearing it. Deeper than
    // the accents beside it on purpose: at 58% lightness it is the darkest
    // face in the group and does not read as one more hue in the sequence.
    // No longer drawn with: the bar has one alert colour now and it is
    // accentRed, shared with the calendar's Sunday. Kept because the palette
    // is a record of where these values came from.
    readonly property color accentAlert:   "#ef3963"

    readonly property color beige: "#ecf0c1"
    readonly property color ink:   "#0f111b"

    property bool barAtBottom: false

    readonly property string uiFont:   "Inter"
    readonly property string iconFont: "CaskaydiaCove Nerd Font Mono"

    // The same family under the name that says what it is for. iconFont is
    // asked for when a glyph is wanted and this when columns have to line up,
    // and a reader of either should not have to know they are the same file.
    readonly property string monoFont: "CaskaydiaCove Nerd Font Mono"

    // The printed symbols for the keys that have one, and the modifiers.
    //
    // They live here rather than in KeyFeed because two things draw them now:
    // the key overlay and the cheatsheet. KeyFeed reads a device and would drag
    // that along with it, and a table of glyphs is not a thing that reads a
    // device.
    //
    // Super takes the diamond rather than the command glyph: this is Linux, and
    // U+2318 means Command on a Mac. Borrowing it would be saying the wrong
    // thing in a symbol chosen for being unambiguous.
    readonly property var modSymbol: ({
        "Ctrl":  "\u2303",
        "Alt":   "\u2325",
        "Shift": "\u21E7",
        "Super": "\u2756"
    })

    // Every codepoint here was checked against Inter, which is what draws them.
    // The ones Inter does not carry, Home and End among them, keep their words
    // rather than becoming a box.
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

    // Nerd Font glyphs are written as code points, not literals: the astral
    // plane characters used by Material Design Icons are easy to corrupt when
    // a file is copied or re-encoded, and a corrupted one renders as tofu.
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
    // Chosen for silhouette, not just meaning. These used to be oct-cpu and
    // md-chip, which are both a square die with legs down two sides: at 21px
    // the pair differed only in detail and the memory pill did not read as
    // memory at all. fa-memory is a DIMM -- a wide board carrying a row of
    // dies, with pins along the bottom edge -- so the two now differ in
    // outline. The name in the font is what was checked, not the code point.
    readonly property string iconCpu:       String.fromCodePoint(0xF4BC)
    readonly property string iconMemory:    String.fromCodePoint(0xEFC5)
    readonly property string iconPlay:      String.fromCodePoint(0xF04B)
    readonly property string iconPause:     String.fromCodePoint(0xF04C)
    readonly property string iconNext:      String.fromCodePoint(0xF04AD)
    readonly property string iconPrev:      String.fromCodePoint(0xF04AE)
    readonly property string iconStop:      String.fromCodePoint(0xF04DB)
    readonly property string iconMusic:     String.fromCodePoint(0xF001)
    // Read out of the font's own cmap rather than guessed: md-shuffle,
    // md-repeat and md-repeat_once. U+F04E1, which this file already carries
    // as iconSwap, is md-swap_horizontal and is not a shuffle.
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

    // Every codepoint here was rendered and looked at, not just checked for
    // presence in the font. F0A21 is in the font and is not a bell: it is a
    // window grid. Membership in the cmap says a glyph exists, never which
    // glyph it is.
    // One bell, in every state. The ringing and exclamation-mark variants say
    // the same thing the colour and the count already say, and a bell with a
    // glyph struck through it reads as "notifications are off" rather than as
    // "there are none".
    readonly property string iconBell:      String.fromCodePoint(0xF009A)
    readonly property string iconClock:     String.fromCodePoint(0xF0150)
    readonly property string iconClearAll:  String.fromCodePoint(0xF0A79)
    readonly property string iconBatteryAlert: String.fromCodePoint(0xF0083)
    readonly property string iconPlug:         String.fromCodePoint(0xF06A5)

    // The one glyph here that is not a subject: it says the pill around it has
    // no reading. Outline rather than filled, to match the hollow face Pill
    // draws under it. This is md-help_circle_outline -- the name was read out
    // of the font's own cmap, per the note above about membership never saying
    // which glyph a code point is.
    readonly property string iconUnknown:      String.fromCodePoint(0xF0625)

    // WMO weather codes, the same table the weather script prints from.
    // Relative luminance, WCAG 2.1. QML gives r, g and b already normalised.
    function luminance(c: color): real {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    // Which text colour survives on a given face: whichever of the two wins the
    // contrast, not whichever side of a brightness threshold the face falls on.
    // A threshold is wrong in the middle of the range -- #7aa2f7 sits just below
    // one at 0.4 and so would take the light foreground, for 2.1:1, when the
    // dark ink gives 7.4:1 on the same face.
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
    // Freshness.
    //
    // A binding written over Date.now() is evaluated once, when it is created,
    // and never again: nothing it depends on ever changes. So a reading that
    // was current at startup stays current on screen for the life of the
    // shell, which is the exact failure this is here to catch. One clock,
    // shared, gives every such binding something that does change.
    //
    // Seconds rather than Minutes: an expiry measured in seconds cannot be
    // driven by a clock that only moves once a minute.
    // ---------------------------------------------------------------------
    SystemClock {
        id: tick

        precision: SystemClock.Seconds
    }

    readonly property double now: tick.date.getTime()

    // Empty while the reading is still worth drawing. Otherwise the reason it
    // is not, phrased to follow "No reading" in a tooltip.
    //
    // asOf is the instant the value was *accepted*, never the instant it was
    // asked for: a helper that is running, a file that still opens and a cache
    // that still serves all say the source is alive and none of them says the
    // number is current. Zero means nothing has ever been accepted.
    //
    // maxAgeMs of 0 means the source is edge-triggered -- it speaks only when
    // something changes -- so silence is not evidence and only asOf being
    // cleared makes the reading unknown.
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

    // Five things the sky can be doing, not thirteen. weatherIcon splits the
    // WMO codes finely because a drizzle glyph and a rain glyph are worth
    // telling apart at a glance; colour is a coarser instrument and one colour
    // per code spends it on distinctions nobody reads off a pill.
    //
    // Collapsing fog into the cloud group also retires the one contrast
    // failure in the set: muted is a colour for dim text and reached only
    // 4.11:1 as a face. Nothing here is below 7.5:1 now.
    function weatherColor(code: int, day: bool): color {
        switch (true) {
        // Clear. The only state that says something about the light rather
        // than about what is falling, so it is the only one split by hour.
        case code === 0:
            return day ? root.accentAmber : root.accentQuiet;
        // Cloud, in every thickness, fog included: the sky is a lid.
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

    // Solid glyphs, not outlines.
    //
    // These were Material Design's md-weather_* set, which draws the sky as
    // thin strokes: at 16 pixels on a bar a drizzle and a downpour were the
    // same grey smudge. Font Awesome's cloud family is filled, so the
    // silhouette carries the reading and the drops below it are what differ.
    //
    // Every code point was read out of the font's own cmap, and the name is
    // written beside it: membership says a glyph exists, never which glyph.
    // The two clear-sky ones stay Material because Font Awesome's only sun
    // here is fa-sun_o, which is an outline.
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
        // Overcast, and fog, which is a lid on the sky either way.
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

    // Both battery glyph runs advance in tens from a base code point, but
    // neither run covers both ends: the charging one has no full glyph and the
    // discharging one has no empty glyph, so those two are named on their own.
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

    // A percentage reading swings between one and three digits, and letting
    // the pill resize with it shifts every pill to its left on each sample.
    // Three digits, so the number's right edge is in the same place at 1% as
    // at 100% and only the space between the icon and the number changes.
    // Measured rather than guessed so it tracks the scale factor.
    readonly property int percentWidth: Math.ceil(percentMetrics.width)

    TextMetrics {
        id: percentMetrics

        font.family: root.uiFont
        font.pixelSize: root.textSize
        font.weight: Font.Medium
        text: "100%"
    }

    // A plain count, so four digits and no percent sign. Measured rather than
    // borrowed from percentWidth, which reserves room for a symbol that a
    // count does not carry.
    readonly property int countWidth: Math.ceil(countMetrics.width)

    TextMetrics {
        id: countMetrics

        font.family: root.uiFont
        font.pixelSize: root.textSize
        font.weight: Font.Medium
        text: "9999"
    }

    // What separates a label's prefix from its reading.
    //
    // Not measured from the font. TextMetrics over a string that is only a
    // space reports zero -- Qt drops trailing whitespace when it lays the run
    // out -- so deriving this from the space glyph left no gap at all, and at
    // three digits, where the right-aligned reading fills its box and leaves no
    // slack, "CPU:" and "100%" touched. Both the colon and a leading 1 carry
    // almost no side bearing, so the separation has to come from here.
    readonly property int labelGap: root.px(5)

    function shorten(value: string, limit: int): string {
        return value.length > limit ? value.slice(0, limit - 1) + "…" : value;
    }

    // Cover art: a local file, or one of a few known cover-art hosts over TLS.
    //
    // mpris:artUrl is chosen by the player, and for a browser that means by
    // the page. Fetching it as given would turn any open tab into a beacon
    // running out of the shell and a way to reach an address on the local
    // network. But refusing every remote URL cost the thing itself: Spotify
    // publishes https://i.scdn.co/... and nothing else, so the island showed a
    // grey square for the one player most likely to be running.
    //
    // So the scheme and the host are both checked. https only, and the host
    // has to be one this file names -- a CDN that serves cover art and nothing
    // else, to a machine already talking to that service. An arbitrary host,
    // a private address, a plain-http URL and a data: blob are all still
    // refused, which is the part that mattered.
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

    // Where a load stops being ordinary. One threshold: see the note at the
    // CPU item in StatusItems for why the middle band went.
    readonly property real loadAlertFraction: 0.90
}
