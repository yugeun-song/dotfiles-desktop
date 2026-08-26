pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // State is a plain JSON file managed by scripts/alarm.sh. Watching the
    // file means the bar needs no IPC and picks up changes made from any
    // terminal immediately.
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") ?? `${Quickshell.env("HOME")}/.local/state`) + "/quickshell-bar/alarms.json"

    property var entries: []
    property var ringing: null

    // When `entries` was last accepted from the file. The list is deliberately
    // kept across a failed load -- a half-written file must not erase every
    // alarm -- so its age is the only thing separating "these are the alarms"
    // from "these were the alarms".
    property double asOf: 0

    // Filtered against nowSeconds rather than a captured Date.now(): a binding
    // only re-runs on its dependencies, so a wall time read here would freeze
    // the list at the last file change and leave a past alarm showing "0m".
    readonly property var pending: root.entries.filter(a => a.epoch > root.nowSeconds).sort((a, b) => a.epoch - b.epoch)

    readonly property var next: root.pending[0] ?? null

    // The label counts down rather than showing the wall time: a bare HH:MM
    // beside a clock glyph reads as "the time", not "when this fires".
    property real nowSeconds: Date.now() / 1000

    readonly property string countdown: {
        if (!root.next)
            return "";
        const left = Math.max(0, root.next.epoch - root.nowSeconds);
        const minutes = Math.ceil(left / 60);
        if (minutes < 60)
            return `${minutes}m`;
        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return `${hours}h ${minutes % 60}m`;
        return `${Math.floor(hours / 24)}d ${hours % 24}h`;
    }

    readonly property string timezone: {
        try {
            return Intl.DateTimeFormat().resolvedOptions().timeZone ?? "local";
        } catch (error) {
            return "local";
        }
    }
    readonly property bool hasAlarm: root.next !== null || root.ringing !== null

    // Occurrences already rung, as id@epoch. The epoch is part of the key so a
    // daily alarm rolled forward by reap counts as a new occurrence.
    property var firedKeys: []
    property real lastReap: 0

    function reload() {
        try {
            const parsed = JSON.parse(file.text());
            if (!Array.isArray(parsed))
                throw new Error("state file is not a list");
            // Every field the bar prints, checked before it is printed.
            // SystemPills interpolates at, daily and label straight into the
            // tooltip, so one entry missing a field put the literal word
            // "undefined" where a time belongs.
            const good = parsed.filter(a => a
                                       && typeof a.epoch === "number" && isFinite(a.epoch)
                                       && typeof a.at === "string" && a.at !== ""
                                       && typeof a.label === "string");
            if (good.length !== parsed.length)
                console.warn("[alarms] dropped", parsed.length - good.length, "malformed entries");
            root.entries = good;
            root.asOf = Date.now();
        } catch (error) {
            // The previous list is kept: a truncated or half-written file would
            // otherwise erase every alarm from the bar without a word. What it
            // stops doing is claiming to be current -- the catch used to assign
            // nothing at all, so a file that never parsed again left the last
            // good list on the bar indefinitely.
            root.asOf = 0;
            console.warn("[alarms] unreadable state:", error);
        }
    }

    function dismiss() {
        root.ringing = null;
    }

    // Spaced out because a reap that cannot write leaves the entry due, and the
    // 5-second tick would then respawn it for as long as the shell runs.
    function reap() {
        if (clean.running || root.nowSeconds - root.lastReap < 60)
            return;
        root.lastReap = root.nowSeconds;
        clean.running = true;
    }

    function check() {
        const now = Date.now() / 1000;

        // A ring nobody dismissed stops being news. Without this the latch is
        // permanent: the pill stays red on an alarm from hours ago, and the
        // early return below means no alarm after it ever rings again.
        if (root.ringing !== null && now - root.ringing.epoch >= 300)
            root.dismiss();

        // An alarm whose moment passed unobserved, across a suspend or a shell
        // restart, still has to be rolled forward or dropped here, or a daily
        // alarm keeps its stale epoch and never comes due again.
        if (root.entries.some(a => now - a.epoch >= 300))
            root.reap();

        if (root.ringing !== null)
            return;
        const due = root.entries.find(a => !a.fired && !root.firedKeys.includes(`${a.id}@${a.epoch}`) && a.epoch <= now && now - a.epoch < 300);
        if (!due)
            return;
        // Remembered here rather than left to reap rewriting the file: if reap
        // fails the entry stays due, and the next tick would ring it again.
        root.firedKeys = root.firedKeys.concat(`${due.id}@${due.epoch}`);
        root.ringing = due;
        chime.running = true;
        root.reap();
    }

    FileView {
        id: file

        path: root.statePath
        watchChanges: true
        onLoaded: root.reload()
        onFileChanged: {
            file.reload();
            root.reload();
        }
        // A missing file only means alarm.sh has never run. Anything else means
        // the list on screen cannot be trusted, so say so.
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                // An answer, not a failure, so the stamp is set: an empty list
                // read off a machine with no alarms is a reading like any other.
                root.entries = [];
                root.asOf = Date.now();
                return;
            }
            // Deleted after a good load, or chmod 000. The list stops being
            // current here rather than surviving as though it were.
            root.asOf = 0;
            console.warn("[alarms] load failed:", error);
        }
    }

    // Rings once. A repeating sound in a status bar is hostile.
    Process {
        id: chime

        command: ["canberra-gtk-play", "-f", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]
    }

    // Rolls a fired alarm forward if it repeats, drops it if it does not.
    Process {
        id: clean

        command: [Quickshell.shellPath("scripts/alarm.sh"), "reap"]

        onExited: code => {
            if (code !== 0)
                console.warn("[alarms] reap failed, exit", code);
        }

        stderr: SplitParser {
            onRead: line => console.warn("[alarms]", line)
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.nowSeconds = Date.now() / 1000;
            root.check();
        }
    }
}
