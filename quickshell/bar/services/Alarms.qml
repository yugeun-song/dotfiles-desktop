pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // JSON state owned by scripts/alarm.sh; watched, so no IPC is needed.
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") ?? `${Quickshell.env("HOME")}/.local/state`) + "/quickshell-bar/alarms.json"

    property var entries: []
    property var ringing: null

    // Last good load. entries survive a failed load, so this marks staleness.
    property double asOf: 0

    // Uses nowSeconds, not Date.now(): a binding only re-runs on dependencies.
    readonly property var pending: root.entries.filter(a => a.epoch > root.nowSeconds).sort((a, b) => a.epoch - b.epoch)

    readonly property var next: root.pending[0] ?? null

    // Ticked by the timer below; drives pending and the tooltip countdown.
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

    // Rung occurrences as id@epoch, so a rolled-forward daily alarm rings again.
    property var firedKeys: []
    property real lastReap: 0

    function reload() {
        try {
            const parsed = JSON.parse(file.text());
            if (!Array.isArray(parsed))
                throw new Error("state file is not a list");
            // StatusItems interpolates these fields into the tooltip; drop
            // entries that would print "undefined".
            const good = parsed.filter(a => a
                                       && typeof a.epoch === "number" && isFinite(a.epoch)
                                       && typeof a.at === "string" && a.at !== ""
                                       && typeof a.label === "string");
            if (good.length !== parsed.length)
                console.warn("[alarms] dropped", parsed.length - good.length, "malformed entries");
            root.entries = good;
            root.asOf = Date.now();
        } catch (error) {
            // Keep the previous list (a half-written file must not erase it),
            // but mark it stale.
            root.asOf = 0;
            console.warn("[alarms] unreadable state:", error);
        }
    }

    function dismiss() {
        root.ringing = null;
    }

    // Rate-limited: a reap that cannot write leaves the entry due, and the
    // 5 s tick would respawn it forever.
    function reap() {
        if (clean.running || root.nowSeconds - root.lastReap < 60)
            return;
        root.lastReap = root.nowSeconds;
        clean.running = true;
    }

    function check() {
        const now = Date.now() / 1000;

        // Auto-dismiss after 5 min, or the latch blocks every later alarm.
        if (root.ringing !== null && now - root.ringing.epoch >= 300)
            root.dismiss();

        // Missed across suspend or restart: roll forward or a daily alarm
        // never comes due again.
        if (root.entries.some(a => !a.fired && now - a.epoch >= 300))
            root.reap();

        if (root.ringing !== null)
            return;
        const due = root.entries.find(a => !a.fired && !root.firedKeys.includes(`${a.id}@${a.epoch}`) && a.epoch <= now && now - a.epoch < 300);
        if (!due)
            return;
        // Recorded locally: if reap fails the entry stays due and would re-ring.
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
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                // alarm.sh never ran: a valid empty reading, not a failure.
                root.entries = [];
                root.asOf = Date.now();
                return;
            }
            // Deleted after a good load, or unreadable: mark stale.
            root.asOf = 0;
            console.warn("[alarms] load failed:", error);
        }
    }

    // Rings once, never loops.
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
