pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Toasts stacked under the bar at the right edge. exclusiveZone 0 makes the
// compositor place the window below the bar's reserved zone, so no copy of
// the bar height is needed here.
Scope {
    id: root

    readonly property int dwellMs: 5000

    // Critical toasts expire too, later: the history panel keeps them, so they
    // need not wait for acknowledgement.
    readonly property int criticalDwellMs: 20000

    // The oldest give way beyond this.
    readonly property int maxVisible: 4

    // Swipe-to-dismiss threshold as a fraction of card width.
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
        // Hidden while the history panel is open: same content, same corner.
        active: root.live.length > 0 && !Notifications.centreOpen

        PanelWindow {
            color: "transparent"

            // A focusable toast would swallow the user's next keystroke.
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
            // Rounded up: Text reports fractional heights, and a surface a
            // fraction short clips the card's bottom border.
            implicitHeight: Math.max(1, Math.ceil(stack.implicitHeight))

            Column {
                id: stack

                width: parent.width
                spacing: Theme.notifStackGap

                Repeater {
                    // ScriptModel, not the bare array: a Repeater rebuilds every
                    // delegate when a plain array is reassigned, replaying each
                    // toast's entrance and dwell. ScriptModel diffs by `id`.
                    model: ScriptModel {
                        values: root.live
                        objectProp: "id"
                    }

                    // The slot holds the column space and collapses; the card
                    // moves. One item doing both leaves a gap, then a jump.
                    Item {
                        id: slot

                        required property var modelData

                        // Shared by the expiry timer and the life bar.
                        readonly property int dwellMs: slot.modelData.critical
                                                       ? root.criticalDwellMs
                                                       : root.dwellMs

                        width: parent.width
                        height: Math.ceil(card.implicitHeight)
                        clip: true

                        // The single exit: expiry, click, and released swipe.
                        SequentialAnimation {
                            id: leaving

                            onStarted: countdown.stop()

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

                        // This timer ends the toast; the life bar only draws it,
                        // so a drawing fault cannot keep a toast up.
                        Timer {
                            running: true
                            interval: slot.dwellMs

                            onTriggered: leaving.start()
                        }

                        Rectangle {
                            id: card

                            readonly property int pad: Theme.notifPad

                            width: parent.width
                            implicitHeight: text.implicitHeight + card.pad * 2
                            height: implicitHeight
                            radius: Theme.notifRadius
                            color: Theme.surfaceBg
                            border.width: slot.modelData.critical ? Theme.notifBorder
                                                                  : Theme.surfaceBorder
                            border.color: slot.modelData.critical ? Theme.accentRed
                                                                  : Theme.surfaceLine

                            // Enters from the edge it leaves by.
                            Component.onCompleted: {
                                card.x = card.width;
                                entering.start();
                                countdown.start();
                            }

                            NumberAnimation {
                                id: entering

                                target: card
                                property: "x"
                                to: 0
                                duration: 260
                                easing.type: Easing.OutCubic
                            }

                            opacity: Math.max(0, 1 - card.x / (card.width * 0.7))

                            // Spring-back only; entrance and exit drive x themselves.
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
                                    // Read from the model: a bare `text` here
                                    // resolves to the Column with id: text.
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
                                    // Plain per the spec; only the body is markup.
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
                                    color: Theme.surfaceDim
                                    lineHeight: 1.28
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    // Markup is advertised; <img> is stripped in
                                    // the service.
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
                                    color: Theme.surfaceFaint
                                    topPadding: Theme.px(7)
                                }
                            }

                            // Life bar. Item.clip is rectangular, so a clipped
                            // strip shows the bottom of a card-radius rectangle
                            // and the bar follows the rounded corners. The clip
                            // window shrinks, not the rounded piece, or its left
                            // corner would move too.
                            Item {
                                id: life

                                readonly property int span: card.width - card.border.width * 2

                                x: card.border.width
                                anchors.bottom: card.bottom
                                anchors.bottomMargin: card.border.width
                                height: Theme.notifLifeBar
                                clip: true

                                Rectangle {
                                    width: life.span
                                    height: card.radius * 2
                                    y: life.height - height
                                    radius: Math.max(0, card.radius - card.border.width)

                                    // Not the border colour: the hairline border
                                    // is too faint for something meant to be watched.
                                    color: slot.modelData.critical ? Theme.accentRed
                                                                   : Theme.surfaceText
                                }

                                NumberAnimation {
                                    id: countdown

                                    target: life
                                    property: "width"
                                    from: life.span
                                    to: 0
                                    duration: slot.dwellMs
                                }
                            }

                            // Right-drag only: dismissal leaves by the screen edge.
                            MouseArea {
                                id: swipe

                                anchors.fill: parent

                                // Pointing hand until dragging: a click runs the
                                // default action.
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

                                onClicked: {
                                    if (card.x !== 0)
                                        return;
                                    // "default" is filtered from actions; use the flag.
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
