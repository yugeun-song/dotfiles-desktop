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

    // Entries carry message text, codes and links, and only the history keeps
    // them past their toast; a day still covers "since yesterday". Checked
    // every ten minutes.
    readonly property int keepHours: 24

    property var history: []

    // Derived from history, never counted separately, so it cannot drift.
    readonly property int unread: root.history.filter(e => !e.read).length

    // Here, not in the panel: the bar pill toggles it and sibling modules
    // cannot reach each other's properties.
    property bool centreOpen: false
    // The panel on screen, its way out included (NotificationCentre.qml):
    // the toasts wait for it rather than enter where it is going.
    property bool centreShown: false

    function toggleCentre() {
        root.centreOpen = !root.centreOpen;
        if (root.centreOpen)
            root.markRead();
    }

    signal toast(var entry)

    // Arrival times by id, kept across reloads: the server replays retained
    // notifications through add(), and a Notification carries no arrival time,
    // so every timestamp would collapse onto the reload.
    PersistentProperties {
        id: arrivals

        reloadableId: "notificationArrivals"

        // A JSON string: a JS object arrives undefined in the new engine
        // ("JSValue can't be reassigned to another engine").
        property string times: "{}"

        // Ids marked read, for the same reason: a replayed notification is
        // rebuilt from scratch and would come back unread.
        property string reads: "[]"
    }

    function wasRead(id) {
        try {
            return JSON.parse(arrivals.reads).indexOf(id) !== -1;
        } catch (e) {
            return false;
        }
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

    // Drops ids the history no longer holds, or the map grows all session,
    // and records which are read.
    function prune() {
        const m = root.arrivalMap();
        const live = {};
        const read = [];
        for (let i = 0; i < root.history.length; i++) {
            const e = root.history[i];
            if (m[e.id] !== undefined)
                live[e.id] = m[e.id];
            if (e.read)
                read.push(e.id);
        }
        arrivals.times = JSON.stringify(live);
        arrivals.reads = JSON.stringify(read);
    }

    // notify-send fills app_name with its own basename when no --app-name is
    // given, which names no application.
    function senderName(raw) {
        if (!raw || raw === "notify-send" || raw === "notify-desktop")
            return "";
        return raw;
    }

    // StyledText fetches any <img src=...>, so any bus client could make the
    // bar request a URL; icons travel in app_icon. Stripped until nothing
    // changes: one pass turned <im<img>g src=...> into a whole <img>.
    function withoutImages(text: string): string {
        let out = text;
        for (;;) {
            const next = out.replace(/<\s*img\b[^>]*>?/gi, "");
            if (next === out)
                return out;
            out = next;
        }
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
        root.serial += 1;
        return {
            id: n.id,
            // This snapshot's own, for the toasts' model: a replaced
            // notification gets a new card, not the old one with old text.
            key: root.serial,
            appName: root.senderName(n.appName),
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body: root.withoutImages(n.body || ""),
            // Drawn in red, and toasted longer (NotificationToasts.criticalDwellMs).
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
        const entry = root.snapshot(n);
        // Handed back after a reload (lastGeneration), a notification is not
        // news: it was toasted when it came, and keeps its read mark; taken as
        // new, every reload toasted the history again, all of it unread.
        const replayed = n.lastGeneration === true;
        // Arriving into an open panel counts as read.
        entry.read = replayed ? root.wasRead(n.id) : root.centreOpen;

        const next = [entry].concat(root.history);
        // Replays come back in no promised order; newest first by arrival.
        if (replayed)
            next.sort((a, b) => b.at - a.at);
        if (next.length > root.historyLimit) {
            for (let i = root.historyLimit; i < next.length; i++)
                root.release(next[i]);
            next.length = root.historyLimit;
        }
        root.history = next;
        // Not while replaying: the history is still partial, and a prune
        // would drop the times and read marks of those yet to come back.
        if (replayed)
            return;
        root.prune();
        root.toast(entry);
    }

    property int serial: 0

    // A replaced notification (replaces_id: notify-send -r, a reused libnotify
    // object) changes in place and the server emits nothing new: the entry is
    // refreshed and toasted again here, queued so that a summary and body
    // changed together make one toast.
    property var refreshing: ({})

    function follow(n) {
        const queue = () => {
            root.refreshing[n.id] = n;
            Qt.callLater(root.refreshQueued);
        };
        n.summaryChanged.connect(queue);
        n.bodyChanged.connect(queue);
        n.actionsChanged.connect(queue);
        n.urgencyChanged.connect(queue);
    }

    function refreshQueued() {
        const queued = root.refreshing;
        root.refreshing = ({});
        for (const id in queued)
            root.refresh(queued[id]);
    }

    function refresh(n) {
        const i = root.history.findIndex(e => e.id === n.id);
        if (i < 0)
            return;
        const entry = root.snapshot(n);
        entry.at = root.history[i].at;
        entry.read = root.centreOpen;
        const next = root.history.slice();
        next[i] = entry;
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

    // tracked keeps a Notification alive past its close; cleared on every path
    // that drops an entry, or the server holds them all session. The entry
    // gives its text up too, as its object can outlive the list; that drops
    // references, not bytes, which is why the bar writes no core (bin/bar).
    function release(entry) {
        if (!entry)
            return;
        if (entry.live)
            entry.live.tracked = false;
        entry.live = null;
        entry.summary = "";
        entry.body = "";
        entry.actions = [];
    }

    function expire() {
        const cutoff = Date.now() - root.keepHours * 3600000;
        if (!root.history.some(e => e.at < cutoff))
            return;
        const next = [];
        for (let i = 0; i < root.history.length; i++) {
            if (root.history[i].at < cutoff)
                root.release(root.history[i]);
            else
                next.push(root.history[i]);
        }
        root.history = next;
        root.prune();
    }

    // Not at start: after a reload the history comes back one replay at a
    // time, and a prune then would drop the marks of those still to come.
    Timer {
        interval: 600000
        repeat: true
        running: true

        onTriggered: root.expire()
    }

    // Rebuilt, not mutated: a var property notifies only on reassignment.
    function markRead() {
        root.history = root.history.map(e => Object.assign({}, e, { read: true }));
        root.prune();
    }

    // An action only works while the sender is running; warn instead of
    // failing silently. A destroyed Notification is still a truthy reference
    // whose properties read undefined, so tracked is what tells it apart.
    function invoke(entry, identifier) {
        const acts = entry.live?.tracked === true ? entry.live.actions : undefined;
        if (!acts) {
            console.warn("[notifications] the sender is gone; cannot run", identifier);
            return false;
        }
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].identifier === identifier) {
                acts[i].invoke();
                return true;
            }
        }
        // The id, not the summary: a summary can be a message's text, and the
        // journal keeps what is logged.
        console.warn("[notifications] no action", identifier, "on notification", entry.id);
        return false;
    }

    NotificationServer {
        id: server

        // Advertise only what is rendered; senders format for these claims.
        // No images: nothing draws them, and a sender that is told so keeps
        // its picture (a chat's avatar, a photo) out of the history.
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: false

        // Retained notifications are handed back after a reload (see arrivals).
        // tracked = true below is what keeps each one alive past its close.
        keepOnReload: true

        onNotification: notification => {
            notification.tracked = true;
            root.add(notification);
            root.follow(notification);
        }
    }
}
