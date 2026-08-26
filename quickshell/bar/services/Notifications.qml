pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The notification daemon, and the history behind it.
//
// Nothing owned org.freedesktop.Notifications on this machine before this
// existed. mako was in the package list and was never installed, so every
// notification the desktop sent went nowhere: capture.sh announcing a saved
// screenshot, session-autostart.sh reporting that it could not start something.
// They were not lost noisily, they were simply never delivered.
//
// The server lives here rather than in a module because a second copy would try
// to take the same bus name and lose, and because the history has to outlive
// any window that shows it.
Singleton {
    id: root

    // How much to keep. Long enough that "what did that say" is answerable an
    // hour later, short enough that it stays in memory without thought.
    readonly property int historyLimit: 100

    // Notifications that have not been looked at since they arrived. The count
    // the bar shows, and what "mark all read" clears.
    property int unread: 0

    property var history: []

    // Whether the history panel is showing. It lives here rather than in the
    // panel because the bar's pill toggles it and the panel renders it, and a
    // module cannot reach a sibling module's property.
    property bool centreOpen: false

    function toggleCentre() {
        root.centreOpen = !root.centreOpen;
        // Opening the panel is the act of reading, so the count clears there.
        if (root.centreOpen)
            root.markRead();
    }

    signal toast(var entry)

    // A notification is kept after it is closed, which is the whole point of a
    // history, so each one is copied into a plain object as it arrives. Holding
    // the Notification itself would mean reading properties off an object the
    // server has already destroyed.
    function snapshot(n) {
        const actions = [];
        for (let i = 0; i < n.actions.length; i++) {
            actions.push({
                text: n.actions[i].text,
                identifier: n.actions[i].identifier
            });
        }
        return {
            id: n.id,
            appName: n.appName || "Notification",
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body: n.body || "",
            // 2 is Critical in the freedesktop spec, which is the only level
            // worth treating differently: it is what "your battery is about to
            // die" uses, and it should not disappear on a timer.
            critical: n.urgency === NotificationUrgency.Critical,
            actions: actions,
            at: Date.now(),
            // Kept so an action can still be invoked from the history while the
            // sender is alive. Reading anything else off it after close is not
            // safe; see snapshot above.
            live: n
        };
    }

    function add(n) {
        const entry = root.snapshot(n);

        const next = [entry].concat(root.history);
        if (next.length > root.historyLimit)
            next.length = root.historyLimit;
        root.history = next;
        root.unread = root.unread + 1;

        root.toast(entry);
    }

    function dismiss(id) {
        const next = [];
        for (let i = 0; i < root.history.length; i++)
            if (root.history[i].id !== id)
                next.push(root.history[i]);
        root.history = next;
    }

    function clear() {
        root.history = [];
        root.unread = 0;
    }

    function markRead() {
        root.unread = 0;
    }

    // Invoking an action tells the sending application to do something, which
    // it can only do while it is still running. An action on a notification
    // from a program that has since exited does nothing, and saying so is
    // better than a button that silently fails.
    function invoke(entry, identifier) {
        if (!entry.live) {
            console.warn("[notifications] the sender is gone; cannot run", identifier);
            return false;
        }
        const acts = entry.live.actions;
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].identifier === identifier) {
                acts[i].invoke();
                return true;
            }
        }
        console.warn("[notifications] no action", identifier, "on", entry.summary);
        return false;
    }

    NotificationServer {
        id: server

        // Everything this shell can actually honour, and nothing it cannot.
        // Claiming a capability that is not implemented makes senders format
        // for a renderer that is not there.
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        // The notification object is destroyed when it closes unless something
        // asks to keep it. The history needs it alive to invoke actions later.
        keepOnReload: true

        onNotification: notification => {
            notification.tracked = true;
            root.add(notification);
        }
    }
}
