pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Notifications as they arrive, stacked under the bar at the right edge.
//
// The window asks for an exclusive zone of zero rather than positioning itself
// with a margin of Theme.barHeight. Under the layer-shell protocol a zone of
// zero means "respect what other surfaces have reserved", so the compositor
// puts this below the bar on its own. A hand-computed offset would be a second
// copy of the bar's height, and would be wrong the first time the bar changes.
Scope {
    id: root

    // Long enough to finish reading a line, short enough not to sit in the way.
    readonly property int dwellMs: 5000

    // Beyond this the stack reaches the bottom of the screen and the oldest are
    // unreadable anyway, so the oldest give way to what just arrived.
    readonly property int maxVisible: 4

    property var live: []

    function push(entry) {
        const next = root.live.concat([entry]);
        while (next.length > root.maxVisible)
            next.shift();
        root.live = next;
    }

    function drop(id) {
        const next = [];
        for (let i = 0; i < root.live.length; i++)
            if (root.live[i].id !== id)
                next.push(root.live[i]);
        root.live = next;
    }

    Connections {
        target: Notifications

        function onToast(entry) {
            root.push(entry);
        }
    }

    LazyLoader {
        // Nothing to say twice. While the history panel is open every toast
        // it would draw is already on screen behind it, and the two surfaces
        // overlap at the same corner.
        active: root.live.length > 0 && !Notifications.centreOpen

        PanelWindow {
            color: "transparent"

            // Never focusable. A toast that took the keyboard would swallow the
            // next keystroke of whatever the notification interrupted.
            focusable: false
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Normal
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:notifications"

            anchors {
                top: true
                right: true
            }

            margins {
                right: Theme.edgeMarginRight
                top: Theme.px(8)
            }

            implicitWidth: Theme.px(400)
            implicitHeight: Math.max(1, stack.implicitHeight)

            Column {
                id: stack

                width: parent.width
                spacing: Theme.px(8)

                Repeater {
                    model: root.live

                    Rectangle {
                        id: toast

                        required property var modelData

                        width: parent.width
                        implicitHeight: text.implicitHeight + Theme.px(22)
                        height: implicitHeight
                        radius: Theme.px(12)
                        color: Theme.bgAlt
                        border.width: 1
                        border.color: toast.modelData.critical ? Theme.accentRed : Theme.accentQuiet

                        // A critical notification is the one class the spec says
                        // must not disappear on its own: it is what a dying
                        // battery uses. Everything else times out.
                        Timer {
                            running: !toast.modelData.critical
                            interval: root.dwellMs

                            onTriggered: root.drop(toast.modelData.id)
                        }

                        Text {
                            id: icon

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.px(13)
                            anchors.top: parent.top
                            anchors.topMargin: Theme.px(12)
                            text: toast.modelData.critical ? Theme.iconBellBadge : Theme.iconBell
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.iconSize
                            color: toast.modelData.critical ? Theme.accentRed : Theme.accentTeal
                        }

                        Column {
                            id: text

                            anchors.left: icon.right
                            anchors.leftMargin: Theme.px(10)
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.px(34)
                            anchors.top: parent.top
                            anchors.topMargin: Theme.px(11)
                            spacing: Theme.px(2)

                            Text {
                                width: parent.width
                                text: toast.modelData.summary
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.textSize
                                font.weight: Font.DemiBold
                                color: Theme.fg
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: toast.modelData.body !== ""
                                text: toast.modelData.body
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(11)
                                color: Theme.accentQuiet
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                // Markup is advertised to senders in the service,
                                // so it has to be honoured here or a body arrives
                                // full of visible <b> tags.
                                textFormat: Text.StyledText
                            }

                            Text {
                                width: parent.width
                                text: toast.modelData.appName
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(10)
                                color: Theme.muted
                                elide: Text.ElideRight
                                topPadding: Theme.px(3)
                            }
                        }

                        // Dismisses the toast only. The notification stays in the
                        // history, which is the whole reason the history exists:
                        // flicking a toast away should not destroy the record of
                        // what it said.
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.px(12)
                            anchors.top: parent.top
                            anchors.topMargin: Theme.px(11)
                            text: Theme.iconClose
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(15)
                            color: closer.containsMouse ? Theme.fg : Theme.muted

                            MouseArea {
                                id: closer

                                anchors.fill: parent
                                anchors.margins: -Theme.px(6)
                                hoverEnabled: true

                                onClicked: root.drop(toast.modelData.id)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: -1

                            // The freedesktop convention is that an action named
                            // "default" is what a click on the body means.
                            onClicked: {
                                for (let i = 0; i < toast.modelData.actions.length; i++) {
                                    if (toast.modelData.actions[i].identifier === "default") {
                                        Notifications.invoke(toast.modelData, "default");
                                        break;
                                    }
                                }
                                root.drop(toast.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
