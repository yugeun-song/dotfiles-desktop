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
    //
    // Day, then month, then year, which is the order hypr/hyprlock.conf and the
    // clock's tooltip already use. The month is a name rather than a number
    // because that is the half of this convention that carries its weight: 03
    // and 08 swap places between one country and the next and nothing on screen
    // says which was meant, while "Mar" and "Aug" cannot be read backwards.
    function stamp(ms) {
        const d = new Date(ms);
        const p = n => (n < 10 ? "0" : "") + n;
        const mins = -d.getTimezoneOffset();
        const sign = mins < 0 ? "-" : "+";
        const oh = Math.floor(Math.abs(mins) / 60);
        const om = Math.abs(mins) % 60;
        const zone = "UTC" + sign + oh + (om === 0 ? "" : ":" + p(om));
        return `${Qt.formatDateTime(d, "d MMM yyyy HH:mm:ss")} ${zone}`;
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
                    width: Theme.centreWidth

                    // Everything inside the card that is not the list: the
                    // header's own top margin, the header, the gap under it and
                    // the card's bottom margin.
                    //
                    // This used to be the literal px(28), which is px(8) short
                    // of what those four actually come to, and px(8) is what
                    // was being cut off the bottom row. A number that has to
                    // agree with four anchors elsewhere in the file will stop
                    // agreeing with them; adding them up cannot.
                    readonly property int chrome: Theme.centrePad + header.height
                                                + Theme.px(10) + Theme.centrePad

                    // How much of the screen this may take. It is a panel over
                    // work in progress, not a page, so it gets a share of what
                    // the bar leaves rather than all of it. 45% is high enough
                    // to hold six or seven notifications on this screen and low
                    // enough that the window behind it is still the thing being
                    // used.
                    readonly property int limit:
                        Math.round((parent.height - Theme.barHeight) * 0.45)

                    // One row plus the gap under it, at the shape most of them
                    // take: the sender and timestamp line, a summary, one
                    // wrapped line of body, and the padding the row adds.
                    //
                    // A constant, and deliberately not measured off the list.
                    // It was (contentHeight + spacing) / count, which looks
                    // like the right answer and is not: ListView reports
                    // contentHeight as an estimate for the rows it has not
                    // built yet and refines it as delegates come and go, so the
                    // panel changed height while it was being scrolled.
                    //
                    // Rows are not all this tall. A body that wraps to two
                    // lines, which is what a screenshot path does, adds about
                    // twenty pixels. So the alignment this buys is approximate,
                    // and it is still worth having: the alternative is a strip
                    // of a row along the bottom edge, which reads as a
                    // rendering fault rather than as "there is more below".
                    readonly property int rowUnit: Theme.px(14)   // sender, time
                                                 + Theme.px(6)    // gap
                                                 + Theme.px(21)   // summary
                                                 + Theme.px(6)    // gap
                                                 + Theme.px(19)   // one body line
                                                 + Theme.notifRowPad * 2
                                                 + list.spacing

                    // The tallest this may be: whole rows inside the limit,
                    // and nothing about the list in it, so it does not move
                    // while the list is scrolled.
                    readonly property int cap: {
                        const rows = Math.max(1, Math.floor(
                            (card.limit - card.chrome + list.spacing) / card.rowUnit));
                        return card.chrome + rows * card.rowUnit - list.spacing;
                    }

                    height: {
                        if (Notifications.history.length === 0)
                            return card.chrome + Theme.px(30);
                        // contentHeight is exact once every row exists, which
                        // is the only case this branch decides: a list short
                        // enough to fit is a list with nothing left to estimate.
                        return Math.min(card.chrome + list.contentHeight, card.cap);
                    }
                    radius: Theme.centreRadius
                    color: Theme.bgAlt
                    border.width: Theme.notifBorder
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
                        anchors.margins: Theme.centrePad
                        height: Theme.px(22)

                        // The count leads the word. It was on the far right as
                        // "18 kept", which put the only part of this line that
                        // ever changes as far as possible from the part that
                        // never does, and made a label out of a panel that
                        // already announces itself by being open.
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notifications.history.length + " NOTIFICATION"
                                  + (Notifications.history.length === 1 ? "" : "S")
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.notifLabelSize
                            font.weight: Font.DemiBold
                            font.letterSpacing: Theme.notifTracking
                            color: Theme.muted
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
                            font.pixelSize: Theme.px(28)
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
                        anchors.leftMargin: Theme.centrePad
                        anchors.rightMargin: Theme.centrePad
                        anchors.bottomMargin: Theme.centrePad

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
                            height: Math.ceil(row.implicitHeight)
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
                                implicitHeight: body.implicitHeight + Theme.notifRowPad * 2
                                height: implicitHeight
                                radius: Theme.notifRowRadius
                                color: hover.containsMouse ? Qt.lighter(Theme.bg, 1.5) : Theme.bg
                                border.width: Theme.notifBorder
                                border.color: slot.modelData.critical ? Theme.accentRed
                                                                      : Theme.muted

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
                                    anchors.leftMargin: Theme.notifRowPad
                                    anchors.rightMargin: Theme.notifRowPad
                                    anchors.topMargin: Theme.notifRowPad
                                    spacing: Theme.px(6)

                                    Row {
                                        width: parent.width
                                        spacing: Theme.px(8)

                                        Text {
                                            visible: slot.modelData.critical
                                                     || slot.modelData.appName !== ""
                                            text: slot.modelData.critical
                                                  ? "URGENT"
                                                  : slot.modelData.appName.toUpperCase()
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.notifLabelSize
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: Theme.notifTracking
                                            color: slot.modelData.critical ? Theme.accentRed
                                                                           : Theme.accentTeal
                                        }

                                        Text {
                                            text: root.stamp(slot.modelData.at)
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.notifLabelSize
                                            color: Theme.muted
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: slot.modelData.summary
                                        // Plain text, per the spec; see the toast for the body's exception.
                                        textFormat: Text.PlainText
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.notifTitleSize
                                        font.weight: Font.ExtraBold
                                        color: Theme.fg
                                        lineHeight: 1.06
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        visible: slot.modelData.body !== ""
                                        text: slot.modelData.body
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.notifBodySize
                                        color: Theme.accentQuiet
                                        lineHeight: 1.28
                                        wrapMode: Text.Wrap
                                        textFormat: Text.StyledText
                                    }

                                    // The buttons the sending application offered.
                                    // Notifications.invoke warns and returns false
                                    // if that application has since exited, which
                                    // is the only way an action can fail here.
                                    Row {
                                        visible: slot.modelData.actions.length > 0
                                        spacing: Theme.px(18)
                                        topPadding: Theme.px(9)

                                        Repeater {
                                            model: slot.modelData.actions

                                            Text {
                                                id: action

                                                required property var modelData

                                                text: action.modelData.text.toUpperCase() + "  →"
                                                // The label came from the sender too.
                                                textFormat: Text.PlainText
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.notifLabelSize
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: Theme.notifTracking
                                                color: press.containsMouse ? Theme.fg
                                                                           : Theme.accentTeal

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 110
                                                        easing.type: Easing.OutCubic
                                                    }
                                                }

                                                MouseArea {
                                                    id: press

                                                    anchors.fill: parent
                                                    anchors.margins: -Theme.px(6)
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
