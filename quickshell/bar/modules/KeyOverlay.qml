pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Pressed keys near the bottom-right corner, where they sit beside a video's
// controls rather than over its subtitles.
//
// The surface is a strip of fixed size, not sized to the caps. Hyprland
// places a layer from the size it asks for and draws the buffer it has, so
// a surface that grew and shrank with its content jumped by the difference
// for a frame at every change; anchored to the right edge, every jump landed
// on every cap, and the collapse that closed a gap resized it on each frame
// of the animation. Inside the strip the caps are laid out right to left,
// newest at the corner: the oldest leaving moves nothing, and a new cap
// arriving slides the others left, animated in one place.
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
            id: win

            // The screen being typed on, and only that one: the caps belong
            // beside the window they went to. Without a screen the compositor
            // placed the strip once, on the monitor focused at Super+Y, and it
            // stayed there while the typing moved to the other screen. Not the
            // focused monitor either, which follows the pointer across an empty
            // stretch of the other screen while the keys still go here.
            screen: Screens.keyboard

            color: "transparent"

            // Must never take the keyboard from the window being typed into.
            focusable: false
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:keys"

            // The caps' share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            anchors {
                bottom: true
                right: true
            }

            // No bottom margin (restHeight spaces the row instead), so a cap
            // falling out leaves the screen rather than clipping at the edge.
            margins {
                bottom: 0
                right: Math.round(Theme.keysMarginRight * win.fit)
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

            // The taller of the two cap kinds, measured off hidden caps, so
            // the strip has one height whichever glyphs are up.
            readonly property int capHeight: Math.max(probeText.implicitHeight, probeIcon.implicitHeight)

            // Reference pixels; the stage below is scaled by the factor. Held
            // to the screen on a narrow one.
            readonly property int stripWidth: Math.max(Theme.px(120),
                Math.min(Theme.keysWidth, Math.floor((win.screen?.width ?? Theme.keysWidth) / win.fit) - Theme.keysMarginRight * 2))
            readonly property int stripHeight: win.capHeight + win.restHeight + Theme.px(24)

            implicitWidth: Math.max(1, Math.round((win.stripWidth + win.sidePad * 2) * win.fit))
            implicitHeight: Math.max(1, Math.round(win.stripHeight * win.fit))

            KeyCap {
                id: probeText

                visible: false
                mods: "⌃"
                text: "X"
            }

            KeyCap {
                id: probeIcon

                visible: false
                iconGlyph: true
                text: Theme.iconPlay
            }

            // Show the feed's failure instead of an empty strip, held to the
            // strip: the reason comes from the reader and may be long.
            Text {
                id: failure

                anchors.centerIn: parent
                width: win.stripWidth
                scale: win.fit
                transformOrigin: Item.Center
                visible: KeyFeed.chords.length === 0 && KeyFeed.failure !== ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: KeyFeed.failure
                font.family: Theme.uiFont
                font.pixelSize: Theme.px(12)
                color: Theme.accentRed
            }

            // Reference pixels, scaled about the corner the caps hold.
            Item {
                id: stage

                anchors.right: parent.right
                anchors.top: parent.top
                width: win.stripWidth + win.sidePad * 2
                height: win.stripHeight
                scale: win.fit
                transformOrigin: Item.TopRight

                Row {
                    id: row

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: win.sidePad
                    anchors.rightMargin: win.sidePad
                    anchors.top: parent.top
                    anchors.topMargin: Theme.px(4)
                    height: win.capHeight
                    // First item at the right edge: the model is newest first.
                    layoutDirection: Qt.RightToLeft
                    spacing: Theme.px(10)

                    // The slide when a new cap takes the corner. Nothing else
                    // moves a cap: the oldest is the leftmost, so its leaving
                    // changes no other position.
                    move: Transition {
                        NumberAnimation {
                            properties: "x"
                            duration: Theme.keysSlideMs
                            easing.type: Easing.OutCubic
                        }
                    }

                    Repeater {
                        // ScriptModel diffs by id. A plain array would rebuild every
                        // delegate on each push, replaying entrances and restarting
                        // dwell timers so nothing aged out while typing.
                        model: ScriptModel {
                            values: KeyFeed.chords.slice().reverse()
                            objectProp: "id"
                        }

                        Item {
                            id: slot

                            required property var modelData

                            width: chord.implicitWidth
                            height: win.capHeight

                            // Run by the dwell timer: the cap falls out, then
                            // the chord is dropped from the feed.
                            SequentialAnimation {
                                id: leaving

                                ParallelAnimation {
                                    NumberAnimation {
                                        target: chord
                                        property: "y"
                                        // Fully past the screen edge.
                                        to: win.stripHeight
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

                                // Bottom-aligned in the slot: an icon cap is a
                                // little taller than a text one.
                                y: win.capHeight - chord.height
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
}
