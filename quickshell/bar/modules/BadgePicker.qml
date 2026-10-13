pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The system badge's menu: Automatic, which follows /etc/os-release, and
// every distribution mark the icon font has, as a grid (a list of them ran
// taller than the panel). The name of the mark under the pointer, else the
// chosen one, is written under the grid.
Item {
    id: root

    property Item anchorItem: root.parent
    property bool open: false
    property string hoveredName: ""

    readonly property int columns: 8
    readonly property int tile: Theme.px(44)
    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property int clearance: Theme.pillMargin + Theme.tooltipGap

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

            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: 0
                rect.y: -root.clearance
                rect.width: root.anchorItem?.width ?? 0
                rect.height: (root.anchorItem?.height ?? 0) + root.clearance * 2
                edges: root.edge
                gravity: root.edge
            }

            Rectangle {
                id: body

                scale: popup.fit
                transformOrigin: Item.TopLeft
                implicitWidth: content.implicitWidth + Theme.px(20)
                implicitHeight: content.implicitHeight + Theme.px(20)
                radius: Theme.tooltipRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                Column {
                    id: content

                    anchors.centerIn: parent
                    spacing: Theme.px(6)

                    Rectangle {
                        id: automatic

                        width: grid.width
                        height: Theme.px(38)
                        radius: Theme.px(9)
                        color: autoHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                        Text {
                            id: autoCheck

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.px(12)
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSize
                            horizontalAlignment: Text.AlignHCenter
                            text: Badge.choice === "auto" ? Theme.iconCheck : ""
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(17)
                            color: Theme.accentGreen
                        }

                        Text {
                            anchors.left: autoCheck.right
                            anchors.leftMargin: Theme.px(10)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Automatic"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.menuTextSize
                            font.weight: Font.Medium
                            color: Theme.fg
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.px(13)
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: `${Badge.autoMark.name}, from /etc/os-release`
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(12)
                            color: Theme.muted
                        }

                        HoverHandler {
                            id: autoHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pick("auto")
                        }
                    }

                    Grid {
                        id: grid

                        columns: root.columns
                        spacing: Theme.px(4)

                        Repeater {
                            model: Badge.offered

                            Rectangle {
                                id: cell

                                required property var modelData

                                width: root.tile
                                height: root.tile
                                radius: Theme.px(9)
                                // The choice as the menus mark an on state;
                                // the hover tint over the rest.
                                color: Badge.choice === cell.modelData.id
                                       ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
                                       : cellHover.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(cell.modelData.cp)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Math.round(Theme.px(30) * (cell.modelData.scale ?? 1))
                                    color: Theme.fg
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
                        width: grid.width
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: root.hoveredName !== "" ? root.hoveredName : Badge.current.name
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(12)
                        color: Theme.muted
                        bottomPadding: Theme.px(2)
                    }
                }
            }
        }
    }
}
