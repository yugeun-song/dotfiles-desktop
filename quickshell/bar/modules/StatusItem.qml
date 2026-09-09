import QtQuick
import Quickshell
import qs.services

// One entry in the right-hand status group.
//
// Pill without the face. A pill was a coloured chip; a status item is a glyph
// on the bar that takes colour only when the reading is worth interrupting
// for. Not a mode on Pill because nearly every line of Pill managed the face.
//
// The interface is deliberately Pill's, so the call sites moved across by
// deleting their fill lines.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string labelPrefix: ""
    property int labelWidth: 0
    property string tooltip: ""
    property Component iconComponent: null
    property var menuEntries: []
    property var command: null

    // The colour the glyph takes when it has something to say. Left at the
    // foreground, an item is just another readout; set to an accent, it is
    // the one thing on the bar that changed. Callers pass an accent only for
    // states worth that -- caps lock on, battery low, a load over its ceiling,
    // unread notifications -- and leave it alone otherwise.
    property color accent: Theme.fg

    // See Pill.unknown. The same distinction holds and for the same reason:
    // "off" is a reading and keeps the muted colour, "not read" is not and
    // draws the question-mark glyph instead of whatever the caller asked for.
    property string unknown: ""

    property bool interactive: root.command !== null || root.menuEntries.length > 0

    signal activated

    readonly property bool unread: root.unknown !== ""
    readonly property color glyphColor: root.unread ? Theme.muted : root.accent

    implicitHeight: Theme.barHeight
    implicitWidth: content.implicitWidth + Theme.menuItemPadX * 2

    // The hover highlight, and the press. macOS fills the item's box rather
    // than underlining it, so the target is the whole thing and not the text.
    // Inset vertically: a highlight that reached the bar's edges would touch
    // the hairline and read as a tab rather than as a hovered item.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Theme.px(3)
        anchors.bottomMargin: Theme.px(3)
        radius: Theme.menuItemRadius
        color: click.pressed || menu.open
               ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
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

    // Same rule as Pill: one surface at a time, and the tooltip stays away
    // until the pointer leaves once the menu has been used.
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

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.px(5)

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: root.iconComponent !== null && !root.unread
            visible: active
            sourceComponent: root.iconComponent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.unread || (root.iconComponent === null && root.icon !== "")
            text: root.unread ? Theme.iconUnknown : root.icon
            font.family: Theme.iconFont
            font.pixelSize: Theme.statusIconSize
            color: root.glyphColor
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.labelPrefix !== "" || root.unread || root.label !== ""
            spacing: Theme.labelGap

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.labelPrefix !== ""
                text: root.labelPrefix
                font.family: Theme.uiFont
                font.pixelSize: Theme.menuBarTextSize
                color: root.glyphColor
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.unread || root.label !== ""
                width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
                horizontalAlignment: root.labelWidth > 0 ? Text.AlignRight : Text.AlignLeft
                text: root.unread ? "—" : root.label
                // A status label carries names this machine did not choose: an
                // SSID, a Bluetooth device name, a window title. All are set by
                // someone else, and none of them may become markup.
                textFormat: Text.PlainText
                font.family: Theme.uiFont
                font.pixelSize: Theme.menuBarTextSize
                color: root.glyphColor
            }
        }
    }
}
