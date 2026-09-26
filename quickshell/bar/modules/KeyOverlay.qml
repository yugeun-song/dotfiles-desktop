pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Pressed keys in the bottom-right corner, where they sit beside a video's
// controls rather than over its subtitles. Each chord is a slot that owns the
// width (and collapses) plus a cap that animates: scaling an item inside a Row
// leaves its gap behind, so the row would jump.
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

            // Must never take the keyboard from the window being typed into.
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:keys"

            anchors {
                bottom: true
                right: true
            }

            // No bottom margin (restHeight spaces the row instead), so a cap
            // falling out leaves the screen rather than clipping at the edge.
            // The right margin matches the toasts above, so the two corners
            // share one edge.
            margins {
                bottom: 0
                right: Theme.edgeMarginRight
            }

            // Empty mask: the caps are display only. The surface sits over the
            // bottom of whatever window is there (a video's recommendation
            // column, a status line), and without the mask it swallowed every
            // click in that area for as long as the feed was on.
            mask: Region {
                item: null
            }

            readonly property int restHeight: Theme.px(56)
            // Room for the entrance overshoot (scale 1.08) on the outer caps.
            readonly property int sidePad: Theme.px(8)

            // Sized to what it draws, so the surface never covers more than
            // the caps (or the failure line, which replaces them).
            implicitWidth: Math.max(1, Math.max(row.implicitWidth, failure.visible ? failure.implicitWidth : 0) + sidePad * 2)
            implicitHeight: Math.max(1, row.implicitHeight + restHeight + Theme.px(24))

            // Show the feed's failure instead of an empty strip.
            Text {
                id: failure

                anchors.centerIn: parent
                visible: KeyFeed.chords.length === 0 && KeyFeed.failure !== ""
                text: KeyFeed.failure
                font.family: Theme.uiFont
                font.pixelSize: Theme.px(12)
                color: Theme.accentRed
            }

            Row {
                id: row

                // Right-aligned: the newest cap holds the corner and older
                // ones age out to its left.
                anchors.right: parent.right
                anchors.rightMargin: sidePad
                anchors.top: parent.top
                anchors.topMargin: Theme.px(4)
                spacing: Theme.px(10)

                Repeater {
                    // ScriptModel diffs by id. A plain array would rebuild every
                    // delegate on each push, replaying entrances and restarting
                    // dwell timers so nothing aged out while typing.
                    model: ScriptModel {
                        values: KeyFeed.chords
                        objectProp: "id"
                    }

                    Item {
                        id: slot

                        required property var modelData

                        implicitWidth: chord.implicitWidth
                        implicitHeight: chord.implicitHeight
                        width: implicitWidth
                        height: implicitHeight

                        // Run by the dwell timer: cap falls out, then the slot
                        // width collapses so the row closes smoothly.
                        SequentialAnimation {
                            id: leaving

                            ParallelAnimation {
                                NumberAnimation {
                                    target: chord
                                    property: "y"
                                    // Fully past the screen edge.
                                    to: chord.height + Theme.px(80)
                                    duration: 340
                                    easing.type: Easing.InCubic
                                }
                                NumberAnimation {
                                    target: chord
                                    property: "opacity"
                                    to: 0
                                    duration: 340
                                    easing.type: Easing.InQuad
                                }
                                NumberAnimation {
                                    target: chord
                                    property: "scale"
                                    to: 0.9
                                    duration: 340
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

                            // Small overshoot so it reads as a keystrike.
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

                            KeyCap {
                                mods: KeyFeed.symbolsFor(slot.modelData.mods)
                                text: KeyFeed.keyLabel(slot.modelData.key)
                                iconGlyph: KeyFeed.keyIsIcon(slot.modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }
}
