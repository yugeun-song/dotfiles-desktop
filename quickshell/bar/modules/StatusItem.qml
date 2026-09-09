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
    // A multiplier on statusIconSize, for glyphs the font draws small inside
    // their box. See Theme.statusIconBoost.
    property real iconScale: 1.0
    property string label: ""
    property string labelPrefix: ""
    property int labelWidth: 0

    // A word in place of a glyph: "CPU 7%" rather than a die and a number.
    // Set it and the item is caption-then-value; leave it empty and the item
    // is the glyph-and-label row everything else uses.
    property string caption: ""
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

    // A filled pill behind the glyph, the way macOS marks a microphone that is
    // live. Reserved for states that are ON rather than merely notable: the
    // input method in Hangul, caps lock, an alarm going off. A colour says
    // "this reading moved"; a filled pill says "this is switched on", and
    // spending the second on the first leaves nothing for the second.
    property bool active: false
    property color activeFill: Theme.accentSaffron

    // A reading past its limit. Sets the weight of both lines, so a captioned
    // item goes bold as a pair rather than having its number thicken away from
    // its label. The colour is the caller's to set through accent.
    property bool alert: false

    // See Pill.unknown. The same distinction holds and for the same reason:
    // "off" is a reading and keeps the muted colour, "not read" is not and
    // draws the question-mark glyph instead of whatever the caller asked for.
    property string unknown: ""

    property bool interactive: root.command !== null || root.menuEntries.length > 0

    signal activated

    // Exposed so a caller can hang a popup off this item and keep it open
    // while the pointer is still on it. See the clock in StatusItems.
    readonly property alias hovered: hover.hovered

    readonly property bool unread: root.unknown !== ""
    readonly property bool filled: root.active && !root.unread
    readonly property color glyphColor: root.unread ? Theme.muted
                                      : root.filled ? Theme.readableOn(root.activeFill)
                                                    : root.accent

    implicitHeight: Theme.barHeight
    implicitWidth: (root.caption !== "" ? stack.implicitWidth : content.implicitWidth) + Theme.menuItemPadX * 2

    // The hover highlight, the press, and the on-state fill, in that order of
    // precedence. Inset vertically so it does not touch the hairline, and
    // fully rounded when it is carrying a state rather than a hover: a pill
    // reads as a badge and a rounded rectangle reads as a button.
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

    // The captioned form: the word dimmed so the number is what is read, and
    // the number in a fixed width so a load crossing 9 to 10 percent does not
    // shift every item to its left.
    Row {
        id: stack

        anchors.centerIn: parent
        visible: root.caption !== ""
        spacing: Theme.statusCaptionGap

        // The same family, size and weight as the value beside it, and the
        // same box: only the colour differs. A heavier weight was the first
        // attempt and it changed the glyph heights enough that the two lines
        // did not sit level, which is the one thing a caption must not do.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.statusCaptionWidth
            height: Theme.barLineHeight
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: root.caption
            font.family: Theme.uiFont
            font.pixelSize: Theme.statusCaptionSize
            font.weight: root.alert ? Font.Bold : Font.Medium
            color: Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.50)
        }

        // Left-aligned inside a fixed width, not right-aligned. Right kept the
        // item's outer edge still, but it moved the number towards the caption
        // as the number grew: "CPU 6%" sat with a gap and "BAT 100%" ran into
        // its own label. The gap after the caption is the one that has to be
        // constant, because it is the one the eye reads as spacing; the slack
        // belongs on the far side where nothing is.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            height: Theme.barLineHeight
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            text: root.unread ? "—" : root.label
            textFormat: Text.PlainText
            font.family: Theme.uiFont
            font.pixelSize: Theme.statusValueSize
            font.weight: root.alert ? Font.Bold : Font.Medium
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
