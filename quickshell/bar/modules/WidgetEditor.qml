pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The widgets' edit mode on one screen (Super+Alt+W; the user, 2026-11-04:
// moved and resized only after a key turns the mode on). The widgets are
// drawn here over everything while it lasts, their desktop window gone: a
// drag moves one and it lands on the screen's grid (Widgets.grid) at the free
// place nearest, shown while dragging over the grid's places, with a line
// wherever that place meets another widget's edge or middle, as a slide
// editor draws one (the user, 2026-11-05); S, M and L resize it; the corner's
// minus removes it.
// The bar at the top adds one, opens the settings, or ends the mode, as do
// Esc and a click on the empty screen.
PanelWindow {
    id: root

    required property real k
    required property real top
    required property var rects

    readonly property real fit: Theme.fit(root.screen)
    readonly property string screenName: root.screen?.name ?? ""
    property bool adding: false

    // The widget being dragged: its id and where it is now; and where it
    // would land, from the layout's own rule (Widgets.landing).
    property string dragId: ""
    property point dragAt: Qt.point(0, 0)
    readonly property var ghost: root.dragId === "" ? null
        : Widgets.landing(root.screenName, root.dragId, root.dragAt.x, root.dragAt.y, root.width, root.height, root.top)
    readonly property var grid: Widgets.grid(root.width, root.height, root.top)

    // The grid's places while a widget is dragged, one cell each: in the
    // left half counted from the left, in the right half from the right, as
    // a place is (Widgets.nearest), the same for top and bottom; a cell of
    // the far half that would meet one of the near half is left out, so the
    // two halves meet at a wider gap where the whole cells leave room over.
    readonly property var slots: {
        if (root.dragId === "")
            return [];
        const g = root.grid;
        const side = (start, end, count, middle) => {
            const near = [];
            const far = [];
            for (let i = 0; i < count; i++) {
                const a = start + i * g.pitch;
                if (a + g.cell / 2 < middle)
                    near.push(a);
                const b = end - g.cell - i * g.pitch;
                if (b + g.cell / 2 >= middle)
                    far.push(b);
            }
            const last = near.length > 0 ? near[near.length - 1] + g.cell + g.gap : -Infinity;
            return near.concat(far.filter(b => b >= last));
        };
        const xs = side(g.x0, g.x1, g.cols, root.width / 2);
        const ys = side(g.y0, g.y1, g.rows, (root.top + root.height) / 2);
        const out = [];
        for (const y of ys) {
            for (const x of xs)
                out.push(Qt.point(x, y));
        }
        return out;
    }

    // Where the landing place lines up with another widget: its left edge,
    // middle or right edge on another's, a vertical line through both; its
    // top, middle or bottom, a horizontal one. Each line runs the length of
    // the widgets it joins and a little past them.
    readonly property var guides: {
        const a = root.ghost;
        if (!a)
            return [];
        const others = root.rects.filter(r => r.id !== root.dragId);
        const reach = root.u(10);
        const lines = {};
        const add = (vertical, at, from, to) => {
            const key = `${vertical ? "v" : "h"}${Math.round(at)}`;
            const line = lines[key];
            lines[key] = line ? { vertical: vertical, at: at, from: Math.min(line.from, from), to: Math.max(line.to, to) }
                              : { vertical: vertical, at: at, from: from, to: to };
        };
        for (const b of others) {
            for (const fa of [a.x, a.x + a.w / 2, a.x + a.w]) {
                for (const fb of [b.x, b.x + b.w / 2, b.x + b.w]) {
                    if (Math.abs(fa - fb) < 1)
                        add(true, fa, Math.min(a.y, b.y) - reach, Math.max(a.y + a.h, b.y + b.h) + reach);
                }
            }
            for (const fa of [a.y, a.y + a.h / 2, a.y + a.h]) {
                for (const fb of [b.y, b.y + b.h / 2, b.y + b.h]) {
                    if (Math.abs(fa - fb) < 1)
                        add(false, fa, Math.min(a.x, b.x) - reach, Math.max(a.x + a.w, b.x + b.w) + reach);
                }
            }
        }
        return Object.values(lines);
    }

    function u(base: real): int {
        return Math.round(Theme.px(base) * root.fit);
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    // The keys on the focused screen, and only while nothing stands over it.
    WlrLayershell.keyboardFocus: Surfaces.top === "widgetEditor" && root.screen === Screens.focused
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell:widget-editor"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The empty screen: a click there ends the mode.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.adding)
                root.adding = false;
            else
                Widgets.toggleEditing();
        }
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (root.adding)
                    root.adding = false;
                else
                    Widgets.toggleEditing();
                event.accepted = true;
            }
        }
    }

    Repeater {
        model: root.slots

        Rectangle {
            required property point modelData

            x: modelData.x
            y: modelData.y
            width: root.grid.cell
            height: root.grid.cell
            radius: Math.round(Theme.widgetRadius * root.k)
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
            border.width: 1
            border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.14)
        }
    }

    // Where the dragged widget would land.
    Rectangle {
        visible: root.ghost !== null
        x: root.ghost?.x ?? 0
        y: root.ghost?.y ?? 0
        width: root.ghost?.w ?? 0
        height: root.ghost?.h ?? 0
        radius: Math.round(Theme.widgetRadius * root.k)
        color: Qt.rgba(Theme.accentIndigo.r, Theme.accentIndigo.g, Theme.accentIndigo.b, 0.10)
        border.width: Math.max(2, root.u(2))
        border.color: Theme.accentIndigo
    }

    Repeater {
        model: root.rects

        Item {
            id: slot

            required property var modelData

            readonly property bool dragged: root.dragId === slot.modelData.id
            readonly property var info: Widgets.kinds.find(k => k.kind === slot.modelData.kind)

            x: slot.dragged ? root.dragAt.x : slot.modelData.x
            y: slot.dragged ? root.dragAt.y : slot.modelData.y
            z: slot.dragged ? 2 : 1
            width: slot.modelData.w
            height: slot.modelData.h

            WidgetCard {
                rect: slot.modelData
                k: root.k
                screen: root.screen
                clickable: false
                opacity: slot.dragged ? 0.85 : 1
            }

            MouseArea {
                id: grip

                property point offset: Qt.point(0, 0)

                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true

                onPressed: mouse => {
                    grip.offset = Qt.point(mouse.x, mouse.y);
                    root.adding = false;
                }
                onPositionChanged: mouse => {
                    if (!grip.pressed)
                        return;
                    const p = grip.mapToItem(null, mouse.x, mouse.y);
                    if (root.dragId === "" && Math.hypot(p.x - grip.offset.x - slot.modelData.x, p.y - grip.offset.y - slot.modelData.y) < root.u(4))
                        return;
                    root.dragId = slot.modelData.id;
                    root.dragAt = Qt.point(Math.max(0, Math.min(root.width - slot.width, p.x - grip.offset.x)),
                                           Math.max(root.top, Math.min(root.height - slot.height, p.y - grip.offset.y)));
                }
                onReleased: {
                    if (root.dragId === slot.modelData.id)
                        Widgets.place(root.screenName, slot.modelData.id, root.dragAt.x, root.dragAt.y, root.width, root.height, root.top);
                    root.dragId = "";
                }
                onCanceled: root.dragId = ""
            }

            // The sizes it is drawn at, the current one lit, astride the
            // bottom edge, in the gap rather than over what the widget says.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - height / 2
                spacing: root.u(4)
                visible: !slot.dragged && (slot.info?.sizes.length ?? 0) > 1

                Repeater {
                    model: slot.info?.sizes ?? []

                    Rectangle {
                        id: chip

                        required property string modelData

                        readonly property bool current: chip.modelData === slot.modelData.size

                        width: root.u(28)
                        height: root.u(24)
                        radius: height / 2
                        color: chip.current ? Theme.accentIndigo
                                            : (chipArea.containsMouse ? Theme.surfaceRaisedHover : Theme.surfaceRaised)

                        Text {
                            anchors.centerIn: parent
                            text: Widgets.sizeNames[chip.modelData] ?? ""
                            font.family: Theme.uiFont
                            font.pixelSize: root.u(12)
                            font.weight: Font.DemiBold
                            color: chip.current ? Theme.ink : Theme.fg
                        }

                        MouseArea {
                            id: chipArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Widgets.resize(root.screenName, slot.modelData.id, chip.modelData,
                                                      root.width, root.height, root.top)
                        }
                    }
                }
            }

            // Remove, at the corner as a desktop's edit mode has it.
            Rectangle {
                visible: !slot.dragged
                x: -width / 3
                y: -height / 3
                width: root.u(24)
                height: width
                radius: width / 2
                color: removeArea.containsMouse ? Theme.accentRed : Theme.surfaceRaised
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                Text {
                    anchors.centerIn: parent
                    text: Theme.iconMinus
                    font.family: Theme.iconFont
                    font.pixelSize: root.u(15)
                    color: removeArea.containsMouse ? Theme.ink : Theme.fg
                }

                MouseArea {
                    id: removeArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Widgets.remove(root.screenName, slot.modelData.id)
                }
            }
        }
    }

    Repeater {
        model: root.guides

        Rectangle {
            required property var modelData

            readonly property real thickness: Math.max(1, root.u(1.5))

            z: 3
            x: modelData.vertical ? modelData.at - thickness / 2 : modelData.from
            y: modelData.vertical ? modelData.from : modelData.at - thickness / 2
            width: modelData.vertical ? thickness : modelData.to - modelData.from
            height: modelData.vertical ? modelData.to - modelData.from : thickness
            color: Theme.accentRed
        }
    }

    // The mode's own bar under the shell's, its gallery and its hint, in the
    // panels' reference pixels (FittedStage).
    FittedStage {
        fit: root.fit

        Rectangle {
            id: toolbar

            anchors.horizontalCenter: parent.horizontalCenter
            y: root.top / root.fit + Theme.px(12)
            width: tools.implicitWidth + Theme.px(16)
            height: Theme.widgetEditorBar
            radius: height / 2
            color: Theme.surfaceBg
            border.width: Theme.surfaceBorder
            border.color: Theme.surfaceLine

            // Swallows clicks so a near miss does not end the mode.
            MouseArea {
                anchors.fill: parent
            }

            Row {
                id: tools

                anchors.centerIn: parent
                spacing: Theme.px(8)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: Theme.px(10)
                    rightPadding: Theme.px(6)
                    text: "Edit widgets"
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.px(14)
                    font.weight: Font.DemiBold
                    color: Theme.fg
                }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Add widget"
                    icon: Theme.iconPlus
                    onClicked: root.adding = !root.adding
                }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Settings"
                    icon: Theme.iconSettings
                    onClicked: Widgets.toggleSettings()
                }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Done"
                    primary: true
                    onClicked: Widgets.toggleEditing()
                }
            }
        }

        // The gallery: one of each kind, at the free place nearest the top left.
        Rectangle {
            visible: root.adding
            anchors.horizontalCenter: toolbar.horizontalCenter
            y: toolbar.y + toolbar.height + Theme.px(8)
            width: kindsRow.implicitWidth + Theme.px(16)
            height: kindsRow.implicitHeight + Theme.px(16)
            radius: Theme.px(16)
            color: Theme.surfaceBg
            border.width: Theme.surfaceBorder
            border.color: Theme.surfaceLine

            MouseArea {
                anchors.fill: parent
            }

            Row {
                id: kindsRow

                anchors.centerIn: parent
                spacing: Theme.px(6)

                Repeater {
                    model: Widgets.kinds

                    Rectangle {
                        id: kindTile

                        required property var modelData

                        width: Theme.px(96)
                        height: Theme.px(40)
                        radius: Theme.px(10)
                        color: kindArea.containsMouse ? Theme.surfaceRaisedHover : Theme.surfaceRaised

                        Text {
                            anchors.centerIn: parent
                            text: kindTile.modelData.title
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(13)
                            font.weight: Font.Medium
                            color: Theme.fg
                        }

                        MouseArea {
                            id: kindArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Widgets.add(root.screenName, kindTile.modelData.kind, root.width, root.height, root.top);
                                root.adding = false;
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.px(28)
            text: "drag to move, S M L to resize, the corner's minus to remove, esc or a click on the empty screen to finish"
            font.family: Theme.uiFont
            font.pixelSize: Theme.px(12)
            color: Theme.fg
            style: Text.Outline
            styleColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.8)
        }
    }
}
