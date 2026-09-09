pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// What the island shows once it is open: a pair of tabs, and under them either
// the music-and-calendar pane or the tray.
//
// Two tabs and not five. The island is a glance, not a window; anything that
// needs more room than this has a surface of its own already -- the launcher,
// the notification centre, the power menu.
Item {
    id: root

    property var player: null
    property bool hasMedia: false
    property bool playing: false
    // Handed to the tray, which needs a window to anchor an item's own menu
    // against. See IslandTray.parentWindow.
    property var parentWindow: null

    // "Nook" is the reference design's name for the music-and-calendar view.
    // Kept because it names a place rather than describing a list, which is
    // what a tab in a two-tab strip has room to do.
    property string tab: "nook"

    Column {
        anchors.fill: parent
        spacing: Theme.islandGap

        Row {
            id: tabs

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.px(4)

            Repeater {
                model: [
                    { id: "nook", label: "Nook", icon: Theme.iconMusic },
                    { id: "tray", label: "Tray", icon: Theme.iconApps }
                ]

                Rectangle {
                    id: tabButton

                    required property var modelData
                    readonly property bool current: root.tab === tabButton.modelData.id

                    implicitWidth: tabRow.implicitWidth + Theme.px(18)
                    implicitHeight: Theme.px(21)
                    radius: height / 2
                    // The current tab is a filled pill and the other is bare.
                    // On a black surface a border would be the obvious way to
                    // say "not selected", and it reads as disabled instead.
                    color: tabButton.current ? Qt.rgba(1, 1, 1, 0.16)
                                             : tabHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }

                    Row {
                        id: tabRow

                        anchors.centerIn: parent
                        spacing: Theme.px(5)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tabButton.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(12)
                            color: tabButton.current ? "#ffffff" : Qt.rgba(1, 1, 1, 0.55)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tabButton.modelData.label
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.islandSubSize
                            font.weight: Font.DemiBold
                            color: tabButton.current ? "#ffffff" : Qt.rgba(1, 1, 1, 0.55)
                        }
                    }

                    HoverHandler {
                        id: tabHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tab = tabButton.modelData.id
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: parent.height - tabs.height - Theme.islandGap

            // Both panes are built and one is hidden, rather than loaded on
            // demand. The tray has to be watching its D-Bus items whether or
            // not its tab is showing, or the first look at it is always empty.
            Row {
                anchors.fill: parent
                visible: root.tab === "nook"
                spacing: Theme.islandGap

                IslandMusic {
                    height: parent.height
                    width: (parent.width - Theme.islandGap) * 0.56
                    player: root.player
                    hasMedia: root.hasMedia
                    playing: root.playing
                }

                // A hairline between the two halves, so they read as two
                // things rather than as one crowded one.
                Rectangle {
                    width: Math.max(1, Theme.px(1))
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.10)
                }

                IslandCalendar {
                    height: parent.height
                    width: parent.width - Theme.islandGap * 2 - (parent.width - Theme.islandGap) * 0.56 - Math.max(1, Theme.px(1))
                }
            }

            IslandTray {
                anchors.fill: parent
                visible: root.tab === "tray"
                parentWindow: root.parentWindow
            }
        }
    }
}
