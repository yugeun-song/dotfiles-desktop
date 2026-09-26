import QtQuick
import Quickshell
import qs.services

// One entry in the right-hand status group: a glyph (or caption and value)
// that takes colour only when the reading is worth interrupting for.
Item {
    id: root

    property string icon: ""
    // For glyphs the font draws small in their box; see Theme.statusIconBoost.
    property real iconScale: 1.0
    property string label: ""
    property string labelPrefix: ""
    property int labelWidth: 0

    // Non-empty switches to the caption-then-value form ("CPU 7%").
    property string caption: ""
    property string tooltip: ""
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

    // Bolds caption and value together; the colour comes from accent.
    property bool alert: false

    // Non-empty = no reading (the text says why). Distinct from "off", which is
    // a reading: this draws the unknown glyph instead of the caller's.
    property string unknown: ""

    property bool interactive: root.command !== null || root.menuEntries.length > 0

    signal activated

    // Lets a caller keep a hover popup open while on the item (the clock).
    readonly property alias hovered: hover.hovered

    readonly property bool unread: root.unknown !== ""
    readonly property bool filled: root.active && !root.unread
    readonly property color glyphColor: root.unread ? Theme.muted
                                      : root.filled ? Theme.readableOn(root.activeFill)
                                                    : root.accent

    implicitHeight: Theme.barHeight
    implicitWidth: (root.caption !== "" ? stack.implicitWidth : content.implicitWidth) + Theme.menuItemPadX * 2

    // Press, on-state fill, hover. Fully rounded when filled: a pill reads as a
    // badge, a rounded rectangle as a button.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Theme.barInset
        anchors.bottomMargin: Theme.barInset
        radius: root.filled ? height / 2 : Theme.menuItemRadius
        color: click.pressed || menu.open
               ? (root.filled ? Qt.darker(root.activeFill, 1.25)
                              : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20))
               : root.filled ? root.activeFill
               : hover.hovered ? Theme.menuHover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }
    }

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (!hover.hovered)
                root.tooltipSuppressed = false;
        }
    }

    // One surface at a time: after the menu is used, the tooltip waits until
    // the pointer leaves.
    property bool tooltipSuppressed: false

    Tooltip {
        id: tip

        anchorItem: root
        active: hover.hovered && !menu.open && !click.pressed && !root.tooltipSuppressed
        immediate: menu.open || click.pressed
        text: root.unread ? `No reading\n${root.unknown}` : root.tooltip
    }

    PopupMenu {
        id: menu

        anchorItem: root
        entries: root.menuEntries

        onOpened: {
            tip.shown = false;
            root.tooltipSuppressed = true;
        }

        onClosed: root.tooltipSuppressed = true
    }

    MouseArea {
        id: click

        anchors.fill: parent
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: {
            tip.shown = false;
            root.tooltipSuppressed = true;
        }
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

    // Captioned form. Fixed value width so 9% -> 10% does not shift the row.
    Row {
        id: stack

        anchors.centerIn: parent
        visible: root.caption !== ""
        spacing: Theme.statusCaptionGap

        // Caption and value share the plain label's size, weight and colour,
        // so the three readouts match the words beside them; position alone
        // tells the caption from the value. Bold on alert, as one warning.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.statusCaptionWidth
            height: Theme.barLineHeight
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: root.caption
            font.family: Theme.uiFont
            font.pixelSize: Theme.menuBarTextSize
            font.weight: root.alert ? Font.Bold : Font.Normal
            color: root.glyphColor
        }

        // Left-aligned: the caption gap must stay constant; slack goes outside.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            height: Theme.barLineHeight
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            text: root.unread ? "—" : root.label
            textFormat: Text.PlainText
            font.family: Theme.uiFont
            font.pixelSize: Theme.menuBarTextSize
            font.weight: root.alert ? Font.Bold : Font.Normal
            color: root.glyphColor
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        visible: root.caption === ""
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
                font.pixelSize: Theme.menuBarTextSize
                color: root.glyphColor
            }

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
                font.pixelSize: Theme.menuBarTextSize
                color: root.glyphColor
            }
        }
    }
}
