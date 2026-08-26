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

    function toggle() {
        Notifications.toggleCentre();
    }

    function close() {
        Notifications.centreOpen = false;
    }

    // Absolute time, not "3 minutes ago". A relative label has to be recomputed
    // to stay true, and one that silently stops updating is worse than a clock.
    function stamp(ms) {
        const d = new Date(ms);
        const p = n => (n < 10 ? "0" : "") + n;
        const now = new Date();
        const sameDay = d.getFullYear() === now.getFullYear()
                     && d.getMonth() === now.getMonth()
                     && d.getDate() === now.getDate();
        const clock = p(d.getHours()) + ":" + p(d.getMinutes());
        return sameDay ? clock : `${p(d.getMonth() + 1)}-${p(d.getDate())} ${clock}`;
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
                    width: Theme.px(420)
                    height: Math.min(parent.height - Theme.barHeight - Theme.px(28),
                                     header.height + list.contentHeight + Theme.px(28))
                    radius: Theme.px(14)
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.accentQuiet

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

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(14)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.px(10)

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Notifications.history.length === 0
                                      ? "" : Notifications.history.length + " kept"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(11)
                                color: Theme.muted
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Notifications.history.length > 0
                                text: Theme.iconClearAll
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.px(17)
                                color: sweep.containsMouse ? Theme.accentRed : Theme.muted

                                MouseArea {
                                    id: sweep

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    anchors.margins: -Theme.px(5)
                                    hoverEnabled: true

                                    onClicked: Notifications.clear()
                                }
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
                        spacing: Theme.px(7)
                        boundsBehavior: Flickable.StopAtBounds
                        model: Notifications.history

                        delegate: Rectangle {
                            id: row

                            required property var modelData

                            width: ListView.view.width
                            height: body.implicitHeight + Theme.px(18)
                            radius: Theme.px(9)
                            color: hover.containsMouse ? Theme.bg : "transparent"
                            border.width: 1
                            border.color: row.modelData.critical ? Theme.accentRed : Theme.bg

                            MouseArea {
                                id: hover

                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            Column {
                                id: body

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: Theme.px(11)
                                anchors.rightMargin: Theme.px(30)
                                anchors.topMargin: Theme.px(9)
                                spacing: Theme.px(3)

                                Row {
                                    width: parent.width
                                    spacing: Theme.px(6)

                                    Text {
                                        text: row.modelData.appName
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(10)
                                        color: Theme.accentTeal
                                    }

                                    Text {
                                        text: root.stamp(row.modelData.at)
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(10)
                                        color: Theme.muted
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: row.modelData.summary
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.textSize
                                    font.weight: Font.DemiBold
                                    color: Theme.fg
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: row.modelData.body !== ""
                                    text: row.modelData.body
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(11)
                                    color: Theme.accentQuiet
                                    wrapMode: Text.Wrap
                                    textFormat: Text.StyledText
                                }

                                // The buttons the sending application offered.
                                // Notifications.invoke warns and returns false if
                                // that application has since exited, which is the
                                // only way an action can fail here.
                                Row {
                                    visible: row.modelData.actions.length > 0
                                    spacing: Theme.px(6)
                                    topPadding: Theme.px(4)

                                    Repeater {
                                        model: row.modelData.actions

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
                                                font.pixelSize: Theme.px(11)
                                                color: press.containsMouse ? Theme.ink : Theme.fg
                                            }

                                            MouseArea {
                                                id: press

                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true

                                                onClicked: {
                                                    Notifications.invoke(row.modelData,
                                                                         action.modelData.identifier);
                                                    root.close();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.px(10)
                                anchors.top: parent.top
                                anchors.topMargin: Theme.px(9)
                                visible: hover.containsMouse || kill.containsMouse
                                text: Theme.iconClose
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.px(14)
                                color: kill.containsMouse ? Theme.accentRed : Theme.muted

                                MouseArea {
                                    id: kill

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    anchors.margins: -Theme.px(5)
                                    hoverEnabled: true

                                    onClicked: Notifications.dismiss(row.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
