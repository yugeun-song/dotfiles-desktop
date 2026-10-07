pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Notification history panel: everything a toast could not hold.
Scope {
    id: root

    // Swipe-to-delete threshold as a fraction of row width; matches the toasts.
    readonly property real swipeCommit: 0.28

    function toggle() {
        Notifications.toggleCentre();
    }

    function close() {
        Notifications.centreOpen = false;
    }

    // Full absolute time: a relative label goes stale unless recomputed, and
    // this list answers "when exactly". Numeric UTC offset for the reason given
    // in StatusItems.qml. Day-month-year with a month name, as hyprlock and the
    // bar clock use, so 03/08 cannot be read backwards.
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
            id: win

            color: "transparent"
            focusable: true

            // Full-screen so any click dismisses it. Ignore the bar's exclusive
            // zone, or the card's top margin stacks below the bar twice.
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

            // The card's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            // Keys handlers must sit on an item: a PanelWindow never takes
            // focus. This one is also the stage, so the bar-height margin and
            // the row cap keep their share of the screen.
            FittedStage {
                fit: win.fit
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }

                // Click-away closes; undimmed, since this is a sidebar, not a modal.
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

                    // Card height minus the list, summed from the same anchors
                    // below so it cannot drift from them.
                    readonly property int chrome: Theme.centrePad + header.height
                                                + Theme.px(10) + Theme.centrePad

                    // Sized in rows, not screen share: rows scale with the bar,
                    // so a screen share shows fewer rows on the denser panel.
                    readonly property int rowTarget: 5

                    // Screen share survives only as a ceiling for short screens.
                    readonly property int limit: Math.min(
                        Math.round((parent.height - Theme.barHeight) * 0.62),
                        card.chrome + card.rowTarget * card.rowUnit - list.spacing)

                    // A typical row plus spacing, as a constant. Not measured
                    // from the list: ListView's contentHeight is an estimate for
                    // unbuilt rows and changes while scrolling. Taller rows make
                    // the whole-row fit approximate, which beats a sliver of row.
                    readonly property int rowUnit: Theme.px(14)   // sender, time
                                                 + Theme.px(6)    // gap
                                                 + Theme.px(21)   // summary
                                                 + Theme.px(6)    // gap
                                                 + Theme.px(19)   // one body line
                                                 + Theme.notifRowPad * 2
                                                 + list.spacing

                    // Whole rows within limit; independent of the list so it
                    // stays still while scrolling.
                    readonly property int cap: {
                        const rows = Math.max(1, Math.floor(
                            (card.limit - card.chrome + list.spacing) / card.rowUnit));
                        return card.chrome + rows * card.rowUnit - list.spacing;
                    }

                    height: {
                        if (Notifications.history.length === 0)
                            return card.chrome + Theme.px(30);
                        // contentHeight is exact whenever it is below cap: every
                        // row is built.
                        return Math.min(card.chrome + list.contentHeight, card.cap);
                    }
                    radius: Theme.centreRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

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

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Notifications.history.length + " NOTIFICATION"
                                  + (Notifications.history.length === 1 ? "" : "S")
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.notifLabelSize
                            font.weight: Font.DemiBold
                            font.letterSpacing: Theme.notifTracking
                            color: Theme.surfaceFaint
                        }

                        // The panel's only control, so drawn large.
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Notifications.history.length > 0
                            text: Theme.iconClearAll
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(28)
                            color: sweep.containsMouse ? Theme.accentRed : Theme.surfaceFaint

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
                        color: Theme.surfaceFaint
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

                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        // The slot holds the list position and collapses; the
                        // row travels. One item doing both leaves a gap behind.
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
                                color: hover.containsMouse ? Theme.surfaceRaisedHover
                                                          : Theme.surfaceRaised
                                border.width: slot.modelData.critical ? Theme.notifBorder
                                                                      : Theme.surfaceBorder
                                border.color: slot.modelData.critical ? Theme.accentRed
                                                                      : Theme.surfaceLine

                                opacity: Math.max(0, 1 - row.x / (row.width * 0.7))

                                Behavior on x {
                                    enabled: !hover.drag.active && !leaving.running

                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                MouseArea {
                                    id: hover

                                    anchors.fill: parent
                                    hoverEnabled: true

                                    // Open hand: the row drags, it does not click.
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
                                        id: header

                                        width: parent.width
                                        spacing: Theme.px(8)

                                        // The time keeps its room; a long app_name
                                        // ("org.freedesktop.network-manager-applet")
                                        // pushed it off the row.
                                        Text {
                                            width: Math.min(implicitWidth, header.width - when.implicitWidth - header.spacing)
                                            elide: Text.ElideRight
                                            visible: slot.modelData.critical
                                                     || slot.modelData.appName !== ""
                                            text: slot.modelData.critical
                                                  ? "URGENT"
                                                  : slot.modelData.appName.toUpperCase()
                                            // The sender names itself; never markup,
                                            // which would fetch an <img> in it.
                                            textFormat: Text.PlainText
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.notifLabelSize
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: Theme.notifTracking
                                            color: slot.modelData.critical ? Theme.accentRed
                                                                           : Theme.surfaceDim
                                        }

                                        Text {
                                            id: when

                                            text: root.stamp(slot.modelData.at)
                                            font.family: Theme.uiFont
                                            font.pixelSize: Theme.notifLabelSize
                                            color: Theme.surfaceFaint
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
                                        color: Theme.surfaceDim
                                        lineHeight: 1.28
                                        wrapMode: Text.Wrap
                                        textFormat: Text.StyledText
                                    }

                                    // A Flow: several long labels wrap to a second
                                    // line instead of running off the row.
                                    Flow {
                                        id: actions

                                        width: parent.width
                                        visible: slot.modelData.actions.length > 0
                                        spacing: Theme.px(18)
                                        topPadding: Theme.px(9)

                                        Repeater {
                                            model: slot.modelData.actions

                                            Text {
                                                id: action

                                                required property var modelData

                                                width: Math.min(implicitWidth, actions.width)
                                                elide: Text.ElideRight
                                                text: action.modelData.text.toUpperCase() + "  →"
                                                // The label came from the sender too.
                                                textFormat: Text.PlainText
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.notifLabelSize
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: Theme.notifTracking
                                                color: press.containsMouse ? Theme.fg
                                                                           : Theme.surfaceDim

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
