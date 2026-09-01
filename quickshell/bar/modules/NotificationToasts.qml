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

            implicitWidth: Theme.notifWidth
            // Rounded up, not passed through. A Text reports a fractional
            // implicitHeight, so the layer surface was a fraction of a pixel
            // shorter than the card inside it and the bottom border was the
            // part that fell outside.
            implicitHeight: Math.max(1, Math.ceil(stack.implicitHeight))

            Column {
                id: stack

                width: parent.width
                spacing: Theme.notifStackGap

                Repeater {
                    // Not `model: root.live`. push() and drop() assign a whole
                    // new array, and a Repeater over a plain array rebuilds
                    // every delegate when the array is replaced: each toast
                    // already on screen replayed its slide-in, restarted its
                    // five second dwell from zero, and one caught mid-dismissal
                    // came back. ScriptModel diffs the list and emits only the
                    // row that actually moved, so the survivors are left alone.
                    // concat() carries the same entry objects across, which is
                    // what identity on `id` is matching.
                    model: ScriptModel {
                        values: root.live
                        objectProp: "id"
                    }

                    // Two items, not one: the slot holds the space in the column
                    // and the card is what moves. Animating a single item's x
                    // inside a Column leaves its gap behind until the model
                    // changes, so the stack jumps instead of closing up behind
                    // what left.
                    Item {
                        id: slot

                        required property var modelData

                        width: parent.width
                        height: Math.ceil(card.implicitHeight)
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
                            readonly property int pad: Theme.notifPad

                            width: parent.width
                            implicitHeight: text.implicitHeight + card.pad * 2
                            height: implicitHeight
                            radius: Theme.notifRadius
                            color: Theme.bgAlt
                            border.width: Theme.notifBorder
                            border.color: slot.modelData.critical ? Theme.accentRed
                                                                  : Theme.accentQuiet

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

                            Column {
                                id: text

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: card.pad
                                anchors.rightMargin: card.pad
                                anchors.topMargin: card.pad
                                spacing: Theme.px(6)

                                Text {
                                    width: parent.width
                                    // Against the model, not against this Text's
                                    // own `text`: the enclosing Column is
                                    // id: text, so the bare name resolves to it
                                    // and the row would never draw.
                                    visible: slot.modelData.critical
                                             || slot.modelData.appName !== ""
                                    text: slot.modelData.critical
                                          ? "URGENT"
                                          : slot.modelData.appName.toUpperCase()
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.notifLabelSize
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: Theme.notifTracking
                                    color: slot.modelData.critical ? Theme.accentRed
                                                                   : Theme.muted
                                    elide: Text.ElideRight
                                    bottomPadding: Theme.px(1)
                                }

                                Text {
                                    width: parent.width
                                    text: slot.modelData.summary
                                    // A summary is a single line of plain text in the freedesktop spec.
                                    // Only the body below is markup, and only because senders are told so.
                                    textFormat: Text.PlainText
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.notifTitleSize
                                    font.weight: Font.ExtraBold
                                    color: Theme.fg
                                    lineHeight: 1.06
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: slot.modelData.body !== ""
                                    text: slot.modelData.body
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.notifBodySize
                                    color: Theme.accentQuiet
                                    lineHeight: 1.28
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
                                    visible: slot.modelData.hasDefault
                                    text: "OPEN  →"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.notifLabelSize
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: Theme.notifTracking
                                    color: Theme.muted
                                    topPadding: Theme.px(7)
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

                        }
                    }
                }
            }
        }
    }
}
