pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

// Transient brightness/volume readout. Never takes focus: it would swallow the
// next press of the key that summoned it, breaking key repeat.
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

    // Outlives `active` by the fade, or the window is gone before it fades.
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
            // The focused screen, as in the launcher.
            screen: {
                const name = Hyprland.focusedMonitor?.name ?? "";
                const match = Quickshell.screens.find(s => s.name === name);
                return match ?? Quickshell.screens[0] ?? null;
            }

            color: "transparent"
            exclusiveZone: 0
            // Auto places this below the bar's zone, so the top margin is only
            // the gap. Ignore plus a bar-height margin landed twice as low.
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

            margins {
                top: Theme.px(6)
            }

            // Empty mask: clicks pass through.
            mask: Region {
                item: null
            }

            Rectangle {
                id: card

                // Created with active already true; bind after completion so
                // the entrance animates instead of starting at its end.
                property bool shown: false

                Component.onCompleted: card.shown = Qt.binding(() => root.active)

                implicitWidth: Theme.px(210)
                implicitHeight: Theme.px(44)
                radius: Theme.px(12)
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine
                opacity: card.shown ? 1 : 0

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
                        // Oversized: the brightness glyph sits well inside its
                        // em box.
                        font.pixelSize: Theme.px(24)
                        // Ignores the caller's accent on purpose: one colour for
                        // every readout.
                        color: Theme.surfaceText
                    }

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
