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
    // active on this machine (auto_monitors.sh disables the laptop panel while
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

    // Hyprland hands quickshell logical pixels, so fractional output scaling is
    // already applied. What is left to react to is the logical resolution: a
    // bar sized for 1440 rows looks oversized on a 1200-row panel.
    readonly property real autoScale: {
        const height = root.referenceScreen?.height ?? root.referenceHeight;
        const ratio = height / root.referenceHeight;
        return Math.max(0.82, Math.min(1.45, root.baseScale * Math.pow(ratio, 0.7)));
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
    readonly property int barHeight:   root.pillHeight + root.pillMargin * 2

    readonly property int chipWidth:   root.px(27)
    readonly property int chipSpacing: root.px(3)

    readonly property int mediaMaxWidth:  root.px(420)
    readonly property int mediaPadding:   root.px(12)
    readonly property int mediaItemGap:   root.px(7)

    readonly property int vizBarWidth:   Math.max(2, root.px(4))
    readonly property int vizBarSpacing: Math.max(1, root.px(2))
    readonly property int vizPadding:    root.px(5)

    readonly property int tooltipRadius:  root.px(10)
    readonly property int tooltipPadX:    root.px(12)
    readonly property int tooltipPadY:    root.px(8)
    readonly property int tooltipGap:     root.px(12)

    readonly property int windowChipPadding:  root.px(10)
    readonly property int windowTitleWidth:   root.px(260)
    readonly property int windowNameWidth:    root.px(130)

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

    readonly property color beige: "#ecf0c1"
    readonly property color ink:   "#0f111b"

    property bool barAtBottom: false

    readonly property string uiFont:   "Inter"
    readonly property string iconFont: "CaskaydiaCove Nerd Font Mono"

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
    // Chosen for silhouette, not just meaning: a square chip next to a
    // stack of cylinders reads apart at 21px, two chip glyphs do not.
    readonly property string iconCpu:       String.fromCodePoint(0xF4BC)
    readonly property string iconMemory:    String.fromCodePoint(0xF061A)
    readonly property string iconPlay:      String.fromCodePoint(0xF04B)
    readonly property string iconPause:     String.fromCodePoint(0xF04C)
    readonly property string iconNext:      String.fromCodePoint(0xF04AD)
    readonly property string iconPrev:      String.fromCodePoint(0xF04AE)
    readonly property string iconStop:      String.fromCodePoint(0xF04DB)
    readonly property string iconMusic:     String.fromCodePoint(0xF001)
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
    readonly property string iconClose:     String.fromCodePoint(0xF0159)
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

    function weatherIcon(code: int, day: bool): string {
        switch (true) {
        case code === 0:
            return String.fromCodePoint(day ? 0xF0599 : 0xF0594);
        case code === 1 || code === 2:
            return String.fromCodePoint(day ? 0xF0595 : 0xF067E);
        case code === 3:
            return String.fromCodePoint(0xF0590);
        case code === 45 || code === 48:
            return String.fromCodePoint(0xF0591);
        case code >= 51 && code <= 57:
            return String.fromCodePoint(0xF0597);
        case code >= 61 && code <= 65:
            return String.fromCodePoint(0xF0596);
        case code === 66 || code === 67:
            return String.fromCodePoint(0xF0F31);
        case code >= 71 && code <= 77:
            return String.fromCodePoint(0xF0598);
        case code >= 80 && code <= 82:
            return String.fromCodePoint(0xF0596);
        case code === 85 || code === 86:
            return String.fromCodePoint(0xF0598);
        case code === 95:
            return String.fromCodePoint(0xF0593);
        case code === 96 || code === 99:
            return String.fromCodePoint(0xF0592);
        default:
            return String.fromCodePoint(0xF0590);
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

    function batteryColor(percent: int, charging: bool): color {
        if (percent <= 15)
            return root.accentRed;
        if (percent <= 30)
            return root.accentAmber;
        if (charging)
            return root.accentGreen;
        return root.accentTeal;
    }

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

    function shorten(value: string, limit: int): string {
        return value.length > limit ? value.slice(0, limit - 1) + "…" : value;
    }

    // Load pills keep their own hue until the value is genuinely worth
    // noticing, so colour means "busy" rather than "this is the CPU one".
    function loadColor(fraction: real, base: color): color {
        if (fraction >= 0.85)
            return root.accentRed;
        if (fraction >= 0.65)
            return root.accentOrange;
        return base;
    }
}
