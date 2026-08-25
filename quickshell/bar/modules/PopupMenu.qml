pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// A small menu anchored to a bar item. Entries are plain objects:
//   { label, icon, detail, checked, action }
// `action` is a function called on click. The menu closes first, so an
// action that opens a window does not fight the menu for focus.
Item {
    id: root

    property var entries: []
    property Item anchorItem: root.parent
    property bool open: false
    property int minimumWidth: Theme.px(200)

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property int clearance: Theme.pillMargin + Theme.px(6)

    signal closed

    function toggle() {
        root.open = !root.open;
    }

    function dismiss() {
        root.open = false;
        root.closed();
    }

    Loader {
        active: root.open && root.entries.length > 0

        sourceComponent: PopupWindow {
            id: popup

            visible: true
            color: "transparent"
            grabFocus: true
            implicitWidth: body.implicitWidth
            implicitHeight: body.implicitHeight

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

                implicitWidth: Math.max(root.minimumWidth, column.implicitWidth + Theme.px(16))
                implicitHeight: column.implicitHeight + Theme.px(10)
                radius: Theme.tooltipRadius
                color: Theme.bgAlt
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                Column {
                    id: column

                    anchors.centerIn: parent
                    width: body.width - Theme.px(10)
                    spacing: 0

                    Repeater {
                        model: root.entries

                        Rectangle {
                            id: row

                            required property var modelData

                            readonly property bool isSeparator: row.modelData.separator === true

                            width: column.width
                            height: row.isSeparator ? Theme.px(9) : Theme.px(30)
                            radius: Theme.px(7)
                            color: hover.hovered && !row.isSeparator ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                            Rectangle {
                                visible: row.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - Theme.px(10)
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }

                            Row {
                                visible: !row.isSeparator
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.px(9)
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.px(9)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.px(8)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.iconSize
                                    horizontalAlignment: Text.AlignHCenter
                                    text: row.modelData.checked === true ? Theme.iconCheck : (row.modelData.icon ?? "")
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.px(14)
                                    color: row.modelData.checked === true ? Theme.accentGreen : Theme.muted
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.label ?? ""
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.textSize
                                    font.weight: Font.Medium
                                    color: Theme.fg
                                }
                            }

                            Text {
                                visible: !row.isSeparator && (row.modelData.detail ?? "") !== ""
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.px(10)
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.detail ?? ""
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(11)
                                color: Theme.muted
                            }

                            HoverHandler {
                                id: hover

                                enabled: !row.isSeparator
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !row.isSeparator
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    const act = row.modelData.action;
                                    root.dismiss();
                                    if (typeof act === "function")
                                        act();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
