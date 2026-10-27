pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Toasts stacked under the bar at the right edge (exclusiveZone 0: the
// compositor places them below the bar's reserved zone). Each is the model
// banner the user chose, without its icon: the summary in semibold over the
// body, one size and one colour (Theme.notifWidth has the measurements); a
// critical one keeps a red border.
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

    // One card per notification: a replaced one's earlier card goes.
    function push(entry) {
        const next = root.live.filter(e => e.id !== entry.id).concat([entry]);
        while (next.length > root.maxVisible)
            next.shift();
        root.live = next;
    }

    // By key, not id: the card of a replaced notification finishing its exit
    // must not take the newer card with it.
    function drop(key) {
        root.live = root.live.filter(e => e.key !== key);
    }

    Connections {
        target: Notifications

        function onToast(entry) {
            root.push(entry);
        }

        // Cleared while the history is open: left in place, the cards were
        // rebuilt when it closed and dwelt again, dismissed ones included.
        function onCentreOpenChanged() {
            if (Notifications.centreOpen)
                root.live = [];
        }
    }

    LazyLoader {
        // Hidden while the history panel is open: same content, same corner;
        // and while it leaves, or a toast would enter where it is going.
        active: root.live.length > 0 && !Notifications.centreOpen && !Notifications.centreShown

        PanelWindow {
            id: win

            color: "transparent"

            // A focusable toast would swallow the user's next keystroke.
            focusable: false
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Normal
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:notifications"

            // The stack's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            anchors {
                top: true
                right: true
            }

            // The right edge under the end of the bar's last glyph, as the
            // model lines its banner up under the clock.
            margins {
                right: Math.round((Theme.edgeMarginRight + Theme.menuItemPadX) * win.fit)
                top: Math.round(Theme.notifBarGap * win.fit)
            }

            implicitWidth: Math.round(Theme.notifWidth * win.fit)
            // Rounded up: Text reports fractional heights, and a surface a
            // fraction short clips the card's bottom border.
            readonly property int wanted: Math.max(1, Math.ceil(stack.implicitHeight * win.fit))

            // Grows at once, shrinks once the stack has stopped: resized with
            // the collapsing slot, the surface was re-placed by Hyprland at
            // every size and the cards below rose in steps. The shrink drops
            // only an empty strip. Set, not bound: a binding would follow
            // every shrink.
            property int held: 1

            Component.onCompleted: win.held = win.wanted
            onWantedChanged: {
                if (win.wanted >= win.held) {
                    win.held = win.wanted;
                    settle.stop();
                } else {
                    settle.restart();
                }
            }

            Timer {
                id: settle

                interval: 400
                onTriggered: win.held = win.wanted
            }

            implicitHeight: win.held

            // Laid out at the reference width and scaled to the window.
            Column {
                id: stack

                width: Theme.notifWidth
                scale: win.fit
                transformOrigin: Item.TopLeft
                spacing: Theme.notifStackGap

                Repeater {
                    // ScriptModel, not the bare array: a Repeater rebuilds every
                    // delegate when a plain array is reassigned, replaying each
                    // toast's entrance and dwell. ScriptModel diffs by `key`.
                    model: ScriptModel {
                        values: root.live
                        objectProp: "key"
                    }

                    // The slot holds the column space and collapses; the card
                    // moves. One item doing both leaves a gap, then a jump.
                    Item {
                        id: slot

                        required property var modelData

                        readonly property int dwellMs: slot.modelData.critical
                                                       ? root.criticalDwellMs
                                                       : root.dwellMs

                        width: parent.width
                        height: Math.ceil(card.implicitHeight)
                        clip: true

                        // The single exit: expiry, click, and released swipe.
                        SequentialAnimation {
                            id: leaving

                            NumberAnimation {
                                target: card
                                property: "x"
                                to: card.width + Theme.px(40)
                                duration: Theme.notifLeaveMs
                                easing.type: Easing.InCubic
                            }
                            NumberAnimation {
                                target: slot
                                property: "height"
                                to: 0
                                duration: Theme.notifCollapseMs
                                easing.type: Easing.OutCubic
                            }
                            ScriptAction {
                                script: root.drop(slot.modelData.key)
                            }
                        }

                        Timer {
                            running: true
                            interval: slot.dwellMs

                            onTriggered: leaving.start()
                        }

                        Rectangle {
                            id: card

                            width: parent.width
                            implicitHeight: lines.height + Theme.notifPadTop + Theme.notifPadBottom
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
                            }

                            NumberAnimation {
                                id: entering

                                target: card
                                property: "x"
                                to: 0
                                duration: Theme.notifEnterMs
                                easing.type: Easing.OutCubic
                            }

                            opacity: Math.max(0, 1 - card.x / (card.width * 0.7))

                            // Spring-back only; entrance and exit drive x themselves.
                            Behavior on x {
                                enabled: !swipe.drag.active && !leaving.running && !entering.running

                                NumberAnimation {
                                    duration: Theme.notifSpringMs
                                    easing.type: Easing.OutCubic
                                }
                            }

                            // Every line Theme.notifLineHeight high, as in the
                            // model (a proportional height let baselines fall 18
                            // and 19 px apart); the body placed by line count, as
                            // Qt keeps a last line at 19 px, which set it a pixel
                            // low, and a Text given that height elides to nothing.
                            Item {
                                id: lines

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: Theme.notifPad
                                anchors.rightMargin: Theme.notifPad
                                anchors.topMargin: Theme.notifPadTop
                                height: Theme.notifLineHeight * (title.lineCount + (body.visible ? body.lineCount : 0))

                                // One line when a body follows, as in the
                                // model; two when the summary is all there is.
                                Text {
                                    id: title

                                    width: parent.width
                                    text: slot.modelData.summary
                                    // Plain per the spec; only the body is markup.
                                    textFormat: Text.PlainText
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.notifTextSize
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                    lineHeightMode: Text.FixedHeight
                                    lineHeight: Theme.notifLineHeight
                                    wrapMode: Text.Wrap
                                    maximumLineCount: slot.modelData.body !== "" ? 1 : 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: body

                                    y: Theme.notifLineHeight * title.lineCount
                                    width: parent.width
                                    visible: slot.modelData.body !== ""
                                    text: slot.modelData.body
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.notifTextSize
                                    color: Theme.surfaceText
                                    lineHeightMode: Text.FixedHeight
                                    lineHeight: Theme.notifLineHeight
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    // Markup is advertised; <img> is stripped in
                                    // the service.
                                    textFormat: Text.StyledText
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
