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
    // The scale is the reference output's, the 2560x1440 desk monitor these
    // sizes were tuned on; each window draws itself scaled by fit() for its
    // screen. Per-screen whole-pixel sizes would take every token out of this
    // singleton; a scaled scene graph keeps text vector-sharp.
    readonly property real baseScale: 1.12
    readonly property int referenceWidth: 2560
    readonly property int referenceHeight: 1440

    readonly property real scaleOverride: Number(Quickshell.env("BAR_SCALE") ?? 0)
    readonly property real scale: root.scaleOverride > 0 ? root.scaleOverride : root.baseScale

    // A window's factor on `screen`: the square root of its logical area over
    // the reference's, so a surface keeps its aspect and its share of the
    // screen (the share was asked for, not the millimetres). Floored at
    // minFit: below it the bar went unreadable (0.79 on the 1920x1200 panel,
    // an 11 px label); capped against a huge logical screen. Keep in step with
    // config/monitors.lua, which uses the same factor and bounds; the lock
    // screen keeps its own proportions (hypr/scripts/lock-fit.sh).
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
    // Menus at the bar's own text size, as the user's reference menus set
    // them (2026-10-27).
    readonly property int menuTextSize: root.menuBarTextSize
    // Nerd Font glyphs sit inside their em box; ask for icons larger than text.
    readonly property int iconSize:    root.px(21)
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
    // The badge's mark (SystemBadge), its ink 1.4 times as tall as the bar's
    // capitals: at 1.2, as the references draw it, the user found it small
    // (2026-10-27). In the icon font an Arch mark's ink is 0.557 of its em
    // box tall (Inter's capitals 0.727); a taller mark is brought to the same
    // height by its scale (services/Badge.qml).
    readonly property real badgeGlyphSize: 1.4 * 0.727 * root.menuBarTextSize / 0.557
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
    // Between a glyph and the text beside it, inside one item: about half the
    // text's em, so the pair reads as one item against the gap between items.
    readonly property int statusGlyphGap: root.px(5)
    // Hover highlight inset, proportional to the bar height.
    readonly property int barInset: Math.max(2, Math.round(root.barHeight * 0.14))

    // Characters of a window name, hence px(); the screen share is only a
    // ceiling (a pure share cut the laptop, where the name is set larger).
    readonly property int appNameWidth: Math.min(
        Math.round(root.referenceWidth * 0.16), root.px(228))
    readonly property int workspaceTextSize: root.px(12)
    // Same cell for one and two digits, so the row does not reflow at 10.
    readonly property int workspaceMinWidth: root.px(19)

    // Applications running with no window, at the left (TrayIcons.qml): as
    // tall as the status glyphs, and grey, since every other mark on the bar
    // is one colour and a coloured one reads as a status light. A saturation
    // of 0 gives the applications their own colours back.
    readonly property int trayIconSize: root.px(17)
    readonly property int trayIconPad: root.px(5)
    readonly property int trayIconGap: root.px(2)
    readonly property real trayIconSaturation: -1
    // How long an application has to end after Quit before its menu offers
    // Force quit.
    readonly property int trayQuitGraceMs: 3000

    // Opaque, so the contents keep their contrast whatever the wallpaper.
    readonly property color menuBarBg: root.bg
    readonly property color menuBarLine: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
    readonly property color menuHover:   Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

    // ---------------------------------------------------------------------
    // Floating surfaces (menus, the calendar, toasts, overlays) use the bar's
    // own colours so they read as the bar, not as another program; the island
    // has its own (below).
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
    // The media chip in the bar, the island, and the player it grows into.
    // ---------------------------------------------------------------------
    // The chip is an island (MediaChip.qml): a black pill set in the bar's
    // middle, clear of its edges, after the user's reference (2026-10-26: a
    // "Charging" pill in a menu bar), a capsule three quarters of the
    // bar's height. The cover is square, as far in from the pill's edges as
    // the pill is from the bar's.
    readonly property color islandColor:   "#000000"
    // As much bar above the pill as below: a pixel's difference the user saw
    // (2026-10-26).
    readonly property int islandInset:     root.px(4)
    readonly property int islandHeight:    root.barHeight - root.islandInset * 2
    readonly property int islandPadX:      root.px(10)
    readonly property int islandArtSize:   root.islandHeight - root.islandInset * 2
    readonly property int islandArtRadius: root.px(5)
    // No rim round the black, as in every reference the user gave
    // (2026-10-26): what sets the grown island off is a soft shadow, the
    // ground below darkened by about a fifth (21 to 27% there), fading over 10
    // to 40 px and further below than beside. The pill in the bar casts none,
    // as the reference's pill in its bar. 0.4 darkens the ground 28% at the
    // foot and 19% beside (measured; 0.5 made it 35%).
    readonly property color islandShadow:      Qt.rgba(0, 0, 0, 0.4)
    readonly property int islandShadowBlur:    root.px(26)
    readonly property int islandShadowOffset:  root.px(7)
    // The island's widths for everything but what plays, as they were (the
    // user, 2026-10-26: readouts, alerts, calls and shares keep them): at
    // most a fifth of the reference width, and one width for an event or a
    // part alone.
    readonly property int mediaChipWidth:      Math.round(root.referenceWidth * 0.20)
    readonly property int islandMinWidth:      root.px(330)
    // The music island's most, the same for every track: this share of the
    // bar's idle width (Bar.qml: what its groups leave, the app's name and
    // the clock taken at their widest), not a length of its own (the user,
    // 2026-10-26). Within it the island is as wide as what plays needs.
    // Half: about 550 px on the desk monitor, and on the laptop panel, whose
    // status group takes most of its right half, just short of where the
    // centred island would meet it.
    readonly property real islandIdleShare:    0.5
    // Its least, a share of the same idle width: a short title is spread to
    // it, not a stub.
    readonly property real islandLeastShare:   0.25
    // Its floor, a length and no share: whatever the shares give (a bar not
    // laid out yet, an untitled track), the cover and the meter at its fewest
    // bars keep their room (the user, 2026-10-26). Only the room off the
    // groups narrows it further.
    readonly property int islandItemGap:       root.px(8)
    readonly property int islandMeterFewest:   8
    readonly property int islandFloorWidth:    root.islandPadX * 2 + root.islandArtSize + root.islandItemGap
                                               + root.islandMeterFewest * root.vizBarWidth
                                               + (root.islandMeterFewest - 1) * root.vizBarSpacing

    // The island's own colours, read off the user's references pixel by pixel
    // (2026-10-26): the flat fill or glyph core of the reference named, the
    // mean where dithered; nearer the primaries than the bar's accents (OKLCH
    // chroma 0.13-0.23 against 0.10-0.16). Text white and grey, as there.
    readonly property color islandRed:     "#fa3532"  // the recording pill; the call's decline
    readonly property color islandGreen:   "#37c058"  // the earbuds' ring; the call's accept
    readonly property color islandBlue:    "#37a3de"  // "Settings" in the mobile data alert
    readonly property color islandMint:    "#01fea3"  // the scooter's range bar
    readonly property color islandYellow:  "#fcdc39"  // the scooter's unlock button
    readonly property color islandText:    "#ffffff"
    readonly property color islandSubtext: "#a4a4a9"  // "Connected" under the earbuds
    // Button fills: the alert's OK, and the scooter's grey buttons, which
    // also serve for what cannot be used.
    readonly property color islandFill:    "#2c2c2d"
    readonly property color islandFillHigh: "#3f3f3f"
    // Each colour's quieter companion, on its own RGB vector as the user
    // asked ("a similar colour vector, only fainter"): the recording pill's
    // dots not yet recorded are its red times exactly 0.40 (#641514), the
    // references' other pairs 0.23 to 0.47. For tracks, a meter at rest, a
    // battery's cell; multiplied in the encoded values, as they were drawn.
    readonly property real islandDimFactor: 0.40
    // Deeper still behind a glyph of the colour, as the scooter's close
    // button is its green times 0.23: the island's tinted buttons.
    readonly property real islandTintFactor: 0.23

    function islandDim(c: color): color {
        return Qt.rgba(c.r * root.islandDimFactor, c.g * root.islandDimFactor,
                       c.b * root.islandDimFactor, c.a);
    }

    function islandTint(c: color): color {
        return Qt.rgba(c.r * root.islandTintFactor, c.g * root.islandTintFactor,
                       c.b * root.islandTintFactor, c.a);
    }

    // How long something on the island has gone on (a share, a call, a
    // recording), as m:ss, and h:mm:ss past an hour.
    function clockText(ms: real): string {
        const s = Math.max(0, Math.floor(ms / 1000));
        const pad = n => String(n).padStart(2, "0");
        const h = Math.floor(s / 3600);
        return h > 0 ? `${h}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}` : `${Math.floor(s / 60)}:${pad(s % 60)}`;
    }
    // The grown island (MediaPopup.qml), hung from the screen's top edge as a
    // notch is: its flares into that edge, its lower corners, and how far
    // into the growth the pill reaches the edge.
    readonly property int islandEarRadius:   root.px(10)
    readonly property int islandPanelRadius: root.px(22)
    readonly property real islandAttachAt:   0.3
    // How quickly what the pill holds leaves before the player takes it over,
    // and comes back after; short, since the growth waits on it (the user,
    // 2026-10-26: the growth read slow).
    readonly property int islandHandMs:      60
    // How long a pause or a blank title must last before the island takes it
    // for the end (services/Media.qml): a seek or a change of track can show
    // either for a moment.
    readonly property int mediaGapMs:        1500
    // The system's events on the island (services/Island.qml): how long a
    // readout stays after the last change and an alert stays, a level's bar,
    // and a battery's cell.
    readonly property int islandReadoutMs:   1400
    readonly property int islandAlertMs:     2600
    readonly property int islandLevelWidth:  root.px(64)
    readonly property int islandLevelHeight: Math.max(3, root.px(4))
    readonly property int islandCellWidth:   root.px(22)
    readonly property int islandCellHeight:  root.px(11)
    // A Bluetooth device's name, at most, before it is cut.
    readonly property int islandEventTextMax: root.px(180)
    // The meter's share of the island's widest row (MediaChip.meterBars),
    // its 22 bars of the 558 px row in the user's capture (2026-10-26), so a
    // long title and the meter keep their proportions on any screen.
    readonly property real islandMeterShare: 0.194
    // How the island moves, after the user's phone references (2026-10-25):
    // the pill and its parts open on a spring's small overshoot (OutBack at
    // this amplitude goes 4.5% past), the parts shut quicker without one.
    readonly property int islandOpenMs:     480
    readonly property int islandShutMs:     300
    readonly property real islandOvershoot: 1.1
    // The grown island grows and shrinks as the notification panel opens,
    // OutCubic at its speed (the user, 2026-10-26): on the parts' curve,
    // which starts gently, it read slow.
    readonly property int islandGrowMs:     root.notifEnterMs
    // The pill comes and goes through a point, as the user asked (2026-10-26:
    // a black hole): a point grows into a dot the pill's height (islandDotAt
    // of the way) that stretches into the pill on the spring above. Going,
    // it sinks a little at once (to islandSink), then is drawn into its
    // middle faster and faster.
    readonly property real islandDotAt:      0.4
    readonly property real islandSink:       0.86
    readonly property int islandSinkMs:      110
    readonly property int islandPlungeMs:    320
    // A screen share on the island (services/ScreenShare.qml): a red dot, who
    // and how long; shareGap parts the island's parts wider than their items,
    // as a phone sets a second activity. A screencopy counts once it has
    // lasted shareLastsMs; a screenshot's ends half a second after its frame.
    readonly property int shareLastsMs:  2000
    readonly property int shareDotSize:  root.px(8)
    readonly property int shareIconSize: root.trayIconSize
    readonly property int shareGap:      root.px(16)
    // The calls and OBS on the grown island (IslandActivities.qml): a row
    // each, icon, two lines and round buttons, as the references have them.
    readonly property int islandRowHeight:  root.px(44)
    readonly property int islandRowIcon:    root.px(32)
    readonly property int islandButtonSize: root.px(34)
    readonly property int islandRowGap:     root.px(12)

    // The player the island grows into (MediaPopup.qml, MediaPlayer.qml), as
    // the user asked (2026-10-25). Wide and shallow: a squarer card left more
    // space above and below. The lock screen's card is this one scaled
    // (hypr/scripts/lock-media.py, the user, 2026-10-26): keep the two in step.
    readonly property int mediaCardWidth:  root.px(540)
    // No height token: popups are content plus popupPad on all four sides.
    // Shared with the calendar.
    readonly property int popupPad: root.px(18)

    readonly property int mediaArtSize:   root.px(52)
    // The waveform takes what the names leave of the top row, right after
    // them (the user, 2026-10-25: further left and wider), at least this.
    readonly property int mediaWaveMin:   root.px(150)
    readonly property int mediaTitleSize: root.px(15)
    readonly property int mediaSubSize:   root.px(12)
    readonly property int mediaTimeSize:  root.px(11)
    readonly property int mediaProgressHeight: root.px(14)
    // Thin, as in the Spotify player the card follows; the knob that appears
    // on hover is what the pointer aims at.
    readonly property int mediaTrackHeight: Math.max(3, root.px(4))
    readonly property int mediaKnobSize:    root.px(12)

    // Graded: play-pause a filled disc, skip either side, shuffle and repeat
    // smallest at the ends; close together, each in a cell wider than its
    // glyph so the gaps between them still click.
    readonly property int mediaDiscSize:    root.px(36)
    // The drawn play and pause mark, about a third of the disc as in Spotify's.
    readonly property int mediaDiscGlyph:   root.px(13)
    readonly property int mediaControlSkip: root.px(24)
    readonly property int mediaControlEdge: root.px(21)
    readonly property int mediaControlCell: root.px(32)
    readonly property int mediaControlGap:  root.px(18)

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

    // Thin bars at a fine pitch: the player card's waveform is as many of
    // cava's bands as fit its width (cava.conf).
    readonly property int vizBarWidth:   Math.max(2, root.px(3))
    readonly property int vizBarSpacing: Math.max(1, root.px(2))

    // Dropdown menus (PopupMenu and its MenuRow, BadgePicker), on the
    // proportions of the reference menus the user sent (2026-10-27),
    // measured in the height of their capitals, c (Inter's are 0.727 em).
    // The roomier set, the user's pick over the denser one (rows 2.39c
    // apart, 1.2c to 2c of padding): rows 3.7c apart, a separator 1.58c; the
    // rows, and so a lit row, 0.8c in from all four edges; inside a row the
    // content 1.6c in from either side, an icon 1.38c tall leading its label
    // by 1.54c; separators 2c short of either edge; corners 2.2c. Also 0.24
    // em under the bar, at least 10 em wide, and the row under the pointer in
    // the accent, as the launcher's.
    readonly property real menuCap:            0.727 * root.menuTextSize
    // A menu's words a step smaller than the measure, at the bar's readouts'
    // size: in rows this roomy they read large at its own (the user,
    // 2026-10-27, keeping the room). The badge's picker keeps the measure's,
    // as the user then asked it be left.
    readonly property int menuItemTextSize:    root.statusTextSize
    readonly property int menuGap:             Math.round(0.24 * root.menuTextSize)
    readonly property int menuRowHeight:       Math.round(3.7 * root.menuCap)
    readonly property int menuSeparatorHeight: Math.round(1.58 * root.menuCap)
    readonly property int menuPad:             Math.round(0.8 * root.menuCap)
    readonly property int menuRowPad:          Math.round(1.6 * root.menuCap)
    readonly property int menuRuleInset:       Math.round(2 * root.menuCap)
    readonly property int menuRadius:          Math.round(2.2 * root.menuCap)
    readonly property int menuRowRadius:       root.menuRadius - root.menuPad
    readonly property int menuDetailGap:       Math.round(2.4 * root.menuTextSize)
    readonly property int menuMinWidth:        10 * root.menuTextSize
    // The font's Mono icons are 0.586 em wide and about as tall, ink to
    // both sides.
    readonly property int menuIconSize:        Math.round(1.38 * root.menuCap / 0.586)
    readonly property int menuLeadWidth:       Math.round((1.38 + 1.54) * root.menuCap)
    readonly property color menuHighlight:     root.accentIndigo
    readonly property color menuHighlightText: root.ink

    readonly property int windowChipPadding:  root.px(10)

    // Toasts, and the history's cards drawn alike (NotificationCentre.qml;
    // the user, 2026-10-25), follow the model banner they chose, measured in
    // its em: 25.56 wide, corners 1.19, baselines 1.185 apart in the menu
    // bar's text size, 0.458 bar heights under the bar; ink 1 em in from the
    // left and under the top, the last baseline 1.148 em over the bottom.
    // From the text size, not px(), whose rounding pulls them apart. Paddings
    // are to line boxes (baseline 0.97 em down), set from a render so the ink
    // lands there; tests/e2e/run.sh measures it as the model was.
    readonly property int notifTextSize:    root.menuBarTextSize
    readonly property int notifLineHeight:  Math.round(1.185 * root.notifTextSize)
    readonly property int notifWidth:       Math.round(25.56 * root.notifTextSize)
    readonly property int notifRadius:      Math.round(1.19 * root.notifTextSize)
    readonly property int notifPad:         Math.round(0.94 * root.notifTextSize)
    readonly property int notifPadTop:      Math.round(0.73 * root.notifTextSize)
    readonly property int notifPadBottom:   Math.round(0.95 * root.notifTextSize)
    readonly property int notifBarGap:      Math.round(0.458 * root.barHeight)
    readonly property int notifStackGap:    root.px(8)
    // A critical one's red border, its only mark.
    readonly property int notifBorder:      Math.max(2, root.px(2))
    // How a toast moves, and the history panel as it does (the user,
    // 2026-10-26): in from the screen's edge, out by it a little faster, the
    // room a card left closing after it, a swipe let go short springing back.
    // Clearing the history sends its cards off one after another.
    readonly property int notifEnterMs:        260
    readonly property int notifLeaveMs:        220
    readonly property int notifCollapseMs:     150
    readonly property int notifSpringMs:       180
    readonly property int notifSweepStaggerMs: 35

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

    // ---------------------------------------------------------------------
    // The key overlay (modules/KeyOverlay.qml): a strip of fixed size.
    // ---------------------------------------------------------------------
    // Five caps of ordinary width with their gaps; a wider chord clips the
    // oldest, which is on its way out.
    readonly property int keysWidth:       root.px(600)
    // In from the corner: at the toasts' edge margin the caps read as
    // pressed against the bezel.
    readonly property int keysMarginRight: root.px(64)
    readonly property int keysSlideMs:     140

    // ---------------------------------------------------------------------
    // The screensaver (modules/ScreensaverDpms.qml): black, then off.
    // ---------------------------------------------------------------------
    // How often the saver asks again about what changes without an event:
    // an idle inhibitor going away, a dark display turned on by something
    // else.
    readonly property int saverRecheckMs: 60000
    // A display's state read this soon after asking for it to go dark may
    // predate the request, so it is not taken as the display woken.
    readonly property int saverSettleMs: 5000

    // The unlock's sweep (UnlockSweep.qml): how often the compositor is asked
    // whether the lock is up, how often the lock screen is captured meanwhile,
    // and how long the lock screen takes to leave by the top: a swipe let go
    // (the user, 2026-10-26: a phone's), at the island's pace since the
    // user found 420 ms slow (2026-10-27).
    readonly property int unlockConfirmMs: 500
    readonly property int unlockCaptureMs: 1000
    readonly property int unlockSweepMs:   root.notifEnterMs

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

    // For Hangul where a line's height matters (the key overlay's caps).
    // Pretendard is what fontconfig/local.conf falls back to for it.
    readonly property string hangulFont: root.firstInstalled(
        ["Pretendard", "Noto Sans CJK KR", "Noto Sans KR", "Source Han Sans K", "NanumGothic"], root.uiFont)

    // Key and modifier symbols, used by the key overlay (via KeyFeed).
    // Super is a diamond: U+2318, the place of interest sign, as some
    // keyboards print it on their command modifier.
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
    // md-camera_off rather than the newer md-webcam_off: every Nerd Font 3
    // carries it.
    readonly property string iconCameraOff: String.fromCodePoint(0xF05DF)

    // Rendered and checked, not just found in the cmap (F0A21 exists but is a
    // window grid). One bell for every state: variants repeat the colour and
    // count, and a struck-out bell reads as "notifications off".
    readonly property string iconBell:      String.fromCodePoint(0xF009A)
    readonly property string iconClock:     String.fromCodePoint(0xF0150)
    readonly property string iconClearAll:  String.fromCodePoint(0xF0A79)
    readonly property string iconBatteryAlert: String.fromCodePoint(0xF0083)
    readonly property string iconPlug:         String.fromCodePoint(0xF06A5)
    // The island's charging events, as the references draw charging.
    readonly property string iconBolt:         String.fromCodePoint(0xF140B)
    // The island's recordings: md-record, md-broadcast, md-open_in_new (the
    // program's window), names read from the cmap.
    readonly property string iconRecord:       String.fromCodePoint(0xF044A)
    readonly property string iconBroadcast:    String.fromCodePoint(0xF1720)
    readonly property string iconOpenWindow:   String.fromCodePoint(0xF03CC)
    // md-pause and md-play for the island's round buttons: the transport's
    // FontAwesome pair fills under half its box and came out small there.
    readonly property string iconPauseMd:      String.fromCodePoint(0xF03E4)
    readonly property string iconPlayMd:       String.fromCodePoint(0xF040A)

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

    // "" while the reading is fresh, else why it is not.
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

    function volumeIcon(percent: int, muted: bool): string {
        if (muted || percent <= 0)
            return root.iconVolumeOff;
        if (percent < 34)
            return root.iconVolumeLow;
        if (percent < 67)
            return root.iconVolumeMed;
        return root.iconVolume;
    }

    // Discharging steps by ten, from the outline (F008E) through F007A-F0082
    // to the full cell (F0079). Charging is one glyph, the bolt inside a full
    // cell (F0084): the font's charging run is not contiguous and, fitted to
    // one column, draws at half the height, so the glyph shrank whenever the
    // cable went in. The value beside it carries the level.
    function batteryIcon(percent: int, charging: bool): string {
        if (charging)
            return String.fromCodePoint(0xF0084);
        const step = Math.max(0, Math.min(10, Math.round(percent / 10)));
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

    // The widest a reading gets: "100%" in bold tabular figures. A value is
    // right-aligned in it, padded to three digits (__5%, _55%, 100%, the
    // user's layout), so its item never changes width; the gaps between
    // items hold and nothing beside it moves.
    readonly property int percentWidth: Math.ceil(percentMetrics.width)

    TextMetrics {
        id: percentMetrics

        font.family: root.uiFont
        font.pixelSize: root.statusTextSize
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
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
        // The host as the Image that fetches it will see it: QML's URL is
        // QUrl. Cut by hand at the first slash, "https://evil.example?@i.scdn.co/x"
        // passed while QUrl connected to evil.example.
        let parsed;
        try {
            parsed = new URL(url);
        } catch (e) {
            return "";
        }
        if (parsed.protocol !== "https:")
            return "";
        return root.artHosts.indexOf(parsed.hostname.toLowerCase()) !== -1 ? url : "";
    }

    // Single alert threshold for CPU and memory load.
    readonly property real loadAlertFraction: 0.90
}
