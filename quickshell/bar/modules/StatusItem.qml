import QtQuick
import Quickshell
import qs.services

// One entry in the right-hand status group: a glyph, alone or before a value,
// that takes colour only when the reading is worth interrupting for.
Item {
    id: root

    property string icon: ""
    // For glyphs the font draws small in their box; see Theme.statusIconBoost.
    property real iconScale: 1.0
    property string label: ""
    property string labelPrefix: ""
    property int labelWidth: 0
    property Component iconComponent: null
    property var menuEntries: []
    property var command: null

    // Glyph colour. Callers set an accent only for states worth attention
    // (load or battery past its limit) or a dimmed tone for "off".
    property color accent: Theme.fg

    // A filled pill behind the glyph, reserved for "switched on right now"
    // (a ringing alarm); colour alone means "this reading moved".
    property bool active: false
    property color activeFill: Theme.accentSaffron

    // Bolds the value; the colour comes from accent.
    property bool alert: false

    // Non-empty = no reading. Distinct from "off", which is a reading: this
    // draws the unknown glyph instead of the caller's.
    property string unknown: ""

    property bool interactive: root.command !== null || root.menuEntries.length > 0
    // Lit as pressed while a panel of the caller's own is open (the weather's
    // place panel), as the menu below keeps it lit.
    property bool held: false
    // Something opens while the pointer is on the item (the clock's month).
    property bool hoverable: false
    // Lit and pointed at: a click or the pointer acts here.
    readonly property bool actionable: root.interactive || root.hoverable

    signal activated

    // Lets a caller keep a hover popup open while on the item (the clock).
    readonly property alias hovered: hover.hovered

    readonly property bool unread: root.unknown !== ""
    readonly property bool filled: root.active && !root.unread
    readonly property color glyphColor: root.unread ? Theme.muted
                                      : root.filled ? Theme.readableOn(root.activeFill)
                                                    : root.accent

    implicitHeight: Theme.barHeight
    implicitWidth: content.implicitWidth + Theme.menuItemPadX * 2

    // Press, on-state fill, hover. Only an actionable item lights up, as the
    // user chose: press where a click acts, hover where a click or the
    // pointer does. On a plain readout either promised a button. Fully
    // rounded when filled: a pill reads as a badge, a rounded rectangle as a
    // button.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Theme.barInset
        anchors.bottomMargin: Theme.barInset
        radius: root.filled ? height / 2 : Theme.menuItemRadius
        color: (click.pressed && root.interactive) || menu.open || root.held
               ? (root.filled ? Qt.darker(root.activeFill, 1.25)
                              : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20))
               : root.filled ? root.activeFill
               : hover.hovered && root.actionable ? Theme.menuHover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        id: hover
    }

    PopupMenu {
        id: menu

        anchorItem: root
        entries: root.menuEntries
    }

    MouseArea {
        id: click

        anchors.fill: parent
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.menuEntries.length > 0) {
                menu.toggle();
                return;
            }
            root.activated();
            if (root.command !== null)
                Apps.open(root.command);
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.statusGlyphGap

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: root.iconComponent !== null && !root.unread
            visible: active
            sourceComponent: root.iconComponent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.unread || (root.iconComponent === null && root.icon !== "")
            height: Theme.barLineHeight
            verticalAlignment: Text.AlignVCenter
            text: root.unread ? Theme.iconUnknown : root.icon
            font.family: Theme.iconFont
            font.pixelSize: Math.round(Theme.statusIconSize * root.iconScale)
            color: root.glyphColor
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.labelPrefix !== "" || root.unread || root.label !== ""
            spacing: Theme.labelGap

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.labelPrefix !== ""
                height: Theme.barLineHeight
                verticalAlignment: Text.AlignVCenter
                text: root.labelPrefix
                font.family: Theme.uiFont
                font.pixelSize: Theme.statusTextSize
                color: root.glyphColor
            }

            // A value given a width is right-aligned in it in tabular figures,
            // padded to the widest reading (Theme.percentWidth), so the item
            // never changes width and the gaps between items hold; the slack
            // stays inside the item. Bold on alert, with the accent, as one
            // warning.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.unread || root.label !== ""
                width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
                height: Theme.barLineHeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: root.labelWidth > 0 ? Text.AlignRight : Text.AlignLeft
                text: root.unread ? "—" : root.label
                // Labels can carry foreign strings; never interpret as markup.
                textFormat: Text.PlainText
                font.family: Theme.uiFont
                font.pixelSize: Theme.statusTextSize
                font.weight: root.alert ? Font.Bold : Font.Normal
                font.features: root.labelWidth > 0 ? ({ "tnum": 1 }) : ({})
                color: root.glyphColor
            }
        }
    }
}
