pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// Key presses for the on-screen overlay, from root's copy of
// keyfeed/keyfeed.py (evdev) as JSON lines. Its password is asked only when
// Super+Y turns the overlay on (the user, 2026-10-26): the reader is held
// outside the bar (scripts/keyfeed-hold.py), so a reload or restart of the
// bar finds it again. Not named "Keys", which would shadow the attached type
// every Keys.onPressed needs.
Singleton {
    id: root

    // On while a holder holds the reader for the bar. The session's end ends
    // both, so a login starts off: an always-on reader is a keylogger nobody
    // asked for, and one started at login would ask for the password there.
    property bool enabled: false

    // The reader sits under the compositor and reads the lock screen too, so
    // it is paused while locked (readerOpen); otherwise the password's last
    // keys were drawn at the unlock. hypridle reports lock and unlock, lock.sh
    // the lock as hyprlock starts, and the compositor is asked too (below):
    // lock.sh also returns when hyprlock crashes and the session stays
    // locked. Starts locked and asks at once, for a bar restarted mid-lock.
    property bool locked: true

    // A holder left by a reload or a restart is found by holdMark below.
    Component.onCompleted: lockProbe.running = true

    IpcHandler {
        target: "keys"

        function lock(): void {
            root.locked = true;
            root.clear();
        }

        function unlock(): void {
            root.locked = false;
            root.clear();
        }
    }

    // Without hypridle no unlock would come, so while locked the compositor
    // is asked now and then. Asked, not hyprlock looked for: a crashed locker
    // leaves the session locked, and its absence had counted as the unlock.
    Timer {
        interval: 5000
        repeat: true
        running: root.locked

        onTriggered: {
            if (!lockProbe.running)
                lockProbe.running = true;
        }
    }

    Process {
        id: lockProbe

        command: ["hyprctl", "locked"]

        // "true" or "false"; anything else (no compositor to ask) changes
        // nothing.
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "false" && root.locked) {
                    root.locked = false;
                    root.clear();
                }
            }
        }
    }

    // A password being typed must reach neither the overlay nor any buffer
    // on the way. Told without reading a key: a password window has the
    // focus (polkit agents, pinentry, askpass helpers, keyring and wallet
    // prompts), or the focused terminal reads with its echo off
    // (scripts/inputstate.py: sudo, su, ssh, passwd, read -s, pkttyagent).
    // The reader is then paused, its keyboards closed; with the helper down
    // nothing can tell, so it stays paused until the helper is back.
    readonly property var secretWindows: /polkit|policykit|pinentry|askpass|gcr-prompter|kwalletd/i

    readonly property var focusedWindow: Screens.focusedWindow

    readonly property bool secretFocused:
        root.secretWindows.test(root.focusedWindow?.wayland?.appId ?? root.focusedWindow?.lastIpcObject?.class ?? "")

    readonly property bool secretInput: root.secretFocused || InputWatch.echoSecret
        || (root.enabled && !InputWatch.running)

    // Set at once, clearing what was just drawn (a first key can beat the
    // word to the bar), and held a moment after: the password's last keys
    // can come after the word that it is over.
    property bool guarded: false

    onSecretInputChanged: {
        if (root.secretInput) {
            guardRelease.stop();
            root.guarded = true;
            root.clear();
        } else {
            guardRelease.restart();
        }
    }

    Timer {
        id: guardRelease

        interval: 400
        onTriggered: root.guarded = root.secretInput
    }

    // The focused window's process, for the terminal watch to find its
    // terminals.
    readonly property int focusedPid: root.focusedWindow?.lastIpcObject?.pid ?? 0

    onFocusedPidChanged: root.tellFocus()

    // Only while the overlay is on: nothing else wants to know, and with no
    // window to watch the helper does no terminal work at all.
    function tellFocus() {
        InputWatch.watch(root.enabled ? root.focusedPid : 0);
    }

    // quickshell fills a window's pid (lastIpcObject) from Hyprland's client
    // list only at its start and on a config reload, so the terminals of a
    // window opened since went unwatched (found 2026-10-17): the list is
    // asked for again when the focused window has no pid yet.
    onFocusedWindowChanged: root.askForPid()

    function askForPid() {
        if (root.enabled && root.focusedWindow && !(root.focusedWindow.lastIpcObject?.pid > 0))
            Hyprland.refreshToplevels();
    }

    onEnabledChanged: {
        root.askForPid();
        root.tellFocus();
    }

    // {mods, key, id}, key a jamo for a letter typed in Hangul. With
    // `waiting`, the only place keys are kept: at most maxVisible, each
    // dropped as its cap leaves (under a second), all on Super+Y off, a lock
    // or unlock, and a password being typed. Only the overlay reads them.
    property var chords: []

    readonly property int dwellMs: 500

    readonly property int maxVisible: 5

    // A letter typed into Hangul is drawn as the jamo fcitx5-hangul makes of
    // it, by Dubeolsik, the layout fcitx5/conf/hangul.conf sets (another
    // layout needs its own tables). Caps Lock is left out: the engine undoes
    // it, so Shift alone decides.
    readonly property var dubeolsik: ({
        Q: "ㅂ", W: "ㅈ", E: "ㄷ", R: "ㄱ", T: "ㅅ", Y: "ㅛ", U: "ㅕ", I: "ㅑ", O: "ㅐ", P: "ㅔ",
        A: "ㅁ", S: "ㄴ", D: "ㅇ", F: "ㄹ", G: "ㅎ", H: "ㅗ", J: "ㅓ", K: "ㅏ", L: "ㅣ",
        Z: "ㅋ", X: "ㅌ", C: "ㅊ", V: "ㅍ", B: "ㅠ", N: "ㅜ", M: "ㅡ"
    })

    readonly property var dubeolsikShift: ({ Q: "ㅃ", W: "ㅉ", E: "ㄸ", R: "ㄲ", T: "ㅆ", O: "ㅒ", P: "ㅖ" })

    // With Ctrl, Alt or Super held the engine passes a letter on untouched:
    // it is a shortcut then, and stays latin.
    function typesJamo(mods, key) {
        return root.dubeolsik[key] !== undefined && mods.every(m => m === "Shift");
    }

    function jamoFor(mods, key) {
        if (!root.typesJamo(mods, key))
            return key;
        return (mods.indexOf("Shift") !== -1 ? root.dubeolsikShift[key] : undefined) ?? root.dubeolsik[key];
    }

    // fcitx5-hangul converting in the focused field, by a reading that is
    // not stale: with the helper gone or fcitx5 not answering, keys are
    // drawn as they always were.
    readonly property bool hangul: Ime.hangul && Ime.method === "hangul" && Ime.asOf !== 0

    // Keys waiting on the input method (Ime.ask), in the order typed: a
    // letter, and whatever came behind it before the answer. Milliseconds as
    // a rule, answerMs at most.
    property var waiting: []

    readonly property int answerMs: 100

    // A letter waits for an input-method reading taken after it was typed:
    // with the poll's last reading, the first letter after a switch to
    // Hangul came out latin about half the time.
    function receive(mods, key) {
        if (root.locked || root.guarded)
            return;
        if (root.waiting.length === 0 && !(root.typesJamo(mods, key) && Ime.asOf !== 0)) {
            root.push(mods, key);
            return;
        }
        root.waiting = root.waiting.concat([{ mods: mods, key: key }]);
        root.fit();
        if (answerWait.running)
            return;
        if (Ime.ask())
            answerWait.start();
        else
            root.settle();
    }

    // The waiting keys drawn, with whatever reading came last: the answer,
    // or after answerMs the one before it.
    function settle() {
        answerWait.stop();
        const batch = root.waiting;
        root.waiting = [];
        for (let i = 0; i < batch.length; i++) {
            root.push(batch[i].mods, root.hangul ? root.jamoFor(batch[i].mods, batch[i].key) : batch[i].key);
            root.scrub(batch[i]);
        }
    }

    // Held to maxVisible keys between the two lists: the oldest chord goes
    // first, as push() would cut it a moment later.
    function fit() {
        while (root.chords.length + root.waiting.length > root.maxVisible) {
            if (root.chords.length > 0) {
                const next = root.chords.slice();
                root.scrub(next.shift());
                root.chords = next;
            } else {
                const next = root.waiting.slice();
                root.scrub(next.shift());
                root.waiting = next;
            }
        }
    }

    Timer {
        id: answerWait

        interval: root.answerMs
        onTriggered: root.settle()
    }

    Connections {
        target: Ime

        function onAnswered() {
            if (answerWait.running)
                root.settle();
        }
    }

    // Keys Inter has no symbol for, drawn from the icon font instead. Modifier
    // and other key symbols live in Theme.modSymbol / Theme.keySymbol.
    readonly property var keyIcon: ({
        "Playpause":  Theme.iconPlay,
        "Play":       Theme.iconPlay,
        "Pause":      Theme.iconPause,
        "Nextsong":   Theme.iconNext,
        "Previoussong": Theme.iconPrev,
        "Stopcd":     Theme.iconStop,
        "Mute":       Theme.iconVolumeOff,
        "Volumedown": Theme.iconVolumeLow,
        "Volumeup":   Theme.iconVolume,
        "Brightnessdown": Theme.iconBrightness,
        "Brightnessup":   Theme.iconBrightness,
        "Power":      Theme.iconPower,
        "Sleep":      Theme.iconSleep,
        "Search":     Theme.iconSearch,
        "Compose":    Theme.iconApps
    })

    function keyLabel(name) {
        return root.keyIcon[name] ?? Theme.keySymbol[name] ?? name;
    }

    // Tells KeyCap which font to use; the wrong one draws a box.
    function keyIsIcon(name) {
        return root.keyIcon[name] !== undefined;
    }

    // Printed order. The feed sends names; symbols are the shell's concern.
    // A scrubbed chord has none.
    function symbolsFor(mods) {
        if (!mods)
            return "";
        const order = ["Ctrl", "Alt", "Shift", "Super"];
        let out = "";
        for (let i = 0; i < order.length; i++)
            if (mods.indexOf(order[i]) !== -1)
                out += Theme.modSymbol[order[i]];
        return out;
    }

    property int nextId: 0
    property string failure: ""

    // A leaving chord gives its key up at once, so that no copy of its object
    // left in a model or a delegate leads to it. This drops the reference,
    // not the bytes, which the engine never clears: hence no core file for
    // the bar (bin/bar).
    function scrub(chord) {
        chord.key = null;
        chord.mods = null;
    }

    function push(mods, key) {
        if (root.locked || root.guarded)
            return;
        const next = root.chords.concat([{ mods: mods, key: key, id: root.nextId }]);
        root.nextId = root.nextId + 1;
        // Overflow is cut without an exit animation; animating it kept its
        // width and stacked chords across the screen during fast typing.
        while (next.length > root.maxVisible)
            root.scrub(next.shift());
        root.chords = next;
    }

    function drop(id) {
        const next = [];
        for (let i = 0; i < root.chords.length; i++) {
            if (root.chords[i].id !== id)
                next.push(root.chords[i]);
            else
                root.scrub(root.chords[i]);
        }
        root.chords = next;
    }

    function clear() {
        for (let i = 0; i < root.chords.length; i++)
            root.scrub(root.chords[i]);
        root.chords = [];
        answerWait.stop();
        for (let i = 0; i < root.waiting.length; i++)
            root.scrub(root.waiting[i]);
        root.waiting = [];
    }

    // Whether the reader may read at all: not while locked or while a
    // password is typed. Told on every change; paused, it holds no keyboard
    // open (keyfeed.py), and push() drops any key that crosses on the way.
    readonly property bool readerOpen: !root.locked && !root.guarded

    onReaderOpenChanged: root.steer()

    function steer() {
        if (link.connected) {
            link.write(root.readerOpen ? "resume\n" : "pause\n");
            link.flush();
        }
    }

    // The session's console, for the reader to hold the keys back while
    // another one is in front (a text console's login, another greeter).
    readonly property string vt: Quickshell.env("XDG_VTNR") ?? ""

    // Root's copy of the reader, put in place by install.sh's sudo step.
    // KEYFEED_SYSTEM points the tests at a stand-in (polkit judges the path
    // pkexec is handed, so another path gains nothing).
    readonly property string reader: Quickshell.env("KEYFEED_SYSTEM") || "/usr/local/libexec/keyfeed"

    // The holder's socket, in the user's runtime directory; KEYFEED_SOCKET
    // keeps the tests' apart.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    readonly property string socketPath: Quickshell.env("KEYFEED_SOCKET")
        || (root.runtimeDir !== "" ? `${root.runtimeDir}/keyfeed/socket` : "")

    // The reader is up and has said so; until then pkexec may still ask.
    property bool ready: false
    readonly property bool running: link.connected && root.ready
    // The holder said how the reader ended; a quiet disconnect is the
    // holder gone.
    property bool exitSeen: false
    // Super+Y off while the holder was still coming up: stopped once it
    // answers.
    property bool stopWanted: false

    function toggle() {
        if (root.enabled)
            root.stop();
        else
            root.start();
    }

    // On: a holder for the reader in a systemd-run unit of its own, so a
    // restart of bar.service leaves it (detached without systemd-run, and in
    // the tests: KEYFEED_HOLD_DETACHED). pkexec asks as it starts.
    function start() {
        root.failure = "";
        if (root.socketPath === "") {
            root.failure = "no runtime directory to hold the key reader in";
            return;
        }
        root.enabled = true;
        root.ready = false;
        root.exitSeen = false;
        root.stopWanted = false;
        const run = ["/usr/bin/env", "python3", "-I", "-S", Quickshell.shellPath("scripts/keyfeed-hold.py"),
                     root.socketPath, Quickshell.shellPath(""), "--needs", root.reader, "--", "pkexec", root.reader]
            .concat(/^[0-9]+$/.test(root.vt) ? ["--vt", root.vt] : []);
        if (Quickshell.env("KEYFEED_HOLD_DETACHED") === "1") {
            holdStart.command = run;
            holdStart.startDetached();
        } else {
            holdStart.fallback = run;
            holdStart.command = ["systemd-run", "--user", "--quiet", "--collect",
                                 "--description=Key overlay reader", "--"].concat(run);
            holdStart.running = true;
        }
        waitLink.tries = 0;
        waitLink.restart();
    }

    // Turns it off: the holder stops the reader and ends.
    function stop() {
        if (link.connected) {
            link.write("stop\n");
            link.flush();
        } else {
            root.stopWanted = waitLink.running;
        }
        waitLink.stop();
        root.enabled = false;
        root.ready = false;
        root.failure = "";
        root.clear();
    }

    Process {
        id: holdStart

        // The same holder started on its own, when systemd-run could not.
        property var fallback: []

        onExited: code => {
            if (code !== 0 && holdStart.fallback.length > 0) {
                console.warn("[keyfeed] systemd-run exited", code, "- holding the reader from here");
                holdStart.command = holdStart.fallback;
                holdStart.fallback = [];
                holdStart.startDetached();
            }
        }
    }

    // The holder listens before pkexec asks; looked for every 100 ms, for up
    // to five seconds.
    Timer {
        id: waitLink

        property int tries: 0

        interval: 100
        repeat: true
        onTriggered: {
            if (link.connected) {
                waitLink.stop();
                return;
            }
            waitLink.tries += 1;
            if (waitLink.tries > 50) {
                waitLink.stop();
                if (root.enabled)
                    root.failure = "the key reader's holder did not start";
                return;
            }
            holdMark.reload();
        }
    }

    // The pid file the holder writes once it listens, looked for before a
    // connect, so a bar with no holder to find (after a login) logs no error.
    FileView {
        id: holdMark

        path: root.socketPath !== "" ? root.socketPath.replace(/[^\/]*$/, "hold.pid") : ""
        printErrors: false

        onLoaded: {
            if (!link.connected)
                link.connected = true;
        }
    }

    Socket {
        id: link

        path: root.socketPath

        parser: SplitParser {
            onRead: line => root.take(line)
        }

        onConnectionStateChanged: root.linked(link.connected)
    }

    function linked(connected) {
        if (connected) {
            waitLink.stop();
            if (root.stopWanted) {
                root.stopWanted = false;
                link.write("stop\n");
                link.flush();
                return;
            }
            // Steered on the holder's "ready", said at once to a bar that
            // comes back to a running reader.
            root.enabled = true;
            root.exitSeen = false;
            return;
        }
        root.ready = false;
        if (root.enabled && !root.exitSeen && !waitLink.running) {
            console.warn("[keyfeed] the reader's holder went; the overlay is off");
            root.enabled = false;
            root.clear();
        }
    }

    function take(line) {
        const t = line.trim();
        if (t === "")
            return;
        let msg;
        try {
            msg = JSON.parse(t);
        } catch (e) {
            // Its length only: a line can carry a key, and the journal is
            // kept on disk.
            console.warn("[keyfeed] unparseable line of", t.length, "characters");
            return;
        }
        if (msg.type === "key") {
            root.failure = "";
            root.receive(msg.mods ?? [], msg.key ?? "?");
        } else if (msg.type === "ready") {
            root.failure = "";
            root.ready = true;
            // It starts paused; it learns whether to send now.
            root.steer();
        } else if (msg.type === "hold") {
            root.ready = false;
        } else if (msg.type === "error") {
            root.failure = msg.reason ?? "unknown";
            console.warn("[keyfeed]", root.failure);
        } else if (msg.type === "exit") {
            root.ended(Number(msg.code), String(msg.complaint ?? ""));
        }
    }

    // How the reader ended, from the holder: 126 the dialog dismissed, 127
    // not authorized or no agent (pkexec's), 69 root's copy not installed. A
    // refusal stays on screen until Super+Y; a reader that stopped on its own
    // keeps the reason it gave.
    function ended(code, complaint) {
        root.exitSeen = true;
        root.ready = false;
        if (!root.enabled || code === 0 || code === 143)
            return;
        if (code === 126) {
            // The user said no: the overlay goes off rather than ask again.
            console.warn("[keyfeed] authentication dismissed; the overlay is off");
            root.enabled = false;
            root.clear();
            return;
        }
        if (code === 69)
            root.failure = "the key reader is not installed; ./install.sh puts it in place";
        else if (code === 127 && /authentication agent/i.test(complaint))
            root.failure = "no polkit agent to ask for the password; Super+Y twice tries again";
        else if (code === 127)
            root.failure = complaint !== "" ? complaint : "not authorized to read the keyboards";
        else if (root.failure === "")
            root.failure = `the key reader stopped (${code}); Super+Y twice starts it again`;
        console.warn("[keyfeed]", root.failure);
    }
}
