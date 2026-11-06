pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

// The lock screen's power button, bottom right, and the panel it opens (the
// user, 2026-11-05: sleep, shut down, sign out and the rest from the lock
// screen). The bar's session menu (PowerMenu.qml) gives the entries and
// their glyphs and the way each runs (lock.qml's power()).
//
// The button is its glyph alone, no disc behind it, brightening under the
// pointer; the panel's rows an icon and words in one colour, lit only by the
// row's faint fill (the user, 2026-11-06). Both coloured per pixel from what
// lies under them, as every surface and word of the lock (LockInk): the
// panel a LockSurface, its rows one layer of ink.
//
// Restart, shut down and sign out ask for a second click within three
// seconds: on a lock screen anyone at the keyboard can reach them, and a
// stray click must not end the session's work. Sleep goes at once; the
// session stays locked through it. Nothing here unlocks anything: the panel
// ends or pauses the session, it never opens it.
//
// It opens out of the button on the island's growth (Theme.islandGrowMs,
// OutCubic) and its rows follow a little after one another; it closes faster
// than it opens, as the island's swap does. Arrows and Enter move and choose
// while it is open, Escape closes it (LockScreen routes the keys here).
Item {
    id: root

    required property var screenRoot
    required property var lockRoot
    required property var under
    // Pixels per bar pixel: the button the bar's height, the panel the bar's
    // menus (PopupMenu's rows, words, icons and corners), all a little
    // larger.
    property real unit: 1

    function s(v: real): real {
        return v * root.unit;
    }
    readonly property real margin: root.s(28)
    // The button a quarter larger than the bar's sizes alone would make it
    // (the user, 2026-11-06: a little larger); the panel keeps the menus'.
    readonly property real buttonGrow: 1.25
    readonly property real buttonSize: root.s(Theme.barHeight * root.buttonGrow)

    readonly property var entries: [
        { id: "logout", label: "Sign out", confirm: "Click again to sign out", icon: Theme.iconLogout, ask: true },
        { id: "suspend", label: "Sleep", confirm: "", icon: Theme.iconSleep, ask: false },
        { id: "reboot", label: "Restart", confirm: "Click again to restart", icon: Theme.iconRestart, ask: true },
        { id: "poweroff", label: "Shut down", confirm: "Click again to shut down", icon: Theme.iconPower, ask: true }
    ]

    property bool open: false
    property int selected: -1
    property int armed: -1

    function toggle(): void {
        if (root.open)
            root.close();
        else {
            root.selected = -1;
            root.armed = -1;
            root.open = true;
        }
    }

    function close(): void {
        root.open = false;
        root.armed = -1;
    }

    function move(delta: int): void {
        const n = root.entries.length;
        root.selected = root.selected < 0 ? (delta > 0 ? 0 : n - 1) : (root.selected + delta + n) % n;
    }

    function choose(index: int): void {
        const entry = root.entries[index];
        if (!entry)
            return;
        root.selected = index;
        if (entry.ask && root.armed !== index) {
            root.armed = index;
            disarm.restart();
            return;
        }
        root.close();
        root.lockRoot.power(entry.id);
    }

    Timer {
        id: disarm

        interval: 3000
        onTriggered: root.armed = -1
    }

    // A click anywhere else closes the panel, and is spent on that.
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        visible: root.open
        onClicked: root.close()
    }

    // ---- the button --------------------------------------------------------
    // The glyph alone, a little dim at rest and full under the pointer or
    // while the panel is open, as the window's close button.
    Item {
        id: button

        width: root.buttonSize
        height: root.buttonSize
        x: root.screenRoot.crisp(root.width - width - root.margin)
        y: root.screenRoot.crisp(root.height - height - root.margin) + root.rise
        opacity: root.arrived * (buttonHover.hovered || root.open ? 1 : 0.72)
        scale: buttonPress.pressed ? 0.92 : 1

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Text {
            id: buttonGlyph

            anchors.centerIn: parent
            text: Theme.iconPower
            color: Theme.beige
            font.family: Theme.iconFont
            font.pixelSize: Math.max(1, root.s(Theme.statusIconSize * root.buttonGrow))
        }

        layer.enabled: true
        layer.smooth: true
        layer.effect: LockInk {
            target: button
            under: root.under
            screenItem: root.screenRoot
            haloSize: root.s(4)
        }

        HoverHandler {
            id: buttonHover

            cursorShape: Qt.PointingHandCursor
        }

        MouseArea {
            id: buttonPress

            anchors.fill: parent
            onClicked: root.toggle()
        }
    }

    // In a little after the lock has come in.
    property real rise: root.s(12)
    property real arrived: 0

    Component.onCompleted: arrive.start()

    SequentialAnimation {
        id: arrive

        PauseAnimation { duration: 160 }

        ParallelAnimation {
            NumberAnimation { target: root; property: "arrived"; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "rise"; to: 0; duration: 520; easing.type: Easing.OutCubic }
        }
    }

    // ---- the panel ---------------------------------------------------------
    readonly property real rowH: root.s(Theme.menuRowHeight)
    readonly property real pad: root.s(Theme.menuPad)
    readonly property real words: Math.max(1, root.s(Theme.menuItemTextSize))
    // A row: the icon in an icon's room an inset in, the words a gap after
    // it, room at the end.
    readonly property real discX: root.s(9)
    readonly property real discSize: root.s(Theme.menuIconSize)
    readonly property real wordsGap: root.s(12)
    readonly property real wordsEnd: root.s(14)

    TextMetrics {
        id: longest

        font.family: Theme.uiFont
        font.weight: Font.Medium
        font.pixelSize: root.words
        text: root.entries.reduce((a, e) => e.confirm.length > a.length ? e.confirm : a, "")
    }

    Item {
        id: panel

        // How far open, eased: everything in the panel follows this one.
        property real shown: 0

        NumberAnimation {
            id: grow

            target: panel
            property: "shown"
            to: 1
            duration: Theme.islandGrowMs
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: shrink

            target: panel
            property: "shown"
            to: 0
            duration: 170
            easing.type: Easing.InCubic
        }

        Connections {
            target: root

            function onOpenChanged() {
                (root.open ? shrink : grow).stop();
                (root.open ? grow : shrink).restart();
            }
        }

        // Wide enough for the longest second-click line, which a fixed
        // width cut short.
        width: Math.max(root.s(Theme.menuMinWidth), root.pad * 2 + root.discX + root.discSize + root.wordsGap + root.wordsEnd + longest.advanceWidth)
        height: root.entries.length * root.rowH + root.pad * 2
        x: button.x + button.width - width
        y: button.y - height - root.s(12) + (1 - panel.shown) * root.s(10)
        visible: panel.shown > 0.001
        opacity: panel.shown
        scale: 0.9 + 0.1 * panel.shown
        transformOrigin: Item.BottomRight

        // The grown island's soft shadow, as every surface the lock floats.
        layer.enabled: panel.visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.islandShadow
            shadowBlur: 1.0
            blurMax: Math.max(1, Math.round(root.s(Theme.islandShadowBlur)))
            shadowVerticalOffset: root.s(Theme.islandShadowOffset)
        }

        LockSurface {
            anchors.fill: parent
            under: root.under
            screenItem: root.screenRoot
            radius: root.s(Theme.menuRadius)
            edgeWidth: Math.max(1, root.s(1))
            // The panel grows and moves as one; its parts' own places do not.
            tick: Math.round(panel.shown * 50)

            // Clicks on the panel stay on it.
            MouseArea {
                anchors.fill: parent
            }
        }

        Column {
            id: rows

            x: root.pad
            y: root.pad
            width: panel.width - root.pad * 2

            layer.enabled: true
            layer.smooth: true
            layer.effect: LockInk {
                target: rows
                under: root.under
                screenItem: root.screenRoot
                tick: Math.round(panel.shown * 50)
            }

            Repeater {
                model: root.entries

                Item {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool lit: root.selected === row.index
                    readonly property bool asking: root.armed === row.index
                    // Each row a little after the one above it.
                    readonly property real own: Math.max(0, Math.min(1, panel.shown * 1.25 - row.index * 0.08))

                    width: parent.width
                    height: root.rowH
                    opacity: row.own
                    transform: Translate {
                        y: (1 - row.own) * root.s(6)
                    }

                    // The row's faint fill, lit or asking: the one change
                    // of brightness, in the ink like the rest.
                    Rectangle {
                        anchors.fill: parent
                        radius: root.s(Theme.menuRowRadius)
                        color: Qt.rgba(1, 1, 1, row.asking ? 0.12 : row.lit ? 0.07 : 0)

                        Behavior on color {
                            ColorAnimation { duration: 140 }
                        }
                    }

                    Text {
                        id: icon

                        anchors.verticalCenter: parent.verticalCenter
                        x: root.discX + (root.discSize - icon.implicitWidth) / 2
                        text: row.modelData.icon
                        color: Theme.beige
                        font.family: Theme.iconFont
                        font.pixelSize: Math.max(1, root.discSize * 0.68)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.discX + root.discSize + root.wordsGap
                        width: parent.width - x - root.s(10)
                        elide: Text.ElideRight
                        text: row.asking ? row.modelData.confirm : row.modelData.label
                        color: Theme.beige
                        font.family: Theme.uiFont
                        font.weight: Font.Medium
                        font.pixelSize: root.words
                    }

                    // The second click's time running out.
                    Rectangle {
                        visible: row.asking
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: root.s(5)
                        x: root.discX + root.discSize + root.wordsGap
                        height: Math.max(1, root.s(2))
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.55)
                        width: drain.left

                        property real full: parent.width - x - root.wordsEnd

                        QtObject {
                            id: drain

                            property real left: 0
                        }

                        NumberAnimation {
                            id: draining

                            target: drain
                            property: "left"
                            duration: disarm.interval
                        }

                        onVisibleChanged: {
                            if (visible) {
                                draining.from = full;
                                draining.to = 0;
                                draining.restart();
                            }
                        }
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: {
                            if (hovered)
                                root.selected = row.index;
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.choose(row.index)
                    }
                }
            }
        }
    }
}
