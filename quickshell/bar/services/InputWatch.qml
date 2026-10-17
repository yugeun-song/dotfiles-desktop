pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The keyboard-side readings, from one helper (scripts/inputstate.py):
// Caps Lock's LED, the input method (Ime reads it), and whether the terminal
// of the window the key overlay watches asks for a password (KeyFeed). One
// process where there were three, each with an interpreter's memory of its
// own; the script says what each part does and how it fails.
Singleton {
    id: root

    // Caps Lock lit, and when that was last confirmed: 0 while unknown (no
    // reading yet, no LED node readable, the helper down). Kept, not
    // cleared, when unknown: hiding the pill would claim Caps Lock is off.
    property bool caps: false
    property double capsAsOf: 0

    // fcitx5's state and engine, and when they were last confirmed: 0 while
    // fcitx5 or the session bus does not answer, or the helper is down.
    property string imeState: ""
    property string imeMethod: ""
    property double imeAsOf: 0

    // Every input-method line: the answer to ask(), or a change it saw.
    signal imeAnswered()

    // The watched window's terminal reads with its echo off.
    property bool echoSecret: false

    readonly property bool running: helper.running

    property int restarts: 0

    // An input-method reading now instead of at the next poll; false with
    // no helper to ask.
    function ask(): bool {
        if (!helper.running)
            return false;
        helper.write("ask\n");
        return true;
    }

    // The window process whose terminals to watch, 0 for none. Kept, so a
    // helper that starts over is told again.
    property int watched: 0

    function watch(pid) {
        root.watched = pid > 0 ? pid : 0;
        if (helper.running)
            helper.write(`pid ${root.watched}\n`);
    }

    // Exponential backoff (2 s to 60 s): the helper ends only when it cannot
    // run here at all, its parts recover inside it.
    Timer {
        id: supervisor

        property int delay: 2000

        interval: supervisor.delay
        repeat: false
        onTriggered: {
            root.restarts = root.restarts + 1;
            console.warn("[input] helper exited, restart", root.restarts);
            supervisor.delay = Math.min(supervisor.delay * 2, 60000);
            helper.running = true;
        }
    }

    Process {
        id: helper

        running: true
        // -S: no site module, a quarter of a megabyte the helper never uses.
        // A helper started over watches from its first line on: told the pid
        // only on stdin, it would first say "clear" for none.
        command: ["python3", "-I", "-S", Quickshell.shellPath("scripts/inputstate.py")]
            .concat(root.watched > 0 ? ["--pid", String(root.watched)] : [])
        stdinEnabled: true

        // In case the window changed while it started.
        onStarted: {
            if (root.watched > 0)
                helper.write(`pid ${root.watched}\n`);
        }

        onRunningChanged: {
            if (!helper.running) {
                root.capsAsOf = 0;
                root.imeAsOf = 0;
                // Unknown counts as asking while a window is watched; KeyFeed
                // also holds its reader paused while the helper is down.
                root.echoSecret = root.watched > 0;
                supervisor.restart();
            }
        }

        stdout: SplitParser {
            onRead: line => root.take(line)
        }
    }

    function take(line) {
        // Any output resets the backoff.
        supervisor.delay = 2000;
        // Only the line ending is cut: trim() would also eat the tab that ends
        // "ime 0<TAB>" (state 0, no engine name).
        const raw = line.replace(/[\r\n]+$/, "");
        const space = raw.indexOf(" ");
        const tag = space < 0 ? raw : raw.slice(0, space);
        const value = space < 0 ? "" : raw.slice(space + 1);
        if (tag === "caps") {
            if (value === "0" || value === "1") {
                root.caps = value === "1";
                root.capsAsOf = Date.now();
            } else if (value === "-") {
                // No LED node readable (a keyboard mid-replug): unknown.
                root.capsAsOf = 0;
            } else {
                console.warn("[input] unexpected line:", raw);
            }
        } else if (tag === "ime") {
            root.takeIme(value, raw);
            root.imeAnswered();
        } else if (tag === "echo") {
            root.echoSecret = value === "secret";
        } else {
            console.warn("[input] unexpected line:", raw);
        }
    }

    function takeIme(value, raw) {
        // "-": fcitx5 did not answer (not the same as "no IM").
        if (value.trim() === "-") {
            root.imeAsOf = 0;
            return;
        }
        // An empty engine name is valid; an empty state is not.
        const parts = value.split("\t");
        if (parts.length !== 2 || parts[0] === "") {
            console.warn("[input] unexpected line:", raw);
            return;
        }
        root.imeState = parts[0];
        root.imeMethod = parts[1];
        root.imeAsOf = Date.now();
    }
}
