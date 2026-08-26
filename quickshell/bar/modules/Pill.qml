import QtQuick
import Quickshell
import qs.services

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property color fill: Theme.muted
    property color textColor: Theme.ink
    property int horizontalPadding: Theme.pillPadding
    property string tooltip: ""
    property int iconPixelSize: Theme.iconSize
    // Width to hold open for the label, whatever it currently reads. A
    // percentage swings between one and three digits; without this the pill
    // resizes on every sample and drags its neighbours along.
    //
    // The label is right-aligned inside it, so the number's right edge and
    // the icon both stay put and the missing digits show up as space between
    // them, the way a right-aligned column of figures reads on paper.
    property int labelWidth: 0
    property Component iconComponent: null
    property var menuEntries: []
    property var command: null

    // Whether a click does anything, which decides the cursor. The pill can
    // derive this for the two mechanisms it implements itself, but a pill that
    // acts through onActivated is invisible to it -- QML gives no way to ask
    // whether a signal has a handler -- so those set it themselves. Leaving it
    // derived is what made the notification pill keep an arrow cursor.
    property bool interactive: root.command !== null || root.menuEntries.length > 0

    signal activated

    implicitHeight: Theme.pillHeight
    implicitWidth: content.implicitWidth + root.horizontalPadding * 2
    radius: Theme.pillRadius

    // Pressed and open both read as darker. Without this the only thing that
    // changed on a click was a second surface appearing somewhere else, which
    // is why clicking felt like it had not registered.
    color: click.pressed || menu.open ? Qt.darker(root.fill, 1.35) : root.fill

    Behavior on color {
        ColorAnimation {
            duration: 90
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (!hover.hovered)
                root.tooltipSuppressed = false;
        }
    }

    // Only one of the two surfaces is ever up, and the rule that decides is
    // here rather than split across two timers. Once the menu has been used,
    // the tooltip stays away until the pointer actually leaves the pill.
    // A timer instead of a rule was what made the boundary feel arbitrary:
    // the tooltip would come back on its own while the pointer had not moved.
    property bool tooltipSuppressed: false

    Tooltip {
        id: tip

        anchorItem: root
        active: hover.hovered && !menu.open && !click.pressed && !root.tooltipSuppressed
        immediate: menu.open || click.pressed
        text: root.tooltip
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
                Quickshell.execDetached(root.command);
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.pillGlyphGap

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: root.iconComponent !== null
            visible: active
            sourceComponent: root.iconComponent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconComponent === null && root.icon !== ""
            text: root.icon
            font.family: Theme.iconFont
            font.pixelSize: root.iconPixelSize
            color: root.textColor
        }

        Text {
            id: labelText

            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            horizontalAlignment: root.labelWidth > 0 ? Text.AlignRight : Text.AlignLeft
            text: root.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.textSize
            font.weight: Font.Medium
            color: root.textColor
        }
    }
}
