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

    // How far a toast has to be dragged before letting go dismisses it rather
    // than springing it back, as a fraction of its width.
    readonly property real swipeCommit: 0.28

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
        // Nothing to say twice. While the history panel is open every toast it
        // would draw is already on screen behind it, and the two surfaces
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

            implicitWidth: Theme.px(440)
            implicitHeight: Math.max(1, stack.implicitHeight)

            Column {
                id: stack

                width: parent.width
                spacing: Theme.px(8)

                Repeater {
                    model: root.live

                    // Two items, not one: the slot holds the space in the column
                    // and the card is what moves. Animating a single item's x
                    // inside a Column leaves its gap behind until the model
                    // changes, so the stack jumps instead of closing up behind
                    // what left.
                    Item {
                        id: slot

                        required property var modelData

                        width: parent.width
                        height: card.implicitHeight
                        clip: true

                        // Runs on expiry, on the close button, and on a released
                        // swipe. One way out, so all three look the same.
                        SequentialAnimation {
                            id: leaving

                            NumberAnimation {
                                target: card
                                property: "x"
                                to: card.width + Theme.px(40)
                                duration: 220
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: slot
                                property: "height"
                                to: 0
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                            ScriptAction {
                                script: root.drop(slot.modelData.id)
                            }
                        }

                        // A critical notification is the one class the spec says
                        // must not disappear on its own: it is what a dying
                        // battery uses. Everything else times out.
                        Timer {
                            running: !slot.modelData.critical
                            interval: root.dwellMs

                            onTriggered: leaving.start()
                        }

                        Rectangle {
                            id: card

                            // One number for every edge. Deriving the height from
                            // the content plus twice this is what keeps the space
                            // under the last line equal to the space above the
                            // first one.
                            readonly property int pad: Theme.px(13)

                            width: parent.width
                            implicitHeight: text.implicitHeight + card.pad * 2
                            height: implicitHeight
                            radius: Theme.px(12)
                            color: Theme.bgAlt
                            border.width: 1
                            border.color: slot.modelData.critical ? Theme.accentRed : Theme.accentQuiet

                            // Arrives from the edge it will later leave by.
                            // Without this it appears instantly and the exit
                            // reads as a glitch rather than as a direction.
                            Component.onCompleted: {
                                card.x = card.width;
                                entering.start();
                            }

                            NumberAnimation {
                                id: entering

                                target: card
                                property: "x"
                                to: 0
                                duration: 260
                                easing.type: Easing.OutCubic
                            }

                            // Fades with the distance travelled, so a swipe shows
                            // how close it is to committing rather than only
                            // reporting it after release.
                            opacity: Math.max(0, 1 - card.x / (card.width * 0.7))

                            // Only for the spring back. The exit and the entrance
                            // drive x themselves and would fight a Behavior.
                            Behavior on x {
                                enabled: !swipe.drag.active && !leaving.running && !entering.running

                                NumberAnimation {
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Text {
                                id: icon

                                anchors.left: parent.left
                                anchors.leftMargin: card.pad
                                anchors.top: parent.top
                                anchors.topMargin: card.pad
                                text: Theme.iconBell
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.iconSize
                                color: slot.modelData.critical ? Theme.accentRed : Theme.accentTeal
                            }

                            Column {
                                id: text

                                anchors.left: icon.right
                                anchors.leftMargin: Theme.px(10)
                                anchors.right: parent.right
                                anchors.rightMargin: card.pad + Theme.px(30)
                                anchors.top: parent.top
                                anchors.topMargin: card.pad
                                spacing: Theme.px(2)

                                Text {
                                    width: parent.width
                                    text: slot.modelData.summary
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(16)
                                    font.weight: Font.DemiBold
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: slot.modelData.body !== ""
                                    text: slot.modelData.body
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(14)
                                    color: Theme.accentQuiet
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    // Markup is advertised to senders in the
                                    // service, so it has to be honoured here or a
                                    // body arrives full of visible <b> tags.
                                    textFormat: Text.StyledText
                                }

                                Text {
                                    width: parent.width
                                    // Against the model, not against `text`: the
                                    // enclosing Column is id: text, so the bare
                                    // name resolves to it and the comparison is
                                    // always true.
                                    visible: slot.modelData.appName !== ""
                                    text: slot.modelData.appName
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(12)
                                    color: Theme.muted
                                    elide: Text.ElideRight
                                    topPadding: Theme.px(3)
                                }
                            }

                            // Drags right only. Dragging a notification left
                            // would suggest it goes somewhere, and there is
                            // nothing to the left of it but the desktop.
                            MouseArea {
                                id: swipe

                                anchors.fill: parent

                                // A toast does answer a click -- it runs the
                                // default action -- so it keeps the finger until
                                // a drag actually starts.
                                cursorShape: swipe.drag.active ? Qt.ClosedHandCursor
                                                               : Qt.PointingHandCursor
                                drag.target: card
                                drag.axis: Drag.XAxis
                                drag.minimumX: 0
                                drag.maximumX: card.width

                                onReleased: {
                                    if (card.x > card.width * root.swipeCommit)
                                        leaving.start();
                                    else
                                        card.x = 0;
                                }

                                // A press that never moved is still a click. The
                                // freedesktop convention is that an action named
                                // "default" is what a click on the body means.
                                onClicked: {
                                    if (card.x !== 0)
                                        return;
                                    // The default action is filtered out of the
                                    // displayed list, so ask the flag rather than
                                    // search a list it is no longer in.
                                    if (slot.modelData.hasDefault)
                                        Notifications.invoke(slot.modelData, "default");
                                    leaving.start();
                                }
                            }

                            // Dismisses the toast only. The notification stays in
                            // the history, which is the whole reason the history
                            // exists: flicking a toast away should not destroy the
                            // record of what it said.
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: card.pad
                                anchors.top: parent.top
                                anchors.topMargin: card.pad
                                text: Theme.iconClose
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.px(25)
                                color: closer.containsMouse ? Theme.fg : Theme.accentQuiet

                                MouseArea {
                                    id: closer

                                    anchors.fill: parent
                                    anchors.margins: -Theme.px(10)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: leaving.start()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
