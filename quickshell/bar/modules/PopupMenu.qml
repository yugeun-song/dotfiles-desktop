pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Menu anchored to a bar item, as the menus the user sent
// (2026-10-27): hung just under the bar from the item's left edge, its rows
// (MenuRow) Theme.barMenuPad in from all four edges, long sideways and only
// slightly round (the same, 2026-11-07; Theme.barMenu*). Entries: { label, icon,
// detail, checked, checkable, action } or { separator: true }. The menu
// closes before `action` runs, so a window it opens does not fight the menu
// for focus.
Item {
    id: root

    property var entries: []
    property Item anchorItem: root.parent
    property bool open: false
    property int minimumWidth: Theme.barMenuMinWidth

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property bool lead: root.entries.some(e => (e.icon ?? "") !== "" || e.checkable === true || e.checked === true)

    // As wide as its columns, as the references set it: the widest label, then
    // the widest detail. Measured with hidden Text items, not a TextMetrics
    // reused in a loop (that is a binding loop). Only the wrapper is hidden:
    // a Column ignores invisible children in its implicit size. A menu of words
    // alone keeps some way clear after the longest, or it would read narrow again.
    readonly property int menuWidth: {
        const labels = Math.ceil(labelColumn.implicitWidth);
        const details = Math.ceil(detailColumn.implicitWidth);
        return Math.max(root.minimumWidth,
                        (Theme.barMenuPad + Theme.barMenuRowPad) * 2 + (root.lead ? Theme.menuLeadWidth : 0) + labels
                        + (details > 0 ? Theme.menuDetailGap + details : Theme.barMenuTailWidth));
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
            // Room for its shadow (Theme.shadowRoom) on the two sides away from
            // where it hangs: to its right and, under a bar at the top, below
            // it. The corner it hangs from stays where it was, so the menu
            // does too; the shadow's other sides, short at a light from above,
            // are left out. Never past the screen's right edge, where the
            // window would be slid in and the menu with it. Only the menu takes
            // the pointer (mask), so a click on its shadow closes it as any
            // click outside does.
            readonly property var room: Theme.shadowRoom("menu")
            readonly property int menuW: Math.round(body.implicitWidth * popup.fit)
            readonly property int menuH: Math.round(body.implicitHeight * popup.fit)
            readonly property real itemX: root.anchorItem?.mapToItem(null, 0, 0).x ?? 0
            readonly property real screenW: root.QsWindow.window?.width ?? 0
            readonly property int right: Math.max(0, Math.min(Math.round(popup.room.side * popup.fit),
                                                             Math.floor(popup.screenW - popup.itemX - popup.menuW)))
            readonly property int below: Theme.barAtBottom ? 0 : Math.round(popup.room.bottom * popup.fit)

            implicitWidth: popup.menuW + popup.right
            implicitHeight: popup.menuH + popup.below
            mask: Region {
                width: popup.menuW
                height: popup.menuH
            }

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

            SurfaceShadow {
                target: body
                kind: "menu"
            }

            Rectangle {
                id: body

                scale: popup.fit
                transformOrigin: Item.TopLeft
                implicitWidth: root.menuWidth
                implicitHeight: column.implicitHeight + Theme.barMenuPad * 2
                radius: Theme.barMenuRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                Column {
                    id: column

                    x: Theme.barMenuPad
                    y: Theme.barMenuPad
                    width: root.menuWidth - Theme.barMenuPad * 2

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
                            rowHeight: Theme.barMenuRowHeight
                            separatorHeight: Theme.barMenuSeparatorHeight
                            rowPad: Theme.barMenuRowPad
                            rowRadius: Theme.barMenuRowRadius
                            ruleInset: Theme.barMenuRowPad

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
