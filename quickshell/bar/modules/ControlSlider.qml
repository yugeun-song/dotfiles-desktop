import QtQuick
import qs.services

// A level of the control centre, as GNOME's quick settings draw one: its
// glyph, itself a button where the level has an off (the sound's mute), the
// track, and a chevron where devices stand behind it. While dragged, the
// knob follows the pointer rather than the service: a write's echo comes
// back a moment later and pulled the knob back under it.
Item {
    id: root

    property string icon: ""
    // 0..1; below 0 while nothing has been read, which draws an empty track.
    property real value: 0
    property bool usable: true
    property bool iconClickable: false
    property bool expandable: false
    property bool expanded: false

    signal moved(real value)
    signal iconClicked
    signal expandRequested

    implicitHeight: Theme.controlSliderHeight

    property bool dragging: false
    property real dragValue: 0
    readonly property bool known: root.value >= 0 || root.dragging
    readonly property real shown: root.dragging ? root.dragValue : Math.max(0, Math.min(1, root.value))

    function take(fraction: real): void {
        root.dragValue = Math.max(0, Math.min(1, fraction));
        root.moved(root.dragValue);
    }

    // A wheel notch is a key's step, 5%, and a touchpad's small deltas add up to
    // one (as in Workspaces.qml): taken one event a step, a single swipe ran the
    // volume from nothing to full in a third of a second, and a sideways one
    // lowered it (found 2026-11-07).
    property real notch: 0

    function wheelBy(delta: real): void {
        root.notch += delta;
        const steps = Math.trunc(root.notch / 120);
        if (steps === 0)
            return;
        root.notch -= steps * 120;
        settle.stop();
        const from = root.dragging ? root.dragValue : root.shown;
        root.dragging = true;
        root.take(from + steps * 0.05);
        settle.restart();
    }

    // The knob holds where it was let go until the service has caught up.
    Timer {
        id: settle

        interval: 400
        onTriggered: root.dragging = false
    }

    Item {
        id: lead

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.controlButtonSize
        height: Theme.controlButtonSize

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: leadArea.enabled && leadArea.containsMouse
            color: Theme.surfaceHover
        }

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: Theme.iconFont
            font.pixelSize: Theme.menuIconSize
            color: root.usable ? Theme.fg : Theme.muted
        }

        MouseArea {
            id: leadArea

            anchors.fill: parent
            enabled: root.iconClickable && root.usable
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.iconClicked()
        }
    }

    Item {
        id: tail

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.expandable
        width: root.expandable ? Theme.controlButtonSize : 0
        height: Theme.controlButtonSize

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: tailArea.containsMouse
            color: Theme.surfaceHover
        }

        Text {
            anchors.centerIn: parent
            text: Theme.iconChevron
            font.family: Theme.iconFont
            font.pixelSize: Theme.menuIconSize
            color: Theme.fg
            rotation: root.expanded ? 90 : 0

            Behavior on rotation {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: tailArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expandRequested()
        }
    }

    // Inset by half a knob at both ends, so the knob stays on the panel at
    // 0 and at 100.
    Item {
        id: track

        anchors.left: lead.right
        anchors.leftMargin: Theme.px(6) + Theme.controlKnobSize / 2
        anchors.right: tail.left
        anchors.rightMargin: Theme.controlKnobSize / 2 + (root.expandable ? Theme.px(4) : Theme.px(6))
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.controlKnobSize

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.controlTrackHeight
            radius: height / 2
            color: Theme.surfaceRaised
        }

        Rectangle {
            visible: root.known
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, root.shown * parent.width)
            height: Theme.controlTrackHeight
            radius: height / 2
            color: root.usable ? Theme.fg : Theme.muted
        }

        Rectangle {
            visible: root.known
            x: root.shown * parent.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.controlKnobSize
            height: width
            radius: width / 2
            color: root.usable ? Theme.fg : Theme.muted
        }
    }

    // As tall as the row and half a knob past either end: the track alone
    // is a few pixels to aim at.
    MouseArea {
        anchors.left: track.left
        anchors.right: track.right
        anchors.leftMargin: -Theme.controlKnobSize / 2
        anchors.rightMargin: -Theme.controlKnobSize / 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        enabled: root.usable
        preventStealing: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        function fraction(mouse): real {
            return mapToItem(track, mouse.x, mouse.y).x / Math.max(1, track.width);
        }

        onPressed: mouse => {
            settle.stop();
            root.dragging = true;
            root.take(fraction(mouse));
        }
        onPositionChanged: mouse => {
            if (pressed)
                root.take(fraction(mouse));
        }
        onReleased: settle.restart()
        onCanceled: settle.restart()
        onWheel: wheel => root.wheelBy(wheel.angleDelta.y)
    }
}
