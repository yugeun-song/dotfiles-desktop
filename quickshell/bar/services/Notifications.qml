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

    property var history: []

    // Derived, never counted. Five separate paths used to move a number that
    // history already answers: dismiss() rebuilt the list without touching it,
    // historyLimit truncated the list while the counter kept climbing, the
    // panel zeroed it on click, and a notification arriving into the open
    // panel incremented it. A count kept beside the thing it counts can only
    // be wrong in ways the thing itself cannot.
    readonly property int unread: root.history.filter(e => !e.read).length

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

    // Arrival times, kept across a configuration reload.
    //
    // The server hands its retained notifications back after every reload and
    // add() runs on each one, so every timestamp in the history used to collapse
    // onto the moment of the reload: thirty notifications spanning an hour all
    // reading the same second. It went unnoticed while the display was hours and
    // minutes and the reload usually fell in the same minute.
    //
    // There is nothing to recover the real time from. A Notification carries an
    // id, its text, an urgency and an expireTimeout, and no arrival time. So the
    // times are kept here, in the one thing whose contents outlive a reload.
    PersistentProperties {
        id: arrivals

        reloadableId: "notificationArrivals"

        // JSON, not an object. These values are carried across a reload into a
        // new QML engine and a JS object cannot make that crossing: quickshell
        // reports "JSValue can't be reassigned to another engine" and the
        // property arrives undefined, which is worse than not persisting at
        // all because every read of it then throws. A string crosses.
        property string times: "{}"
    }

    function arrivalMap() {
        try {
            return JSON.parse(arrivals.times);
        } catch (e) {
            return {};
        }
    }

    // The time this id first arrived, remembered the first time it is asked for.
    function arrivalOf(id) {
        const m = root.arrivalMap();
        if (m[id] !== undefined)
            return m[id];
        const now = Date.now();
        m[id] = now;
        arrivals.times = JSON.stringify(m);
        return now;
    }

    // Anything the history no longer holds. Without this the map is the only
    // thing here that never forgets, and it grows for as long as the session.
    function prune() {
        const m = root.arrivalMap();
        const live = {};
        for (let i = 0; i < root.history.length; i++) {
            const e = root.history[i];
            if (m[e.id] !== undefined)
                live[e.id] = m[e.id];
        }
        arrivals.times = JSON.stringify(live);
    }

    // The sending utility puts its own basename in app_name when the caller
    // passes no --app-name, so "notify-send" means nobody identified themselves
    // rather than naming an application. Labelling every scripted notification
    // with the tool that sent it tells a reader nothing they cannot see.
    function senderName(raw) {
        if (!raw || raw === "notify-send" || raw === "notify-desktop")
            return "";
        return raw;
    }

    // A notification is kept after it is closed, which is the whole point of a
    // history, so each one is copied into a plain object as it arrives. Holding
    // the Notification itself would mean reading properties off an object the
    // server has already destroyed.
    function snapshot(n) {
        // Two kinds of action never become a button.
        //
        // "default" is what the sender wants run when the notification itself is
        // clicked, and the freedesktop spec says it should not be displayed as
        // one. Claude Code sends it with no label, so drawing it produced an
        // empty chip that did nothing a reader could predict.
        //
        // Anything else with no label is the same problem without the excuse:
        // a button whose text is blank cannot say what pressing it does.
        const actions = [];
        let hasDefault = false;
        for (let i = 0; i < n.actions.length; i++) {
            const a = n.actions[i];
            if (a.identifier === "default") {
                hasDefault = true;
                continue;
            }
            if (!a.text || a.text.trim() === "")
                continue;
            actions.push({ text: a.text, identifier: a.identifier });
        }
        return {
            id: n.id,
            appName: root.senderName(n.appName),
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body: n.body || "",
            // 2 is Critical in the freedesktop spec, which is the only level
            // worth treating differently: it is what "your battery is about to
            // die" uses, and it should not disappear on a timer.
            critical: n.urgency === NotificationUrgency.Critical,
            actions: actions,
            hasDefault: hasDefault,
            at: root.arrivalOf(n.id),
            read: false,
            // Kept so an action can still be invoked from the history while the
            // sender is alive. Reading anything else off it after close is not
            // safe; see snapshot above.
            live: n
        };
    }

    function add(n) {
        // Already read if it arrived into an open panel: the user is looking at
        // it as it lands. Counting it unread there left a badge that outlived
        // the reading of every notification it stood for.
        const entry = root.snapshot(n);
        entry.read = root.centreOpen;

        const next = [entry].concat(root.history);
        if (next.length > root.historyLimit)
            next.length = root.historyLimit;
        root.history = next;
        root.prune();

        root.toast(entry);
    }

    function dismiss(id) {
        const next = [];
        for (let i = 0; i < root.history.length; i++)
            if (root.history[i].id !== id)
                next.push(root.history[i]);
        root.history = next;
        root.prune();
    }

    function clear() {
        root.history = [];
        root.prune();
    }

    // Rebuilt rather than marked in place: unread is a binding over history, and
    // a var property only tells its dependents anything when it is reassigned.
    function markRead() {
        root.history = root.history.map(e => Object.assign({}, e, { read: true }));
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
