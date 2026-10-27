pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Notification history, opened by the bell or Super+N: the day's entries
// drawn as the toasts are (NotificationToasts.qml), in one panel where the
// toasts stand, the count and clear all above them (the user, 2026-10-25).
// A click runs the default action and closes it; a drag to the right drops
// the entry. It moves as a toast does (the user, 2026-10-26): in from the
// screen's edge and back out, a new card entering as a toast, clear all
// sending the cards off one after another (Theme.notif*Ms).
Scope {
    id: root

    // Swipe-to-delete threshold as a fraction of card width; matches the toasts.
    readonly property real swipeCommit: 0.28

    // From the opening until the panel has slid out: the window outlives
    // the close by its way out.
    property bool up: false

    onUpChanged: {
        Notifications.centreShown = root.up;
        if (!root.up)
            root.entered = ({});
    }

    // Clear all under way: the ids it was asked for, dropped once the last
    // card is off. Kept here, not in the window, so that a close halfway
    // drops them at once; an entry that came meanwhile stays.
    property var sweptIds: []
    readonly property bool sweeping: root.sweptIds.length > 0
    // The stagger stops growing here: cards further down are out of view.
    readonly property int sweepCap: 8
    // The first card in view, which goes first.
    property int sweepFrom: 0

    // A card that arrived since the panel opened enters once, not again at
    // each rebuild of the list.
    property real openedAt: 0
    property var entered: ({})

    function toggle() {
        Notifications.toggleCentre();
    }

    function close() {
        Notifications.centreOpen = false;
    }

    // `from` and `to`: the cards in view, the only ones built.
    function sweep(from: int, to: int): void {
        const ids = Notifications.history.map(e => e.id);
        if (root.sweeping || ids.length === 0)
            return;
        root.sweepFrom = Math.max(0, from);
        const last = to >= root.sweepFrom ? to : ids.length - 1;
        root.sweptIds = ids;
        sweepEnd.interval = Math.min(last - root.sweepFrom, root.sweepCap) * Theme.notifSweepStaggerMs
                            + Theme.notifLeaveMs;
        sweepEnd.restart();
    }

    function finishSweep(): void {
        sweepEnd.stop();
        const ids = root.sweptIds;
        if (ids.length === 0)
            return;
        root.sweptIds = [];
        if (Notifications.history.every(e => ids.indexOf(e.id) !== -1)) {
            Notifications.clear();
            return;
        }
        for (const id of ids)
            Notifications.dismiss(id);
    }

    Timer {
        id: sweepEnd

        onTriggered: root.finishSweep()
    }

    Connections {
        target: Notifications

        function onCentreOpenChanged() {
            if (Notifications.centreOpen) {
                root.openedAt = Date.now();
                root.entered = ({});
                root.up = true;
            } else {
                root.finishSweep();
            }
        }
    }

    GlobalShortcut {
        name: "notifications"
        description: "Show the notification history"

        onPressed: root.toggle()
    }

    LazyLoader {
        active: root.up || Notifications.centreOpen

        PanelWindow {
            id: win

            color: "transparent"
            focusable: true

            // On its way out it takes no keys or clicks: one typed just after
            // Escape belongs to the window under it.
            readonly property bool leaving: !Notifications.centreOpen
            property Region passThrough: Region {}

            // Full-screen so any click dismisses it. Ignore the bar's exclusive
            // zone, or the cards' top margin stacks below the bar twice.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: win.leaving ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:notification-centre"
            mask: win.leaving ? win.passThrough : null

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // The cards' share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            // Keys need an item (a PanelWindow takes no focus); the stage
            // also keeps the margins' and the list's share of the screen.
            FittedStage {
                id: stage

                fit: win.fit
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }

                // Click-away closes; undimmed, since this is a sidebar, not a modal.
                MouseArea {
                    anchors.fill: parent
                    enabled: !win.leaving

                    onClicked: root.close()
                }

                // Where the toasts stand, the cards held together in one panel
                // rather than floating apart (the user, 2026-10-25); its padding
                // is the cards' gap, its corners theirs at that distance.
                Rectangle {
                    id: panel

                    readonly property int pad: Theme.notifStackGap

                    // The list scrolls past this share of the screen.
                    readonly property int room: Math.round((stage.height - Theme.barHeight) * 0.62)
                                                - header.height - panel.pad * 3

                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Theme.barHeight + Theme.notifBarGap
                    anchors.rightMargin: Theme.edgeMarginRight + Theme.menuItemPadX
                    width: Theme.notifWidth + panel.pad * 2
                    // The gap above the list closes with it: no step when the
                    // last card goes.
                    height: panel.pad + header.height
                            + (list.visible ? Math.min(panel.pad, list.height) + list.height : 0) + panel.pad
                    radius: Theme.notifRadius + panel.pad
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

                    // In and out by the screen's edge, fading with the
                    // distance, as a toast; moved, never resized, which
                    // Hyprland would re-place at every step.
                    readonly property real away: panel.width + panel.anchors.rightMargin + Theme.px(40)
                    property real offset: panel.away

                    transform: Translate {
                        x: panel.offset
                    }
                    opacity: Math.max(0, 1 - panel.offset / (panel.width * 0.7))

                    // Begun at the window's first frame, as MediaPopup's is, or
                    // part of the way in is over before it shows; 300 ms at most.
                    property bool waiting: true

                    Connections {
                        target: panel.Window.window
                        enabled: panel.waiting

                        function onAfterAnimating(): void {
                            panel.waiting = false;
                            panel.follow();
                        }
                    }

                    Timer {
                        interval: 300
                        running: panel.waiting

                        onTriggered: {
                            panel.waiting = false;
                            panel.follow();
                        }
                    }

                    Connections {
                        target: Notifications

                        function onCentreOpenChanged(): void {
                            panel.follow();
                        }
                    }

                    function follow(): void {
                        if (panel.waiting)
                            return;
                        if (Notifications.centreOpen) {
                            outward.stop();
                            inward.start();
                        } else if (panel.offset >= panel.away) {
                            inward.stop();
                            root.up = false;
                        } else {
                            inward.stop();
                            outward.start();
                        }
                    }

                    NumberAnimation {
                        id: inward

                        target: panel
                        property: "offset"
                        to: 0
                        duration: Theme.notifEnterMs
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        id: outward

                        target: panel
                        property: "offset"
                        to: panel.away
                        duration: Theme.notifLeaveMs
                        easing.type: Easing.InCubic

                        onFinished: {
                            if (!Notifications.centreOpen)
                                root.up = false;
                        }
                    }

                    // Clicks inside must not reach the dismisser behind it.
                    MouseArea {
                        anchors.fill: parent
                    }

                    // The count, in line with the cards' text, and clear all.
                    Item {
                        id: header

                        x: panel.pad
                        y: panel.pad
                        width: Theme.notifWidth
                        height: Theme.notifLineHeight + Theme.notifPadTop

                        Text {
                            anchors.left: parent.left
                            anchors.right: sweep.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.notifPad
                            text: {
                                const n = Notifications.history.length;
                                return n === 0 ? "No notifications" : n === 1 ? "1 notification" : `${n} notifications`;
                            }
                            elide: Text.ElideRight
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.notifTextSize
                            font.weight: Font.DemiBold
                            color: Theme.surfaceFaint
                        }

                        // The list's only control.
                        Text {
                            id: sweep

                            anchors.right: parent.right
                            anchors.rightMargin: Theme.notifPad
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Notifications.history.length > 0
                            text: Theme.iconClearAll
                            font.family: Theme.iconFont
                            font.pixelSize: Math.round(Theme.notifLineHeight * 1.2)
                            color: sweepArea.containsMouse && !root.sweeping ? Theme.accentRed : Theme.surfaceFaint

                            MouseArea {
                                id: sweepArea

                                anchors.fill: parent
                                anchors.margins: -Theme.px(8)
                                enabled: !root.sweeping
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                // The cards in view go first; a point in the gap
                                // between two finds none, so the bottom is looked
                                // for a gap's height up too.
                                onClicked: {
                                    const bottom = list.contentY + list.height - 1;
                                    const to = Math.max(list.indexAt(1, bottom),
                                                        list.indexAt(1, bottom - Theme.notifStackGap - 1));
                                    root.sweep(list.indexAt(1, list.contentY), to);
                                }
                            }
                        }
                    }

                    ListView {
                        id: list

                        x: panel.pad
                        y: header.y + header.height + panel.pad
                        width: Theme.notifWidth
                        // Kept while it closes up after the last entry has gone.
                        visible: Notifications.history.length > 0 || list.height > 0
                        // contentHeight is exact whenever it is below the room:
                        // every card is built.
                        height: Math.max(0, Math.min(list.contentHeight, panel.room))

                        clip: true
                        spacing: Theme.notifStackGap
                        boundsBehavior: Flickable.StopAtBounds
                        model: Notifications.history

                        // Not before the panel is in: it enters at its size.
                        Behavior on height {
                            enabled: !panel.waiting

                            NumberAnimation {
                                duration: Theme.notifCollapseMs
                                easing.type: Easing.OutCubic
                            }
                        }

                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: Theme.notifCollapseMs
                                easing.type: Easing.OutCubic
                            }
                        }

                        // The slot holds the list position and collapses; the
                        // card travels. One item doing both leaves a gap behind.
                        delegate: Item {
                            id: slot

                            required property var modelData
                            required property int index

                            // Among those clear all is sending off.
                            readonly property bool swept: root.sweptIds.indexOf(slot.modelData.id) !== -1

                            width: ListView.view.width
                            height: Math.ceil(card.implicitHeight)
                            clip: true

                            // Rebuilt at every change of the history: a card being
                            // swept stays gone, a new one enters once.
                            Component.onCompleted: {
                                if (slot.swept) {
                                    card.x = card.width + Theme.px(40);
                                    return;
                                }
                                const key = slot.modelData.key;
                                if (slot.modelData.at > root.openedAt && !root.entered[key]) {
                                    root.entered[key] = true;
                                    card.x = card.width;
                                    entering.start();
                                }
                            }

                            onSweptChanged: {
                                if (slot.swept)
                                    sweepingOut.start();
                            }

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
                                    script: Notifications.dismiss(slot.modelData.id)
                                }
                            }

                            // Clear all: off as a toast leaves, each a beat after
                            // the one above.
                            SequentialAnimation {
                                id: sweepingOut

                                PauseAnimation {
                                    duration: Math.min(Math.max(0, slot.index - root.sweepFrom), root.sweepCap)
                                              * Theme.notifSweepStaggerMs
                                }
                                NumberAnimation {
                                    target: card
                                    property: "x"
                                    to: card.width + Theme.px(40)
                                    duration: Theme.notifLeaveMs
                                    easing.type: Easing.InCubic
                                }
                            }

                            NumberAnimation {
                                id: entering

                                target: card
                                property: "x"
                                to: 0
                                duration: Theme.notifEnterMs
                                easing.type: Easing.OutCubic
                            }

                            // The toast's card, as it is drawn there.
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

                                opacity: Math.max(0, 1 - card.x / (card.width * 0.7))

                                // Spring-back only; entrance and exits drive x themselves.
                                Behavior on x {
                                    enabled: !swipe.drag.active && !leaving.running && !sweepingOut.running
                                             && !entering.running && !slot.swept

                                    NumberAnimation {
                                        duration: Theme.notifSpringMs
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                // Lines of notifLineHeight, the body placed by
                                // line count (NotificationToasts.qml says why).
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
                                    enabled: !slot.swept

                                    // A hand where a click runs something, else the
                                    // open hand of a card that only drags.
                                    cursorShape: swipe.drag.active ? Qt.ClosedHandCursor
                                                 : slot.modelData.hasDefault ? Qt.PointingHandCursor
                                                 : Qt.OpenHandCursor
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
                                        if (card.x !== 0 || !slot.modelData.hasDefault)
                                            return;
                                        // "default" is filtered from actions; use the flag.
                                        Notifications.invoke(slot.modelData, "default");
                                        root.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
