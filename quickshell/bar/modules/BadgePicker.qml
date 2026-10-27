pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The system badge's menu, set as PopupMenu is (Theme.menu*), padded alike
// on all four sides: Automatic, which follows /etc/os-release, then every
// distribution mark the icon font has, as a grid (a list of them ran taller
// than the panel). The name of the mark under the pointer, else the chosen
// one, is written under the grid.
Item {
    id: root

    property Item anchorItem: root.parent
    property bool open: false
    property string hoveredName: ""

    readonly property int columns: 8
    // The marks 1.33 of the text's em across, as large as the menu drew them
    // before it was made smaller: at the badge's own size the user found them
    // small (2026-10-27). The font's marks are 0.586 em at their widest, a
    // taller one brought down by its scale. A tile keeps round its mark what
    // a row keeps above and below its text, and tiles meet as rows do.
    readonly property int markInk: Math.round(1.33 * Theme.menuTextSize)
    readonly property real markSize: root.markInk / 0.586
    readonly property int tile: root.markInk + Theme.menuRowHeight - Math.round(Theme.menuCap)
    readonly property int gridWidth: root.columns * root.tile
    // Wide enough for Automatic's own columns too.
    readonly property int innerWidth: Math.max(root.gridWidth,
                                               Theme.menuRowPad * 2 + Theme.menuLeadWidth + Math.ceil(autoLabel.implicitWidth)
                                               + Theme.menuDetailGap + Math.ceil(autoDetail.implicitWidth))
    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom

    function toggle() {
        root.open = !root.open;
    }

    function dismiss() {
        root.open = false;
        root.hoveredName = "";
    }

    function pick(id) {
        Badge.choose(id);
        root.dismiss();
    }

    Text {
        id: autoLabel

        visible: false
        text: "Automatic"
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuTextSize
    }

    Text {
        id: autoDetail

        visible: false
        textFormat: Text.PlainText
        text: Badge.autoMark.name
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuTextSize
    }

    Loader {
        active: root.open

        sourceComponent: PopupWindow {
            id: popup

            // grabFocus lets the compositor close this on an outside click;
            // synced back into `open`, as PopupMenu does.
            visible: root.open
            onVisibleChanged: {
                if (!popup.visible)
                    root.dismiss();
            }

            readonly property real fit: Theme.fit(root.QsWindow.window?.screen)

            color: "transparent"
            grabFocus: true
            implicitWidth: Math.round(body.implicitWidth * popup.fit)
            implicitHeight: Math.round(body.implicitHeight * popup.fit)

            // Hung from the badge's left edge, as PopupMenu hangs.
            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: 0
                rect.y: -Theme.menuGap
                rect.width: root.anchorItem?.width ?? 0
                rect.height: (root.anchorItem?.height ?? 0) + Theme.menuGap * 2
                edges: root.edge | Edges.Left
                gravity: root.edge | Edges.Right
                adjustment: PopupAdjustment.Slide
            }

            Rectangle {
                id: body

                scale: popup.fit
                transformOrigin: Item.TopLeft
                implicitWidth: root.innerWidth + Theme.menuPad * 2
                implicitHeight: content.implicitHeight + Theme.menuPad * 2
                radius: Theme.menuRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                Column {
                    id: content

                    x: Theme.menuPad
                    y: Theme.menuPad
                    width: root.innerWidth

                    MenuRow {
                        width: content.width
                        label: "Automatic"
                        detail: Badge.autoMark.name
                        checked: Badge.choice === "auto"
                        lead: true
                        onActivated: root.pick("auto")
                    }

                    MenuRow {
                        width: content.width
                        separator: true
                    }

                    Grid {
                        id: grid

                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: root.columns

                        Repeater {
                            model: Badge.offered

                            Rectangle {
                                id: cell

                                required property var modelData

                                width: root.tile
                                height: root.tile
                                radius: Theme.menuRowRadius
                                // Lit as a row is; the choice as the bar marks
                                // an open item.
                                color: cellHover.hovered ? Theme.menuHighlight
                                       : Badge.choice === cell.modelData.id
                                         ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(cell.modelData.cp)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Math.round(root.markSize * (cell.modelData.scale ?? 1))
                                    color: cellHover.hovered ? Theme.menuHighlightText : Theme.fg
                                }

                                HoverHandler {
                                    id: cellHover

                                    onHoveredChanged: {
                                        if (cellHover.hovered)
                                            root.hoveredName = cell.modelData.name;
                                        else if (root.hoveredName === cell.modelData.name)
                                            root.hoveredName = "";
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pick(cell.modelData.id)
                                }
                            }
                        }
                    }

                    Text {
                        width: content.width
                        height: Theme.menuRowHeight
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: root.hoveredName !== "" ? root.hoveredName : Badge.current.name
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.menuTextSize
                        color: Theme.muted
                    }
                }
            }
        }
    }
}
