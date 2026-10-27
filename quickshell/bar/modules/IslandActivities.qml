pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The calls and OBS on the grown island (MediaPopup.qml), under the player
// when something plays, opening as what plays does (the user, 2026-10-26).
// A row each, as the references set a call and a recording: icon, name over
// what it is doing and for how long, round buttons (IslandButton.qml) for the
// little worth doing from here (a call has none: Calls.qml); icon and name
// bring its window forward.
Column {
    id: root

    property bool showCalls: false
    property bool showObs: false

    spacing: Theme.islandRowGap

    Repeater {
        model: root.showCalls ? Calls.apps : []

        Item {
            id: call

            required property var modelData

            width: root.width
            height: Theme.islandRowHeight

            Row {
                id: callFace

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(12)

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.islandRowIcon
                    height: Theme.islandRowIcon
                    source: call.modelData.icon
                    sourceSize.width: Theme.islandRowIcon * 2
                    sourceSize.height: Theme.islandRowIcon * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.px(2)

                    Text {
                        width: Math.min(implicitWidth, root.width - Theme.islandRowIcon - callFace.spacing)
                        elide: Text.ElideRight
                        text: call.modelData.name
                        textFormat: Text.PlainText
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.mediaTitleSize
                        font.weight: Font.DemiBold
                        color: Theme.islandText
                    }

                    // Each call's own clock: the calls began at their own
                    // times.
                    Row {
                        spacing: Theme.px(6)

                        Text {
                            text: "In a call"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.mediaSubSize
                            color: Theme.islandSubtext
                        }

                        Text {
                            text: Theme.clockText(Calls.now - call.modelData.since)
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.mediaSubSize
                            font.features: ({ "tnum": 1 })
                            color: Theme.islandGreen
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: callFace
                cursorShape: Qt.PointingHandCursor
                onClicked: Calls.show(call.modelData)
            }
        }
    }

    // OBS: recording (or paused) with its pause and its stop; live alone,
    // only how long, since a stream stopped by a stray click is not undone.
    Item {
        id: obs

        width: root.width
        height: Theme.islandRowHeight
        visible: root.showObs

        readonly property string icon: {
            const entry = DesktopEntries.heuristicLookup("com.obsproject.Studio")
                          ?? DesktopEntries.heuristicLookup("obs");
            const name = entry?.icon ?? "";
            return name.startsWith("/") ? `file://${name}` : name !== "" ? Quickshell.iconPath(name, true) : "";
        }

        Row {
            id: obsFace

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(12)

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.islandRowIcon
                height: Theme.islandRowIcon
                source: obs.icon
                sourceSize.width: Theme.islandRowIcon * 2
                sourceSize.height: Theme.islandRowIcon * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(2)

                Text {
                    text: "OBS Studio"
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.mediaTitleSize
                    font.weight: Font.DemiBold
                    color: Theme.islandText
                }

                Row {
                    spacing: Theme.px(6)

                    Text {
                        text: Obs.recording ? (Obs.paused ? "Paused" : Obs.streaming ? "Recording, live" : "Recording")
                                            : "Live"
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.mediaSubSize
                        color: Theme.islandSubtext
                    }

                    Text {
                        text: Theme.clockText(Obs.recording ? Obs.recordElapsed : Obs.streamElapsed)
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.mediaSubSize
                        font.features: ({ "tnum": 1 })
                        color: Obs.recording && Obs.paused ? Theme.islandSubtext : Theme.islandRed
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: obsFace
            cursorShape: Qt.PointingHandCursor
            onClicked: Obs.show()
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(10)
            visible: Obs.recording

            IslandButton {
                glyph: Obs.paused ? Theme.iconPlayMd : Theme.iconPauseMd
                onClicked: Obs.togglePause()
            }

            IslandButton {
                stop: true
                onClicked: Obs.stopRecording()
            }
        }
    }
}
