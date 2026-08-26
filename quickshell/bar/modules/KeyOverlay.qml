pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// The keys as they are pressed, drawn along the bottom of the screen.
//
// Every chord is two items rather than one: a slot that holds the width and
// collapses, and a cap that moves. Animating one item's scale inside a Row
// leaves its gap behind, so the row would jump when a chord aged out instead of
// closing up behind it.
Scope {
    id: root

    GlobalShortcut {
        name: "keyOverlay"
        description: "Show the keys being pressed"

        onPressed: KeyFeed.toggle()
    }

    LazyLoader {
        active: KeyFeed.enabled

        PanelWindow {
            color: "transparent"

            // Never focusable, and never in the way. The overlay exists to show
            // what is being typed somewhere else; taking the keyboard would stop
            // the very thing it is drawing.
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:keys"

            anchors {
                bottom: true
                left: true
                right: true
            }

            margins {
                bottom: Theme.px(56)
            }

            implicitHeight: Math.max(1, row.implicitHeight + Theme.px(8))

            // Nothing to show yet, and nothing to say about it: an empty strip
            // at the foot of the screen reads as a rendering fault.
            Text {
                anchors.centerIn: parent
                visible: KeyFeed.chords.length === 0 && KeyFeed.failure !== ""
                text: KeyFeed.failure
                font.family: Theme.uiFont
                font.pixelSize: Theme.px(12)
                color: Theme.accentRed
            }

            Row {
                id: row

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(10)

                Repeater {
                    model: KeyFeed.chords

                    Item {
                        id: slot

                        required property var modelData

                        implicitWidth: chord.implicitWidth
                        implicitHeight: chord.implicitHeight
                        width: implicitWidth
                        height: implicitHeight

                        // One way out, taken by the dwell timer. Width collapses
                        // after the cap has faded so the row closes into the gap
                        // rather than snapping across it.
                        SequentialAnimation {
                            id: leaving

                            ParallelAnimation {
                                NumberAnimation {
                                    target: chord
                                    property: "opacity"
                                    to: 0
                                    duration: 180
                                    easing.type: Easing.InQuad
                                }
                                NumberAnimation {
                                    target: chord
                                    property: "scale"
                                    to: 0.82
                                    duration: 180
                                    easing.type: Easing.InQuad
                                }
                            }
                            NumberAnimation {
                                target: slot
                                property: "width"
                                to: 0
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                            ScriptAction {
                                script: KeyFeed.drop(slot.modelData.id)
                            }
                        }

                        Timer {
                            running: true
                            interval: KeyFeed.dwellMs

                            onTriggered: leaving.start()
                        }

                        Row {
                            id: chord

                            spacing: Theme.px(4)
                            transformOrigin: Item.Bottom

                            // Arrives with a small overshoot. A cap that simply
                            // appears reads as a redraw; one that lands reads as
                            // a key having been struck.
                            Component.onCompleted: entering.start()

                            SequentialAnimation {
                                id: entering

                                ParallelAnimation {
                                    NumberAnimation {
                                        target: chord
                                        property: "opacity"
                                        from: 0
                                        to: 1
                                        duration: 90
                                    }
                                    NumberAnimation {
                                        target: chord
                                        property: "scale"
                                        from: 0.6
                                        to: 1.08
                                        duration: 110
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                NumberAnimation {
                                    target: chord
                                    property: "scale"
                                    to: 1
                                    duration: 130
                                    easing.type: Easing.OutBack
                                }
                            }

                            Repeater {
                                model: slot.modelData.mods

                                KeyCap {
                                    required property var modelData

                                    text: modelData
                                    modifier: true
                                }
                            }

                            KeyCap {
                                text: slot.modelData.key
                                modifier: false
                            }
                        }
                    }
                }
            }
        }
    }
}
