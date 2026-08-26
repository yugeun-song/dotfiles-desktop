pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// The history behind the toasts: what arrived, what it said, and what it can
// still be asked to do.
//
// A toast is a glance. Everything it cannot hold -- the notification that
// arrived while the screen was locked, the one dismissed by reflex, the second
// line of a body that was elided -- lives here instead.
Scope {
    id: root

    // How far a row has to be dragged before letting go deletes it rather than
    // springing it back, as a fraction of its width. The same figure the toasts
    // use, because the two are the same gesture on the same notification.
    readonly property real swipeCommit: 0.28

    function toggle() {
        Notifications.toggleCentre();
    }

    function close() {
        Notifications.centreOpen = false;
    }

    // Absolute time, not "3 minutes ago". A relative label has to be recomputed
    // to stay true, and one that silently stops updating is worse than a clock.
    //
    // Written out whole: date, seconds, and the offset. This list is read to
    // answer "when exactly", and the short form could not. It hid the date
    // whenever the notification had arrived today, which is most of them and
    // exactly the ones where the answer sounds obvious and is not; and a bare
    // clock reading never says which clock it was read from.
    //
    // The offset is a number rather than an abbreviation, for the reason
    // LeftPills gives: an abbreviation has to be recognised before it says
    // anything, and several are ambiguous across regions. Minutes appear only
    // when they are not zero, so Seoul reads UTC+9 and Kathmandu UTC+5:45.
    function stamp(ms) {
        const d = new Date(ms);
        const p = n => (n < 10 ? "0" : "") + n;
        const mins = -d.getTimezoneOffset();
        const sign = mins < 0 ? "-" : "+";
        const oh = Math.floor(Math.abs(mins) / 60);
        const om = Math.abs(mins) % 60;
        const zone = "UTC" + sign + oh + (om === 0 ? "" : ":" + p(om));
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} `
             + `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())} ${zone}`;
    }

    GlobalShortcut {
        name: "notifications"
        description: "Show the notification history"

        onPressed: root.toggle()
    }

    LazyLoader {
        active: Notifications.centreOpen

        PanelWindow {
            color: "transparent"
            focusable: true

            // This covers the whole screen so a click anywhere dismisses it,
            // which means it must ignore the bar's exclusive zone. Without this
            // the compositor first pushes the surface below the bar and the
            // card's own top margin then stacks on top of that, putting it a
            // full bar height too low.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:notification-centre"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Keys go to an item inside the window, never to the window. A
            // PanelWindow does not take focus itself, so a Keys handler on it is
            // never reached and Escape does nothing.
            Item {
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }

                // Clicking away closes. The area is transparent rather than
                // dimmed: this panel is a sidebar, not a modal, and dimming the
                // whole screen to read one line overstates it.
                MouseArea {
                    anchors.fill: parent

                    onClicked: root.close()
                }

                Rectangle {
                    id: card

                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Theme.barHeight + Theme.px(8)
                    anchors.rightMargin: Theme.edgeMarginRight
                    width: Theme.px(510)

                    // Everything inside the card that is not the list: the
                    // header's own top margin, the header, the gap under it and
                    // the card's bottom margin.
                    //
                    // This used to be the literal px(28), which is px(8) short
                    // of what those four actually come to, and px(8) is what
                    // was being cut off the bottom row. A number that has to
                    // agree with four anchors elsewhere in the file will stop
                    // agreeing with them; adding them up cannot.
                    readonly property int chrome: Theme.px(14) + header.height
                                                + Theme.px(10) + Theme.px(12)

                    // How much of the screen this may take. It is a panel over
                    // work in progress, not a page, so it gets a share of what
                    // the bar leaves rather than all of it. 45% is high enough
                    // to hold six or seven notifications on this screen and low
                    // enough that the window behind it is still the thing being
                    // used.
                    readonly property int limit:
                        Math.round((parent.height - Theme.barHeight) * 0.45)

                    // One row plus the gap under it, averaged over the list.
                    //
                    // Rows are not all the same height, so this is an average
                    // and the alignment it buys is approximate. It is worth
                    // having anyway: these notifications mostly arrive from two
                    // or three senders in the same shape, so in practice the
                    // average is the height, and the limit lands on a boundary
                    // between rows instead of through the middle of one.
                    readonly property real rowUnit: {
                        const n = Notifications.history.length;
                        return n > 0 ? (list.contentHeight + list.spacing) / n : 0;
                    }

                    height: {
                        const n = Notifications.history.length;
                        if (n === 0)
                            return card.chrome + Theme.px(30);
                        const full = card.chrome + list.contentHeight;
                        if (full <= card.limit)
                            return full;
                        if (card.rowUnit <= 0)
                            return card.limit;
                        // Whole rows only. Anything left over would be a strip
                        // of a row, which reads as a rendering fault rather
                        // than as "there is more below".
                        const rows = Math.max(1, Math.floor(
                            (card.limit - card.chrome + list.spacing) / card.rowUnit));
                        return Math.round(card.chrome + rows * card.rowUnit - list.spacing);
                    }
                    radius: Theme.px(14)
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.accentQuiet

                    Behavior on height {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Clicks inside must not reach the dismisser behind it, or
                    // reading the list would close it.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Item {
                        id: header

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.px(14)
                        height: Theme.px(22)

                        // The count leads the word. It was on the far right as
                        // "18 kept", which put the only part of this line that
                        // ever changes as far as possible from the part that
                        // never does, and made a label out of a panel that
                        // already announces itself by being open.
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notifications.history.length + " Notification"
                                  + (Notifications.history.length === 1 ? "" : "s")
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(16)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                        }

                        // The only control left on this panel, so it is drawn at
                        // a size that says so. It was the smaller of two icons
                        // while every row also carried a close button.
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Notifications.history.length > 0
                            text: Theme.iconClearAll
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(30)
                            color: sweep.containsMouse ? Theme.accentRed : Theme.muted

                            MouseArea {
                                id: sweep

                                anchors.fill: parent
                                anchors.margins: -Theme.px(8)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: Notifications.clear()
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: Notifications.history.length === 0
                        text: "Nothing yet"
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.textSize
                        color: Theme.muted
                    }

                    ListView {
                        id: list

                        anchors.top: header.bottom
                        anchors.topMargin: Theme.px(10)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        anchors.bottomMargin: Theme.px(12)

                        clip: true
                        spacing: Theme.px(9)
                        boundsBehavior: Flickable.StopAtBounds
                        model: Notifications.history

                        // The rows below the one that left slide up rather than
                        // snapping into the gap.
                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Same split as the toasts: the slot holds the row's
                        // place in the list and collapses, the row is what
                        // travels. One item doing both leaves its gap behind.
                        delegate: Item {
                            id: slot

                            required property var modelData

                            width: ListView.view.width
                            height: row.implicitHeight
                            clip: true

                            SequentialAnimation {
                                id: leaving

                                NumberAnimation {
                                    target: row
                                    property: "x"
                                    to: row.width + Theme.px(40)
                                    duration: 200
                                    easing.type: Easing.InCubic
                                }
                                NumberAnimation {
                                    target: slot
                                    property: "height"
                                    to: 0
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }
                                ScriptAction {
                                    script: Notifications.dismiss(slot.modelData.id)
                                }
                            }

                            Rectangle {
                                id: row

                                width: parent.width
                                implicitHeight: body.implicitHeight + Theme.px(20)
                                height: implicitHeight
                                radius: Theme.px(9)
                                color: hover.containsMouse ? Qt.lighter(Theme.bg, 1.5) : Theme.bg
                                border.width: 1
                                border.color: slot.modelData.critical ? Theme.accentRed : Theme.muted

                                opacity: Math.max(0, 1 - row.x / (row.width * 0.7))

                                Behavior on x {
                                    enabled: !hover.drag.active && !leaving.running

                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                // Hover highlight and swipe are the same area, so
                                // a drag that starts anywhere on the row works
                                // rather than only on a dedicated handle.
                                MouseArea {
                                    id: hover

                                    anchors.fill: parent
                                    hoverEnabled: true

                                    // A hand, not a pointing finger. The row has
                                    // no click to offer -- it is dragged aside to
                                    // delete -- and a finger would promise one.
                                    cursorShape: hover.drag.active ? Qt.ClosedHandCursor
                                                                   : Qt.OpenHandCursor
                                    drag.target: row
                                    drag.axis: Drag.XAxis
                                    drag.minimumX: 0
                                    drag.maximumX: row.width

                                    onReleased: {
                                        if (row.x > row.width * root.swipeCommit)
                                            leaving.start();
                                        else
                                            row.x = 0;
                                    }
                                }

                                Column {
                                    id: body

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: Theme.px(11)
                                    // Was 48, holding a gap for a close button
                                    // that is no longer drawn.
                                    anchors.rightMargin: Theme.px(12)
                                    anchors.topMargin: Theme.px(10)
                                    spacing: Theme.px(4)

                                    Row {
                                        width: parent.width
                                        spacing: Theme.px(6)

                                        Text {
                                            visible: slot.modelData.appName !== ""
                                            text: slot.modelData.appName
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(12)
                                            color: Theme.accentTeal
                                        }

                                        Text {
                                            text: root.stamp(slot.modelData.at)
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.px(12)
                                            color: Theme.muted
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: slot.modelData.summary
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(16)
                                        font.weight: Font.DemiBold
                                        color: Theme.fg
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        visible: slot.modelData.body !== ""
                                        text: slot.modelData.body
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(14)
                                        color: Theme.accentQuiet
                                        wrapMode: Text.Wrap
                                        textFormat: Text.StyledText
                                    }

                                    // The buttons the sending application offered.
                                    // Notifications.invoke warns and returns false
                                    // if that application has since exited, which
                                    // is the only way an action can fail here.
                                    Row {
                                        visible: slot.modelData.actions.length > 0
                                        spacing: Theme.px(6)
                                        topPadding: Theme.px(4)

                                        Repeater {
                                            model: slot.modelData.actions

                                            Rectangle {
                                                id: action

                                                required property var modelData

                                                width: label.implicitWidth + Theme.px(16)
                                                height: label.implicitHeight + Theme.px(7)
                                                radius: Theme.px(6)
                                                color: press.containsMouse ? Theme.accentTeal : Theme.bg
                                                border.width: 1
                                                border.color: Theme.accentQuiet

                                                Text {
                                                    id: label

                                                    anchors.centerIn: parent
                                                    text: action.modelData.text
                                                    font.family: Theme.uiFont
                                                    font.pixelSize: Theme.px(13)
                                                    color: press.containsMouse ? Theme.ink : Theme.fg
                                                }

                                                MouseArea {
                                                    id: press

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor

                                                    onClicked: {
                                                        Notifications.invoke(slot.modelData,
                                                                             action.modelData.identifier);
                                                        root.close();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                            }
                        }
                    }
                }
            }
        }
    }
}
