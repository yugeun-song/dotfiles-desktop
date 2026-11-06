pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The tablet mirror's settings and its start, laid out as the weather's place panel
// (the user, 2026-11-07: write on the tablet, share it in a call). It says what is
// missing in words, since the step left is usually on the tablet. A change takes
// effect at the next start: scrcpy has no way to change them while it runs. Esc or a
// click beside the card closes it, and so does a lock; the mirror goes on.
Scope {
    id: root

    function close(): void {
        Mirror.panelOpen = false;
    }

    // A lock takes the keyboard; the panel would hold it again after.
    Connections {
        target: KeyFeed

        function onLockedChanged() {
            if (KeyFeed.locked)
                root.close();
        }
    }

    LazyLoader {
        active: Mirror.panelOpen

        PanelWindow {
            id: win

            screen: Mirror.panelScreen ?? Screens.focused

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:mirror"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real fit: Theme.fit(win.screen)

            Component.onCompleted: Mirror.watchers += 1
            Component.onDestruction: Mirror.watchers -= 1

            FittedStage {
                fit: win.fit

                // A clear backdrop (only the session dialog dims); a click closes.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.weatherPanelWidth)
                    height: body.implicitHeight + Theme.displaysPad * 2
                    radius: Theme.surfaceRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

                    // Swallows clicks so a near miss does not hit the backdrop.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: body

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.displaysPad
                        spacing: Theme.px(14)

                        Text {
                            text: "Tablet"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(22)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                        }

                        // What is the case, and the step left.
                        Row {
                            width: parent.width
                            spacing: Theme.px(12)

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Theme.iconTablet
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.px(30)
                                color: Mirror.state === "running" ? Theme.accentGreen : Mirror.state === "ready" ? Theme.fg : Theme.muted
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.px(54)
                                spacing: Theme.px(2)

                                Text {
                                    text: Mirror.title(Mirror.state)
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(15)
                                    font.weight: Font.Medium
                                    color: Theme.fg
                                }

                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    // A device's name and scrcpy's words: never markup.
                                    textFormat: Text.PlainText
                                    text: Mirror.hint(Mirror.state, Mirror.error, Mirror.name)
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(12)
                                    color: Theme.muted
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: Theme.surfaceBorder
                            color: Theme.surfaceSeparator
                        }

                        Column {
                            width: parent.width

                            MirrorChoice {
                                label: "Longest side"
                                value: Mirror.options.maxSize
                                choices: [{ label: "1280", value: 1280 }, { label: "1600", value: 1600 }, { label: "1920", value: 1920 }, { label: "Full", value: 0 }]
                                onPicked: value => Mirror.set({ maxSize: value })
                            }

                            MirrorChoice {
                                label: "Bit rate"
                                value: Mirror.options.bitRate
                                choices: [{ label: "8M", value: 8 }, { label: "16M", value: 16 }, { label: "32M", value: 32 }, { label: "64M", value: 64 }]
                                onPicked: value => Mirror.set({ bitRate: value })
                            }

                            MirrorChoice {
                                label: "Frame rate"
                                value: Mirror.options.fps
                                choices: [{ label: "30", value: 30 }, { label: "60", value: 60 }, { label: "90", value: 90 }]
                                onPicked: value => Mirror.set({ fps: value })
                            }

                            MirrorChoice {
                                label: "Codec"
                                value: Mirror.options.codec
                                choices: [{ label: "H.264", value: "h264" }, { label: "H.265", value: "h265" }]
                                onPicked: value => Mirror.set({ codec: value })
                            }

                            ToggleRow {
                                label: "Control from this laptop"
                                detail: "Off, the laptop only shows the tablet, and a stray click draws nothing."
                                on: Mirror.options.control === true
                                onToggled: on => Mirror.set({ control: on })
                            }

                            ToggleRow {
                                label: "Tablet's sound"
                                detail: "Off, it stays out of the call."
                                on: Mirror.options.audio === true
                                onToggled: on => Mirror.set({ audio: on })
                            }

                            ToggleRow {
                                label: "Full screen"
                                detail: "For sharing a whole screen in the call."
                                on: Mirror.options.fullscreen === true
                                onToggled: on => Mirror.set({ fullscreen: on })
                            }
                        }

                        Item {
                            width: parent.width
                            height: action.height

                            Text {
                                anchors.left: parent.left
                                anchors.right: action.left
                                anchors.rightMargin: Theme.px(12)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Mirror.running
                                wrapMode: Text.WordWrap
                                text: "Changes take effect at the next start."
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(12)
                                color: Theme.muted
                            }

                            PillButton {
                                id: action

                                anchors.right: parent.right
                                label: Mirror.running ? "Stop" : "Start"
                                primary: true
                                usable: Mirror.running || Mirror.canStart
                                onClicked: {
                                    if (action.usable)
                                        Mirror.toggle();
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
