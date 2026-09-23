pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The notification daemon (org.freedesktop.Notifications) and its history.
// No other daemon is installed. A singleton: a second server would lose the bus
// name, and the history must outlive any window showing it.
Singleton {
    id: root

    readonly property int historyLimit: 100

    property var history: []

    // Derived from history, never counted separately, so it cannot drift.
    readonly property int unread: root.history.filter(e => !e.read).length

    // Here, not in the panel: the bar pill toggles it and sibling modules
    // cannot reach each other's properties.
    property bool centreOpen: false

    function toggleCentre() {
        root.centreOpen = !root.centreOpen;
        if (root.centreOpen)
            root.markRead();
    }

    signal toast(var entry)

    // Arrival times by id, kept across reloads. The server replays retained
    // notifications through add() after a reload, and a Notification carries no
    // arrival time, so without this every timestamp collapses onto the reload.
    PersistentProperties {
        id: arrivals

        reloadableId: "notificationArrivals"

        // A JSON string, not an object: a JS object cannot cross into the new
        // engine ("JSValue can't be reassigned to another engine") and arrives
        // undefined.
        property string times: "{}"
    }

    function arrivalMap() {
        try {
            return JSON.parse(arrivals.times);
        } catch (e) {
            return {};
        }
    }

    function arrivalOf(id) {
        const m = root.arrivalMap();
        if (m[id] !== undefined)
            return m[id];
        const now = Date.now();
        m[id] = now;
        arrivals.times = JSON.stringify(m);
        return now;
    }

    // Drops ids the history no longer holds, or the map grows all session.
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

    // notify-send fills app_name with its own basename when no --app-name is
    // given, which names no application.
    function senderName(raw) {
        if (!raw || raw === "notify-send" || raw === "notify-desktop")
            return "";
        return raw;
    }

    // Bodies render as StyledText, which fetches any <img src=...>: any bus
    // client could make this process request an arbitrary URL. Icons travel in
    // app_icon, so <img> is stripped once here and other markup keeps working.
    function withoutImages(text: string): string {
        return text.replace(/<\s*img\b[^>]*>?/gi, "");
    }

    function snapshot(n) {
        // Copied into a plain object: the history outlives the Notification.
        // "default" is the click-the-body action and the spec says not to show
        // it as a button; unlabelled actions are skipped too.
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
            body: root.withoutImages(n.body || ""),
            // Critical never expires on a timer.
            critical: n.urgency === NotificationUrgency.Critical,
            actions: actions,
            hasDefault: hasDefault,
            at: root.arrivalOf(n.id),
            read: false,
            // Only for invoking actions later; read nothing else off it.
            live: n
        };
    }

    function add(n) {
        // Arriving into an open panel counts as read.
        const entry = root.snapshot(n);
        entry.read = root.centreOpen;

        const next = [entry].concat(root.history);
        if (next.length > root.historyLimit) {
            for (let i = root.historyLimit; i < next.length; i++)
                root.release(next[i]);
            next.length = root.historyLimit;
        }
        root.history = next;
        root.prune();

        root.toast(entry);
    }

    function dismiss(id) {
        const next = [];
        for (let i = 0; i < root.history.length; i++) {
            if (root.history[i].id !== id)
                next.push(root.history[i]);
            else
                root.release(root.history[i]);
        }
        root.history = next;
        root.prune();
    }

    function clear() {
        for (let i = 0; i < root.history.length; i++)
            root.release(root.history[i]);
        root.history = [];
        root.prune();
    }

    // tracked keeps a Notification alive past its close; clear it on every path
    // that drops an entry, or the server holds them all session.
    function release(entry) {
        if (entry && entry.live)
            entry.live.tracked = false;
    }

    // Rebuilt, not mutated: a var property notifies only on reassignment.
    function markRead() {
        root.history = root.history.map(e => Object.assign({}, e, { read: true }));
    }

    // An action only works while the sender is running; warn instead of
    // failing silently.
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

        // Advertise only what is rendered; senders format for these claims.
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        // Retained notifications are handed back after a reload (see arrivals).
        // tracked = true below is what keeps each one alive past its close.
        keepOnReload: true

        onNotification: notification => {
            notification.tracked = true;
            root.add(notification);
        }
    }
}
