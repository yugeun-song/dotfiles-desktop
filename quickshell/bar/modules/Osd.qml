pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

// A transient readout for a value that changes by key press: brightness and
// output volume. It appears on change and leaves on its own.
//
// Deliberately not focusable and not keyboard-grabbing. An overlay that took
// focus would swallow the next press of the very key that summoned it, so
// holding volume-up would show one step and then stop.
Scope {
    id: root

    property int value: 0
    property string icon: ""
    property color accent: Theme.accentAmber
    property bool active: false
    property int holdMs: 1400

    readonly property int fadeMs: 140

    function show(newValue, newIcon, newAccent) {
        root.value = Math.max(0, Math.min(100, newValue));
        root.icon = newIcon;
        root.accent = newAccent ?? Theme.accentAmber;
        root.active = true;
        hold.restart();
    }

    Timer {
        id: hold

        interval: root.holdMs
        onTriggered: root.active = false
    }

    // The loader has to outlive `active`, or the window is destroyed the
    // instant the value expires and the fade animates on a surface nobody
    // ever sees.
    property bool mounted: false

    onActiveChanged: {
        if (root.active) {
            unmount.stop();
            root.mounted = true;
        } else {
            unmount.restart();
        }
    }

    Timer {
        id: unmount

        interval: root.fadeMs + 60
        onTriggered: root.mounted = false
    }

    LazyLoader {
        active: root.mounted

        PanelWindow {
            // Follows the focused screen for the same reason the launcher
            // does: the alternative is a readout on a monitor nobody is
            // looking at.
            screen: {
                const name = Hyprland.focusedMonitor?.name ?? "";
                const match = Quickshell.screens.find(s => s.name === name);
                return match ?? Quickshell.screens[0] ?? null;
            }

            color: "transparent"
            exclusiveZone: 0
            // Auto, not Ignore. Ignore was supposed to measure from the screen
            // edge, so the margin below added the bar's height to clear it --
            // but the bar's exclusive zone was applied as well and the card
            // landed twice as far down as intended. Auto starts below whatever
            // the bar claimed, so the margin is only the gap.
            exclusionMode: ExclusionMode.Auto
            focusable: false
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:osd"

            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            anchors {
                top: true
            }

            // A gap under the bar, not the bar's height: Auto has already
            // placed this below it.
            margins {
                top: Theme.px(6)
            }

            // Nothing here accepts input; the mask keeps clicks going through
            // to whatever is underneath.
            mask: Region {
                item: null
            }

            Rectangle {
                id: card

                // The card is built with root.active already true, so binding
                // straight to it would start at the end of the animation and
                // the card would appear in one step. Starting from the hidden
                // values and binding on completion gives it something to run.
                property bool shown: false

                Component.onCompleted: card.shown = Qt.binding(() => root.active)

                implicitWidth: Theme.px(210)
                implicitHeight: Theme.px(44)
                radius: Theme.px(12)
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine
                opacity: card.shown ? 1 : 0

                // Sliding down out of the bar reads as "the bar said this",
                // which is where the value lives the rest of the time.
                transform: Translate {
                    y: card.shown ? 0 : -Theme.px(8)

                    Behavior on y {
                        NumberAnimation {
                            duration: root.fadeMs
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.fadeMs
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.px(10)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.icon
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.px(17)
                        // The bar's foreground, not the caller's accent. A
                        // brightness step and a volume step are the same kind
                        // of thing and were arriving in two different colours,
                        // neither of which the bar wears.
                        color: Theme.surfaceText
                    }

                    // The bar is the point of this widget: a number alone
                    // does not tell you how much headroom is left.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.px(118)
                        height: Theme.px(6)
                        radius: height / 2
                        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(height, parent.width * root.value / 100)
                            height: parent.height
                            radius: height / 2
                            color: Theme.surfaceText

                            Behavior on width {
                                NumberAnimation {
                                    duration: 110
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.px(26)
                        horizontalAlignment: Text.AlignRight
                        text: `${root.value}`
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(13)
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }
                }
            }
        }
    }
}
