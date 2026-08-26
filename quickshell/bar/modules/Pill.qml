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

    // Empty while the pill is showing something it actually read. Anything
    // else is the reason it is not, and the pill then draws itself hollow with
    // no number in it and says the reason instead of the tooltip.
    //
    // This is not "off" and it is not "absent". Off is a reading: the radio is
    // down, there is no alarm set, nothing is connected. Those keep the muted
    // face and a word for it, or set visible: false. This state is for when
    // the answer is not known, which no accent in the palette may claim.
    //
    // visible answers "does this thing exist". unknown answers "did we read
    // it". A pill that hides because it could not be read is telling the same
    // lie as a pill that shows 0%.
    property string unknown: ""

    // Internal. Here once so that adopting the mechanism at a call site costs
    // one binding rather than a conditional on every visual property.
    readonly property bool unread: root.unknown !== ""
    readonly property color face: root.unread ? Theme.bgAlt : root.fill
    readonly property color faceText: root.unread ? Theme.accentQuiet : root.textColor

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
    //
    // Darker for a face, lighter for the hollow one: Qt.darker on something
    // already near the background is not a visible press.
    color: click.pressed || menu.open
           ? (root.unread ? Qt.lighter(root.face, 1.6) : Qt.darker(root.face, 1.35))
           : root.face

    // An edge instead of a face. Every other pill in the bar is a solid chip
    // carrying dark text; inverting all three at once -- hollow, light text,
    // a drawn border -- is what makes an unread pill tellable from a muted
    // "off" one at a glance rather than on inspection. The border is inset, so
    // nothing reflows when a reading drops.
    border.width: root.unread ? Math.max(1, Theme.px(1)) : 0
    border.color: Theme.muted

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
        // The caller's tooltip is built out of the same values the label came
        // from, so showing it here would put back every number the face just
        // withheld -- "Charge 0%", "Capacity 0.0 of 53.0 Wh".
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
                Quickshell.execDetached(root.command);
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.pillGlyphGap

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            // BatteryGauge draws an arc whose length is the percentage, so an
            // icon component asserts a reading exactly as much as the label
            // does. Suppressing the label and leaving the gauge would have
            // drawn an empty ring beside an em dash and called it honest.
            active: root.iconComponent !== null && !root.unread
            visible: active
            sourceComponent: root.iconComponent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // One glyph replaces all of them. wifiIcon() returns the
            // radio-off bars, weatherIcon() a cloud, Bt.icon() a struck-through
            // symbol -- any of those drawn beside an em dash says "off" while
            // the pill is saying it does not know. Which pill this is stays
            // legible from its position and from the tooltip.
            visible: root.unread || (root.iconComponent === null && root.icon !== "")
            text: root.unread ? Theme.iconUnknown : root.icon
            font.family: Theme.iconFont
            font.pixelSize: root.iconPixelSize
            color: root.faceText
        }

        Text {
            id: labelText

            anchors.verticalCenter: parent.verticalCenter
            visible: root.unread || root.label !== ""
            width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            horizontalAlignment: root.labelWidth > 0 ? Text.AlignRight : Text.AlignLeft
            // The em dash keeps labelWidth's reservation, so a pill that loses
            // its reading does not resize and drag its neighbours along -- the
            // same reason labelWidth exists at all.
            text: root.unread ? "—" : root.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.textSize
            font.weight: Font.Medium
            color: root.faceText
        }
    }
}
