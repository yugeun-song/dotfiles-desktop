pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Menu anchored to a bar item, as the menus the user sent
// (2026-10-27): hung just under the bar from the item's left edge, its rows
// (MenuRow) Theme.menuPad in from all four edges. Entries: { label, icon,
// detail, checked, checkable, action } or { separator: true }. The menu
// closes before `action` runs, so a window it opens does not fight the menu
// for focus.
Item {
    id: root

    property var entries: []
    property Item anchorItem: root.parent
    property bool open: false
    property int minimumWidth: Theme.menuMinWidth

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property bool lead: root.entries.some(e => (e.icon ?? "") !== "" || e.checkable === true || e.checked === true)

    // As wide as its columns, as the references set it: the widest label, then
    // the widest detail. Measured with hidden Text items, not a TextMetrics
    // reused in a loop (that is a binding loop). Only the wrapper is hidden:
    // a Column ignores invisible children in its implicit size.
    readonly property int menuWidth: {
        const labels = Math.ceil(labelColumn.implicitWidth);
        const details = Math.ceil(detailColumn.implicitWidth);
        return Math.max(root.minimumWidth,
                        (Theme.menuPad + Theme.menuRowPad) * 2 + (root.lead ? Theme.menuLeadWidth : 0) + labels
                        + (details > 0 ? Theme.menuDetailGap + details : 0));
    }

    Item {
        visible: false

        Column {
            id: labelColumn

            Repeater {
                model: root.entries

                Text {
                    required property var modelData

                    textFormat: Text.PlainText
                    text: modelData.separator === true ? "" : (modelData.label ?? "")
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.menuItemTextSize
                }
            }
        }

        Column {
            id: detailColumn

            Repeater {
                model: root.entries

                Text {
                    required property var modelData

                    textFormat: Text.PlainText
                    text: modelData.separator === true ? "" : (modelData.detail ?? "")
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.menuItemTextSize
                }
            }
        }
    }

    signal opened
    signal closed

    function toggle() {
        if (root.open) {
            root.dismiss();
        } else {
            root.open = true;
            root.opened();
        }
    }

    function dismiss() {
        if (!root.open)
            return;
        root.open = false;
        root.closed();
    }

    Loader {
        active: root.open && root.entries.length > 0

        sourceComponent: PopupWindow {
            id: popup

            // grabFocus lets the compositor close this on an outside click;
            // sync that back into `open` or the next click only resets it.
            visible: root.open
            onVisibleChanged: {
                if (!popup.visible)
                    root.dismiss();
            }

            // The menu's share of the bar's screen, as on the reference output.
            readonly property real fit: Theme.fit(root.QsWindow.window?.screen)

            color: "transparent"
            grabFocus: true
            implicitWidth: Math.round(body.implicitWidth * popup.fit)
            implicitHeight: Math.round(body.implicitHeight * popup.fit)

            // The item's left edge is the menu's, as the references hang a
            // menu from its title; slid along the bar, never flipped to the
            // item's other side, where it would run off the screen.
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
                implicitWidth: root.menuWidth
                implicitHeight: column.implicitHeight + Theme.menuPad * 2
                radius: Theme.menuRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                Column {
                    id: column

                    x: Theme.menuPad
                    y: Theme.menuPad
                    width: root.menuWidth - Theme.menuPad * 2

                    Repeater {
                        model: root.entries

                        MenuRow {
                            id: row

                            required property var modelData

                            width: column.width
                            separator: row.modelData.separator === true
                            label: row.modelData.label ?? ""
                            icon: row.modelData.icon ?? ""
                            detail: row.modelData.detail ?? ""
                            checked: row.modelData.checked === true
                            lead: root.lead
                            textSize: Theme.menuItemTextSize

                            onActivated: {
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
