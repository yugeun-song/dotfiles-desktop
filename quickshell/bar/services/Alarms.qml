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

    readonly property var pending: {
        const now = Date.now() / 1000;
        return root.entries.filter(a => a.epoch > now).sort((a, b) => a.epoch - b.epoch);
    }

    readonly property var next: root.pending[0] ?? null

    // The label counts down rather than showing the wall time: a bare HH:MM
    // beside a clock glyph reads as "the time", not "when this fires".
    property real nowSeconds: 0

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

    function reload() {
        try {
            const parsed = JSON.parse(file.text());
            root.entries = Array.isArray(parsed) ? parsed : [];
        } catch (error) {
            root.entries = [];
        }
    }

    function dismiss() {
        root.ringing = null;
    }

    function check() {
        if (root.ringing !== null)
            return;
        const now = Date.now() / 1000;
        const due = root.entries.find(a => !a.fired && a.epoch <= now && now - a.epoch < 300);
        if (!due)
            return;
        root.ringing = due;
        chime.running = true;
        clean.running = true;
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
