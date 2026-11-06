import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "modules"
import qs.services
import "modules/lockout.js" as Lockout

// Unit tests for the bar's own logic, run by tests/unit/qml.sh in a copy of
// quickshell/bar with this file as its shell.qml: offscreen, on no bus, with
// state and config in a temporary directory. What is tested is the code that
// decides (URL filters, the override file the Displays panel writes, launcher
// ranking, notification markup), not what is drawn.
ShellRoot {
    id: root

    property int passed: 0
    property int failed: 0

    // Values compare as JSON, so arrays and objects compare by content.
    function check(name, got, want) {
        const a = JSON.stringify(got);
        const b = JSON.stringify(want);
        if (a === b) {
            root.passed += 1;
            return;
        }
        root.failed += 1;
        console.log(`[test] FAIL ${name}: got ${a}, want ${b}`);
    }

    // Launcher and Displays own layer windows, which need a Wayland display:
    // offscreen there is no PanelWindow backend and the file would not load.
    // Their suites run when a display is there (the nested session of
    // tests/e2e), and are left out otherwise.
    Loader {
        id: modules

        active: Quickshell.env("WAYLAND_DISPLAY") !== null && Quickshell.env("WAYLAND_DISPLAY") !== ""
        source: "TestModules.qml"
    }

    function testTheme() {
        check("battery: charging is one glyph at any level", Theme.batteryIcon(37, true), String.fromCodePoint(0xF0084));
        check("battery: empty", Theme.batteryIcon(2, false), String.fromCodePoint(0xF008E));
        check("battery: a level", Theme.batteryIcon(44, false), String.fromCodePoint(0xF007D));
        check("battery: full", Theme.batteryIcon(100, false), String.fromCodePoint(0xF0079));
        check("volume: muted is off at any level", Theme.volumeIcon(80, true), Theme.iconVolumeOff);
        check("art: an allowed host", Theme.localArt("https://i.scdn.co/image/x"), "https://i.scdn.co/image/x");
        check("art: a local file", Theme.localArt("file:///tmp/cover.png"), "file:///tmp/cover.png");
        check("art: plain http", Theme.localArt("http://i.scdn.co/image/x"), "");
        check("art: an allowed name as a prefix of another host", Theme.localArt("https://i.scdn.co.evil.example/x"), "");
        check("art: an allowed name as userinfo", Theme.localArt("https://i.scdn.co@evil.example/x"), "");
        check("art: userinfo before an allowed host", Theme.localArt("https://user@i.scdn.co/x"), "https://user@i.scdn.co/x");
        check("art: a port on an allowed host", Theme.localArt("https://i.scdn.co:8443/x"), "https://i.scdn.co:8443/x");
        check("art: upper case host", Theme.localArt("https://I.SCDN.CO/x"), "https://I.SCDN.CO/x");
        check("art: empty", Theme.localArt(""), "");
        check("art: an allowed host after ?@", Theme.localArt("https://evil.example?@i.scdn.co/x"), "");
        check("art: an allowed host after #@", Theme.localArt("https://evil.example#@i.scdn.co/x"), "");
        check("art: not a URL", Theme.localArt("https://"), "");
        check("shorten: short", Theme.shorten("kitty", 8), "kitty");
        check("shorten: long", Theme.shorten("abcdefghij", 5), "abcd…");
        check("fit: no screen", Theme.fit(null), 1);
        check("fit: the laptop panel and the desk monitor alike", [Theme.fit({ width: 1920, height: 1200 }),
              Theme.fit({ width: 2560, height: 1440 })], [1, 1]);
        check("fit: a larger screen by its area", Theme.fit({ width: 3840, height: 2160 }), 1.5);
        check("fit: capped", Theme.fit({ width: 7680, height: 4320 }), 2);
    }

    function testNotifications() {
        check("img: removed", Notifications.withoutImages("a<img src=\"https://x/y.png\">b"), "ab");
        check("img: upper case", Notifications.withoutImages("<IMG SRC=x>text"), "text");
        check("img: spaces", Notifications.withoutImages("< img src=x >text"), "text");
        check("img: unclosed", Notifications.withoutImages("text<img src=https://x"), "text");
        check("img: other markup kept", Notifications.withoutImages("<b>bold</b>"), "<b>bold</b>");
        check("img: nested to survive one pass", Notifications.withoutImages("a<im<img>g src=\"http://x/y\">b"), "ab");
        const saved = Notifications.history;
        const now = Date.now();
        const stale = { id: 901, key: 901, summary: "old", body: "code 1234", actions: [{ text: "Open", identifier: "o" }],
                        at: now - 25 * 3600000, read: true, live: null };
        const recent = { id: 902, key: 902, summary: "new", body: "b", actions: [], at: now - 3600000, read: false, live: null };
        Notifications.history = [recent, stale];
        Notifications.expire();
        check("history: an entry a day old expires", Notifications.history.map(e => e.id), [902]);
        check("history: and gives its text up", [stale.summary, stale.body, stale.actions], ["", "", []]);
        Notifications.dismiss(902);
        check("history: so does a dismissed one", recent.summary, "");
        Notifications.history = saved;
        const fake = { id: 9901, appName: "t", appIcon: "", summary: "old", body: "b", urgency: 0, actions: [], tracked: true };
        Notifications.history = [Object.assign(Notifications.snapshot(fake), { at: 5, read: true })].concat(Notifications.history);
        const firstKey = Notifications.history[0].key;
        fake.summary = "new";
        Notifications.refresh(fake);
        const replaced = Notifications.history.find(e => e.id === 9901);
        check("replace: the entry is refreshed in place", replaced.summary, "new");
        check("replace: it keeps its arrival", replaced.at, 5);
        check("replace: it is unread again", replaced.read, false);
        check("replace: its toast is a new card", replaced.key !== firstKey, true);
        check("invoke: a gone sender is refused", Notifications.invoke({ id: 1, live: { tracked: false } }, "x"), false);
        Notifications.dismiss(9901);
        check("sender: notify-send", Notifications.senderName("notify-send"), "");
        check("sender: named", Notifications.senderName("Firefox"), "Firefox");
    }

    function testScreensaver() {
        Screensaver.parse("# kept\nSamsung Display Corp. 0x419D\t3\nname:HDMI-A-1\t10\nname:DP-1\t0\nbad line\n");
        check("saver: entries", Screensaver.entries,
              [{ selector: "Samsung Display Corp. 0x419D", minutes: 3 }, { selector: "name:HDMI-A-1", minutes: 10 }]);
        check("saver: kept lines", Screensaver.kept, ["# kept", "name:DP-1\t0", "bad line"]);
        check("saver: by description", Screensaver.minutesOf("eDP-1", "Samsung Display Corp. 0x419D"), 3);
        check("saver: by connector", Screensaver.minutesOf("HDMI-A-1", "Philips 27M2N5500"), 10);
        check("saver: none", Screensaver.minutesOf("DP-2", ""), 0);
        Screensaver.parse("name:eDP-1\t5\nSamsung Display Corp. 0x419D\t3\n");
        check("saver: a description line wins", Screensaver.minutesOf("eDP-1", "Samsung Display Corp. 0x419D"), 3);
        check("saver: commas dropped", Screensaver.normalize("Acme, Inc. Model, 1 "), "Acme Inc. Model 1");
    }

    function testKeyFeed() {
        // hyprctl holds its answer until keyLockSteps lets it go.
        check("keys: a bar starts locked until it knows there is no lock", KeyFeed.locked, true);
        KeyFeed.locked = false;
        check("mods: printed order", KeyFeed.symbolsFor(["Super", "Shift", "Ctrl"]),
              Theme.modSymbol.Ctrl + Theme.modSymbol.Shift + Theme.modSymbol.Super);
        check("keys: icon", KeyFeed.keyIsIcon("Playpause"), true);
        check("keys: word", KeyFeed.keyIsIcon("Esc"), false);
        KeyFeed.clear();
        for (let i = 0; i < 8; i++)
            KeyFeed.push([], String(i));
        check("chords: capped", KeyFeed.chords.map(c => c.key), ["3", "4", "5", "6", "7"]);
        KeyFeed.clear();
        KeyFeed.locked = true;
        KeyFeed.push([], "p");
        check("chords: none while locked", KeyFeed.chords.length, 0);
        KeyFeed.locked = false;
        KeyFeed.push([], "x");
        check("chords: back after the unlock", KeyFeed.chords.map(c => c.key), ["x"]);
        KeyFeed.clear();
        // A chord that leaves gives its key up, wherever its object went.
        KeyFeed.push(["Ctrl"], "s");
        const dropped = KeyFeed.chords[0];
        KeyFeed.drop(dropped.id);
        check("scrub: a dropped chord keeps no key", [dropped.key, dropped.mods], [null, null]);
        KeyFeed.push([], "a");
        const cleared = KeyFeed.chords[0];
        KeyFeed.clear();
        check("scrub: nor does a cleared one", cleared.key, null);
        for (let i = 0; i < 5; i++)
            KeyFeed.push([], String(i));
        const oldest = KeyFeed.chords[0];
        KeyFeed.push([], "5");
        check("scrub: nor one cut by the cap", oldest.key, null);
        KeyFeed.clear();
        check("mods: a scrubbed chord prints none", KeyFeed.symbolsFor(null), "");
        const dialogs = ["org.kde.polkit-kde-authentication-agent-1", "hyprpolkitagent", "lxqt-policykit-agent",
                         "org.gnupg.pinentry-qt", "org.kde.ksshaskpass", "gcr-prompter", "org.kde.kwalletd6",
                         "org.kde.kded6", "kcmshell6", "systemsettings", "org.kde.bluedevilwizard",
                         "nm-connection-editor"];
        check("secret: password windows are known", dialogs.filter(c => !KeyFeed.secretWindows.test(c)), []);
        check("secret: other windows are not", ["kitty", "firefox", "org.kde.dolphin", "code-oss"]
              .filter(c => KeyFeed.secretWindows.test(c)), []);
        KeyFeed.guarded = true;
        KeyFeed.push([], "p");
        check("chords: none while a password is typed", KeyFeed.chords.length, 0);
        KeyFeed.guarded = false;
        // As at the start, until the probe answers.
        KeyFeed.locked = true;
        check("hangul: letters", ["R", "K", "M", "Z"].map(k => KeyFeed.jamoFor([], k)), ["ㄱ", "ㅏ", "ㅡ", "ㅋ"]);
        check("hangul: with Shift", ["R", "T", "O", "K"].map(k => KeyFeed.jamoFor(["Shift"], k)), ["ㄲ", "ㅆ", "ㅒ", "ㅏ"]);
        check("hangul: a shortcut stays latin", [KeyFeed.jamoFor(["Ctrl"], "R"), KeyFeed.jamoFor(["Shift", "Super"], "R")],
              ["R", "R"]);
        check("hangul: not a letter", [KeyFeed.jamoFor([], "1"), KeyFeed.jamoFor(["Shift"], "Space")], ["1", "Space"]);
        const jamo = Object.values(KeyFeed.dubeolsik);
        check("hangul: 26 letters, 26 jamo", [jamo.length, jamo.filter((j, i) => jamo.indexOf(j) !== i)], [26, []]);
        check("hangul: shifted keys are letters",
              Object.keys(KeyFeed.dubeolsikShift).filter(k => KeyFeed.dubeolsik[k] === undefined), []);
        check("caps: Hangul ones are as tall as latin ones",
              [jamoCap.implicitHeight, wordCap.implicitHeight], [latinCap.implicitHeight, latinCap.implicitHeight]);
    }

    KeyCap {
        id: latinCap

        visible: false
        mods: Theme.modSymbol.Shift
        text: "R"
    }

    KeyCap {
        id: jamoCap

        visible: false
        mods: Theme.modSymbol.Shift
        text: "ㄲ"
    }

    KeyCap {
        id: wordCap

        visible: false
        text: "한/영"
    }

    function keyLockSteps() {
        return [
            { wait: 50, run: () => Quickshell.execDetached(["touch", Quickshell.env("QML_TEST_LOCK_GO")]) },
            { wait: 500, run: () => check("keys: a session the compositor calls unlocked unlocks them", KeyFeed.locked, false) }
        ];
    }

    // The reader through pkexec, with the stand-ins of tests/unit/qml.sh.
    readonly property string keyDir: Quickshell.env("KEYFEED_TEST_DIR") ?? ""
    property string keyLog: ""
    property string keyControl: ""

    FileView {
        id: keyControlFile

        path: root.keyDir + "/control"
        watchChanges: true
        printErrors: false

        onFileChanged: keyControlFile.reload()
        onLoaded: root.keyControl = keyControlFile.text()
        onLoadFailed: root.keyControl = ""
    }

    FileView {
        id: keyLogFile

        path: root.keyDir + "/log"
        watchChanges: true
        printErrors: false

        onFileChanged: keyLogFile.reload()
        onLoaded: root.keyLog = keyLogFile.text()
        onLoadFailed: root.keyLog = ""
    }

    FileView {
        id: keyArgsFile

        path: root.keyDir + "/args"
        blockLoading: true
        printErrors: false
    }

    readonly property string echoFlag: Quickshell.env("ECHOWATCH_TEST_FLAG") ?? ""

    FileView {
        id: echoLog

        path: Quickshell.env("ECHOWATCH_TEST_LOG") ?? ""
        blockLoading: true
        printErrors: false
    }

    function keyMode(mode) {
        Quickshell.execDetached(["sh", "-c", `printf %s "$2" > "$1/mode"`, "sh", root.keyDir, mode]);
    }

    function keyFeedSteps() {
        const reader = Quickshell.env("KEYFEED_SYSTEM");
        return [
            { wait: 0, run: () => {
                root.keyMode("ok");
                KeyFeed.toggle();
            } },
            { wait: 700, run: () => {
                keyArgsFile.reload();
                check("reader: told the session's console", keyArgsFile.text().trim(), "--vt 7");
                check("reader: told to send once it is ready", root.keyControl, "resume\n");
                check("reader: its keys reach the overlay", KeyFeed.chords.map(c => c.key), ["K"]);
                check("reader: started once", root.keyLog, "started\n");
                KeyFeed.clear();
                KeyFeed.locked = true;
            } },
            { wait: 300, run: () => {
                check("reader: a lock pauses it", root.keyControl, "resume\npause\n");
                KeyFeed.locked = false;
            } },
            { wait: 300, run: () => {
                check("reader: the unlock resumes it", root.keyControl, "resume\npause\nresume\n");
                check("reader: and its keys come again", KeyFeed.chords.map(c => c.key), ["K"]);
                echoLog.reload();
                check("prompt: the watcher is told the focused window", echoLog.text(), "pid 0\n");
                Quickshell.execDetached(["touch", root.echoFlag]);
            } },
            { wait: 400, run: () => {
                check("prompt: a terminal asking for a password pauses the reader",
                      [KeyFeed.guarded, root.keyControl], [true, "resume\npause\nresume\npause\n"]);
                check("prompt: and what was drawn goes", KeyFeed.chords.length, 0);
                KeyFeed.push([], "p");
                check("prompt: nothing is drawn meanwhile", KeyFeed.chords.length, 0);
                Quickshell.execDetached(["rm", "-f", root.echoFlag]);
            } },
            { wait: 250, run: () => check("prompt: held a moment after", KeyFeed.guarded, true) },
            { wait: 500, run: () => {
                check("prompt: then the reader resumes", root.keyControl, "resume\npause\nresume\npause\nresume\n");
                KeyFeed.toggle();
            } },
            { wait: 700, run: () => {
                check("reader: Super+Y off tells it to stop", root.keyControl,
                      "resume\npause\nresume\npause\nresume\nstop\n");
                check("reader: and it stops, though the bar cannot signal it", root.keyLog, "started\nstopped\n");
                root.keyMode("dismiss");
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: a dismissed password turns the overlay off", KeyFeed.enabled, false);
                root.keyMode("refuse");
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: a refusal leaves it on with pkexec's reason", [KeyFeed.enabled, KeyFeed.failure],
                      [true, "Error executing command as another user: Not authorized"]);
                check("reader: and asks no more", KeyFeed.running, false);
                root.keyMode("noagent");
                KeyFeed.toggle();
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: a missing agent is said, and not asked for again by itself", KeyFeed.failure,
                      "no polkit agent to ask for the password; Super+Y twice tries again");
                root.keyMode("ok");
                KeyFeed.toggle();
            } },
            { wait: 100, run: () => KeyFeed.toggle() },
            { wait: 700, run: () => {
                check("reader: Super+Y twice starts it", [KeyFeed.failure, KeyFeed.chords.map(c => c.key)], ["", ["K"]]);
                KeyFeed.toggle();
                Quickshell.execDetached(["chmod", "-x", reader]);
            } },
            { wait: 300, run: () => KeyFeed.toggle() },
            { wait: 600, run: () => {
                check("reader: one not installed is said", KeyFeed.failure,
                      "the key reader is not installed; ./install.sh puts it in place");
                KeyFeed.toggle();
                Quickshell.execDetached(["chmod", "+x", reader]);
            } }
        ];
    }

    // The input method helper of tests/unit/qml.sh, which answers only when
    // asked: a reading changed behind the bar's back stands for a switch the
    // poll has not seen yet.
    readonly property string imeDir: Quickshell.env("IME_TEST_DIR") ?? ""
    property int imeAsks: 0

    FileView {
        id: imeAskLog

        path: root.imeDir + "/asks"
        watchChanges: true
        printErrors: false

        onFileChanged: imeAskLog.reload()
        onLoaded: root.imeAsks = imeAskLog.text().split("\n").filter(l => l === "ask").length
        onLoadFailed: root.imeAsks = 0
    }

    function imeReading(line) {
        Quickshell.execDetached(["sh", "-c", line === null ? `rm -f "$1/reading"` : `printf '%s\\n' "$2" > "$1/reading"`,
                                 "sh", root.imeDir, line ?? ""]);
    }

    function imeMute(on) {
        Quickshell.execDetached(on ? ["touch", root.imeDir + "/mute"] : ["rm", "-f", root.imeDir + "/mute"]);
    }

    function imeSteps() {
        return [
            { wait: 0, run: () => {
                check("ime: the helper's reading at the start", [Ime.state, Ime.method], ["1", "keyboard-kr-kr104"]);
                check("ime: latin is not drawn as Hangul", KeyFeed.hangul, false);
                KeyFeed.clear();
                root.imeReading("2\thangul");
            } },
            { wait: 300, run: () => {
                check("ime: a switch not seen yet", Ime.state, "1");
                KeyFeed.receive([], "R");
                check("ime: a letter waits for the answer", [KeyFeed.chords.length, KeyFeed.waiting.length], [0, 1]);
            } },
            { wait: 300, run: () => {
                check("ime: it asked", root.imeAsks, 1);
                check("ime: the first letter after a switch is Hangul", KeyFeed.chords.map(c => c.key), ["ㄱ"]);
                KeyFeed.receive(["Shift"], "R");
                KeyFeed.receive([], "Space");
                KeyFeed.receive(["Ctrl"], "R");
            } },
            { wait: 300, run: () => {
                check("ime: what came behind a waiting letter keeps its place",
                      KeyFeed.chords.map(c => [c.mods, c.key]), [[[], "ㄱ"], [["Shift"], "ㄲ"], [[], "Space"], [["Ctrl"], "R"]]);
                check("ime: one ask for the lot", root.imeAsks, 2);
                KeyFeed.clear();
                root.imeReading("1\tkeyboard-kr-kr104");
            } },
            { wait: 300, run: () => KeyFeed.receive([], "R") },
            { wait: 300, run: () => {
                check("ime: switched back, latin again", KeyFeed.chords.map(c => c.key), ["R"]);
                KeyFeed.clear();
                root.imeMute(true);
                root.imeReading("2\thangul");
            } },
            { wait: 300, run: () => KeyFeed.receive([], "A") },
            { wait: 50, run: () => check("ime: unanswered, it waits", KeyFeed.waiting.length, 1) },
            { wait: 250, run: () => {
                check("ime: then is drawn with the last reading", [KeyFeed.waiting.length, KeyFeed.chords.map(c => c.key)],
                      [0, ["A"]]);
                KeyFeed.clear();
                root.imeMute(false);
            } },
            { wait: 300, run: () => {
                for (let i = 0; i < 5; i++)
                    KeyFeed.push([], String(i));
                KeyFeed.receive([], "R");
                check("ime: five keys at most, waiting ones counted", [KeyFeed.chords.length, KeyFeed.waiting.length], [4, 1]);
                // What lock() does.
                KeyFeed.locked = true;
                KeyFeed.clear();
            } },
            { wait: 300, run: () => {
                check("ime: a letter waiting at a lock is never drawn", KeyFeed.chords.length, 0);
                KeyFeed.locked = false;
                root.imeReading(null);
            } },
            { wait: 300, run: () => KeyFeed.receive([], "R") },
            { wait: 300, run: () => {
                check("ime: fcitx5 not answering reads latin", [Ime.asOf, KeyFeed.chords.map(c => c.key)], [0, ["R"]]);
                KeyFeed.receive([], "K");
                check("ime: and nothing waits for it", [KeyFeed.waiting.length, KeyFeed.chords.map(c => c.key)],
                      [0, ["R", "K"]]);
                KeyFeed.clear();
            } }
        ];
    }

    function testCamera() {
        const cam = (name, state) => ({ name: name, state: state, nodes: state === "on" ? ["video0"] : [] });
        const reading = (sw, cameras, switches) => ({ switch: sw, busy: false, cameras: cameras,
                                                      power_switches: switches ?? [], missing: [] });
        check("camera: no reading", Camera.classify(null), "unknown");
        check("camera: no cameras list", Camera.classify({ switch: "off" }), "unknown");
        check("camera: on", Camera.classify(reading("on", [cam("A", "on")])), "on");
        check("camera: on with none", Camera.classify(reading("on", [])), "on");
        check("camera: off with none", Camera.classify(reading("off", [])), "none");
        check("camera: off", Camera.classify(reading("off", [cam("A", "off"), cam("B", "off")])), "off");
        check("camera: off, one live", Camera.classify(reading("off", [cam("A", "off"), cam("B", "on")])), "leak");
        check("camera: on, one dark", Camera.classify(reading("on", [cam("A", "on"), cam("B", "off")])), "stuck");
        check("camera: off by firmware alone", Camera.classify(reading("off", [], [{ name: "fw", state: "off" }])), "off");
        check("camera: on, firmware still off", Camera.classify(reading("on", [], [{ name: "fw", state: "off" }])), "stuck");
    }

    // The camera stand-ins of tests/unit/qml.sh, driven through files.
    readonly property string camDir: Quickshell.env("CAMERA_TEST_DIR") ?? ""

    function sh(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd, "sh", root.camDir]);
    }

    function camStatus(sw, state) {
        const r = { switch: sw, busy: false, cameras: [{ name: "Cam A", state: state, nodes: state === "on" ? ["video0"] : [] }],
                    power_switches: [], missing: [] };
        root.sh(`printf '%s\\n' '${JSON.stringify(r)}' > "$1/status.new" && mv "$1/status.new" "$1/status.json"`);
    }

    function camBusy() {
        const r = { switch: "off", busy: true, cameras: [{ name: "Cam A", state: "on", nodes: ["video0"] }],
                    power_switches: [], missing: [] };
        root.sh(`printf '%s\\n' '${JSON.stringify(r)}' > "$1/status.new" && mv "$1/status.new" "$1/status.json"`);
    }

    function camEvents(n) {
        root.sh(`i=0; while [ $i -lt ${n} ]; do i=$((i+1)); echo "UDEV  [1.$i] add      /devices/test/video4linux/video$i (video4linux)" >> "$1/events"; done`);
    }

    // Counted as the stand-in appends: text() right after reload() still
    // returns the previous load.
    property int camCallCount: 0

    function camCalls() {
        return root.camCallCount;
    }

    FileView {
        id: calls

        path: root.camDir + "/calls"
        watchChanges: true
        printErrors: false

        onFileChanged: calls.reload()
        onLoaded: root.camCallCount = calls.text().split("\n").filter(l => l === "run").length
        onLoadFailed: root.camCallCount = 0
    }

    // The camera service on events: a step waits, then acts or checks. The
    // reading starts as switch off, camera off (tests/unit/qml.sh).
    // Caps Lock, from the same helper: the stub prints what $WORK/caps
    // holds, on change.
    readonly property string capsFile: Quickshell.env("CAPS_TEST_FILE") ?? ""

    function capsWrite(value) {
        Quickshell.execDetached(["sh", "-c", `printf '%s\\n' "$2" > "$1"`, "sh", root.capsFile, value]);
    }

    function capsSteps() {
        return [
            { wait: 0, run: () => {
                check("caps: off at the start", [InputWatch.caps, InputWatch.capsAsOf > 0], [false, true]);
                root.capsWrite("1");
            } },
            { wait: 300, run: () => {
                check("caps: on", [InputWatch.caps, InputWatch.capsAsOf > 0], [true, true]);
                root.capsWrite("-");
            } },
            { wait: 300, run: () => {
                check("caps: no LED readable keeps the reading, marked unknown",
                      [InputWatch.caps, InputWatch.capsAsOf], [true, 0]);
                root.capsWrite("0");
            } },
            { wait: 300, run: () => check("caps: off again", [InputWatch.caps, InputWatch.capsAsOf > 0], [false, true]) }
        ];
    }

    function cameraSteps() {
        return [
            { wait: 600, run: () => {
                check("camera events: one read at start", root.camCalls(), 1);
                check("camera events: off at start", Camera.state, "off");
                check("camera events: shown while off", Camera.shown, true);
                root.camStatus("on", "on");
            } },
            { wait: 150, run: () => root.camEvents(1) },
            { wait: 700, run: () => {
                check("camera events: a device event reads", root.camCalls(), 2);
                check("camera events: on after it", Camera.state, "on");
                check("camera events: hidden while on", Camera.shown, false);
                root.camEvents(6);
            } },
            { wait: 900, run: () => {
                check("camera events: a burst is one read", root.camCalls(), 3);
                root.camBusy();
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 300, run: () => {
                check("camera events: refresh reads at once", root.camCalls(), 4);
                check("camera events: a reading under the lock is not shown", Camera.state, "on");
                root.camStatus("off", "off");
            } },
            { wait: 800, run: () => {
                check("camera events: read again once the lock is free", Camera.state, "off");
                root.camStatus("off", "on");
            } },
            { wait: 150, run: () => root.camEvents(1) },
            { wait: 700, run: () => {
                check("camera events: a live camera under an off switch", Camera.state, "leak");
                root.sh(`echo 1 > "$1/exit"`);
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 400, run: () => {
                check("camera events: a failed read is noted", Camera.failure !== "", true);
                check("camera events: the last reading stays", Camera.state, "leak");
                root.sh(`echo 0 > "$1/exit"`);
                root.camStatus("off", "off");
            } },
            { wait: 2400, run: () => {
                check("camera events: the retry clears the failure", Camera.failure, "");
                check("camera events: the retry reads the new state", Camera.state, "off");
                root.sh(`: > "$1/calls"; touch "$1/state/off"`);
            } },
            { wait: 800, run: () => {
                check("camera events: the switch file is an event", root.camCalls(), 1);
                root.sh(`echo 127 > "$1/exit"`);
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 400, run: () => {
                check("camera events: nothing installed, nothing shown", Camera.shown, false);
                check("camera events: nothing installed", Camera.installed, false);
                root.sh(`echo 0 > "$1/exit"`);
            } },
            { wait: 150, run: () => Camera.refresh() },
            { wait: 400, run: () => check("camera events: back once installed", Camera.state, "off") }
        ];
    }

    // The system widget against the stand-in /sys/class/drm of
    // tests/unit/qml.sh (two cards report VRAM, an integrated one's carve-out
    // and a discrete one's 8 GiB, a quarter used, the discrete one its load
    // in per cent; a third only its idle time), its parsers on given text,
    // and the calendar's day under the pointer.
    readonly property string drmDir: Quickshell.env("BAR_DRM_DIR") ?? ""
    property var vramWidget: null
    property var calendarWidget: null
    property var heroes: []

    function vramSteps() {
        const widget = 'import QtQuick; import qs.modules; SystemWidget { width: 356; height: 170; size: "medium"; '
            + 'options: ({ cpu: true, gpu: true, memory: false, vram: true, battery: false, disk: false, tmpfs: false, network: true }) }';
        return [
            { wait: 0, run: () => {
                root.vramWidget = Qt.createQmlObject(widget, root, "vram");
                root.calendarWidget = Qt.createQmlObject('import QtQuick; import qs.modules; CalendarWidget { width: 356; height: 170; '
                    + 'size: "medium"; options: ({ mondayFirst: true }) }', root, "calendar");
                root.heroes = [["08", "00", 138, 65], ["5", "00", 138, 96], ["-12°", "00°", 138, 92]].map(h =>
                    Qt.createQmlObject(`import QtQuick; import qs.modules; HeroText { text: "${h[0]}"; probe: "${h[1]}"; width: ${h[2]}; height: ${h[3]} }`,
                                       root, "hero"));
            } },
            { wait: 2600, run: () => {
                const w = SystemReadings;
                const rows = root.vramWidget.rows;
                check("system: the rows asked for, in the user's order; VRAM from the card with the most, a quarter used; its load in per cent",
                      [rows.map(r => r.label), rows.find(r => r.key === "vram")?.value, w.vramDir.endsWith("/card1/device"),
                       w.busyKind, rows.find(r => r.key === "gpu")?.value, (w.trails.gpu?.v ?? []).length > 1, w.users],
                      [["CPU", "Network Rx", "Network Tx", "GPU load", "VRAM"], 0.25, true, "percent", 0.37, true, 1]);
                check("system: /proc/net/dev without the loopback and the virtual links",
                      w.netTotals("Inter-|   Receive |  Transmit\n face |bytes packets\n    lo: 100 1 0 0 0 0 0 0 100 1 0 0 0 0 0 0\n"
                                  + "  wlo1: 5000 10 0 0 0 0 0 0 700 5 0 0 0 0 0 0\n docker0: 9 9 0 0 0 0 0 0 9 9 0 0 0 0 0 0\n"
                                  + "  eth0: 1000 1 0 0 0 0 0 0 300 1 0 0 0 0 0 0\n"),
                      { rx: 6000, tx: 1000 });
                check("system: df's root and a tmpfs /tmp; a /tmp on disk is no tmpfs",
                      [w.mounts("Type 1B-blocks Used Mounted on\nbtrfs 1000 250 /\ntmpfs 400 100 /tmp\n"),
                       w.mounts("Type 1B-blocks Used Mounted on\nbtrfs 1000 250 /\nbtrfs 1000 250 /tmp\n").tmp],
                      [{ disk: { size: 1000, used: 250 }, tmp: { size: 400, used: 100 } }, null]);
                check("system: sizes as df -h writes them, rates in three figures at most",
                      [w.bytes(511017222144), w.bytes(8119660544), w.bytes(512), w.rate(0), w.rate(1536), w.rate(999.6 * 1024),
                       w.rate(12.4 * 1048576)],
                      ["476G", "7.6G", "512B", { text: "0", unit: "B/s" }, { text: "1.5", unit: "K/s" }, { text: "1.0", unit: "M/s" },
                       { text: "12", unit: "M/s" }]);
                const c = root.calendarWidget;
                const g = c.grid;
                const at = day => {
                    const i = c.leading + day - 1;
                    return Qt.point(g.x + (i % 7 + 0.4) * g.pitch, g.y + (Math.floor(i / 7) + 0.4) * g.pitch);
                };
                const read = p => { c.pointer = p; return c.hoveredDay; };
                check("calendar: the day under the pointer, none off the month or without one",
                      [read(at(1)), read(at(c.days)), read(Qt.point(20, 80)), read(null)], [1, c.days, 0, 0]);
                check("calendar: its distance in D-day notation",
                      [c.dayOffset(c.today), c.dayOffset(c.today + 3), c.dayOffset(c.today - 2)], ["D-Day", "D+3", "D-2"]);
                c.pointer = at(1);
                c.pointer = null;
                check("calendar: the distance read last stays as the pointer leaves, to fade out as it was",
                      [c.hoveredDay, c.lastOffset], [0, c.dayOffset(1)]);
                const fits = root.heroes.map(h => h.fitSize > 0 && h.inkHeight <= h.height + 0.5);
                check("hero: every figure inside its box", fits, [true, true, true]);
                check("hero: a short figure takes the height its probe allows, a wide one shrinks",
                      [root.heroes[0].inkHeight > 55, root.heroes[2].fitSize < root.heroes[1].fitSize], [true, true]);
                root.vramWidget.destroy();
                root.vramWidget = null;
                root.calendarWidget.destroy();
                root.calendarWidget = null;
            } },
            { wait: 200, run: () => {
                const w = SystemReadings;
                const kept = (w.trails.gpu?.v ?? []).length;
                check("system: hidden, nothing is read but the charts stay", [w.users, w.sampling, kept > 1], [0, false, true]);
                w.trim(Date.now() + w.span + 1);
                check("system: past the charts' span they hold nothing", Object.keys(w.trails).length, 0);
                w.forget(true);
                check("system: with no system widget placed everything goes", [w.probed, w.vramFound, w.busyFound], [false, false, false]);
                for (const h of root.heroes)
                    h.destroy();
                root.heroes = [];
            } }
        ];
    }

    readonly property string weatherDir: Quickshell.env("WEATHER_TEST_DIR") ?? ""
    property int weatherCallCount: 0

    FileView {
        id: weatherCalls

        path: root.weatherDir + "/calls"
        watchChanges: true
        printErrors: false

        onFileChanged: weatherCalls.reload()
        onLoaded: root.weatherCallCount = weatherCalls.text().split("\n").filter(l => l === "run").length
        onLoadFailed: root.weatherCallCount = 0
    }

    // The place panel's asks of weather.sh, a line each.
    property var weatherAsks: []

    FileView {
        id: weatherAskLog

        path: root.weatherDir + "/asks"
        watchChanges: true
        printErrors: false

        onFileChanged: weatherAskLog.reload()
        onLoaded: root.weatherAsks = weatherAskLog.text().split("\n").filter(l => l !== "")
        onLoadFailed: root.weatherAsks = []
    }

    // A link or the internet coming up during a fetch (Weather.kick) is not
    // dropped: it fetches again at once if that fetch failed, and not at all
    // if it succeeded. The stand-in takes 0.4 s; the first fetch starts as
    // the service does.
    function weatherSteps() {
        return [
            { wait: 0, run: () => check("weather: nothing before the first fetch", Weather.ready, false) },
            { wait: 150, run: () => {
                check("weather: a fetch at start", Weather.fetching, true);
                Weather.kick();
                check("weather: a kick during it is kept", Weather.kickQueued, true);
            } },
            { wait: 1300, run: () => {
                check("weather: a failed fetch is followed at once", root.weatherCallCount, 2);
                check("weather: the kick is spent", Weather.kickQueued, false);
                Quickshell.execDetached(["sh", "-c", `echo true > "$1/live"`, "sh", root.weatherDir]);
            } },
            { wait: 150, run: () => {
                Weather.kick();
                Weather.kick();
            } },
            { wait: 1300, run: () => {
                check("weather: after a live fetch the kick fetches nothing more", root.weatherCallCount, 3);
                check("weather: live resets the failures", Weather.failures, 0);
                check("weather: the reading is shown", Weather.ready, true);
            } },
            // The place panel's search: one letter asks nothing; a name
            // typed while a search runs is asked after it, and the answer to
            // the older name is dropped; a pick is kept by weather.sh and
            // fetched at once; Seoul comes back through it too.
            { wait: 0, run: () => {
                Weather.find("B");
                check("weather: one letter asks nothing", Weather.searching, false);
                check("weather: and finds nothing", Weather.places.length, 0);
                Weather.find("Bus");
            } },
            { wait: 100, run: () => {
                check("weather: two letters ask", Weather.searching, true);
                Weather.find(" Busan ");
                check("weather: a name typed meanwhile waits for that ask", Weather.searchAgain, true);
            } },
            { wait: 1000, run: () => {
                check("weather: the answer is the last name's", Weather.answered, "Busan");
                check("weather: the older name's places are dropped", Weather.places.map(p => p.name).join(), "Busan");
                check("weather: both names were asked, trimmed", root.weatherAsks.join("|"), "search Bus|search Busan");
                Weather.choose(Weather.places[0]);
            } },
            { wait: 1300, run: () => {
                check("weather: the pick goes to weather.sh", root.weatherAsks[root.weatherAsks.length - 1], "set Busan 35.1 129 Asia/Seoul");
                check("weather: and its weather is fetched at once", root.weatherCallCount, 4);
                Weather.forget();
            } },
            { wait: 500, run: () => {
                check("weather: Seoul again through weather.sh", root.weatherAsks[root.weatherAsks.length - 1], "reset");
                check("weather: and fetched again", root.weatherCallCount, 5);
            } }
        ];
    }

    // Playback paused and resumed four times, each resume before the stopped
    // cava has exited: no failure is counted, and the meter runs at the end.
    function cavaSteps() {
        const flips = [{ wait: 100, run: () => { Cava.active = true; } }];
        for (let i = 0; i < 4; i++) {
            flips.push({ wait: 500, run: () => { Cava.active = false; } });
            flips.push({ wait: 100, run: () => { Cava.active = true; } });
        }
        return flips.concat([{ wait: 1500, run: () => {
            check("cava: a pause and a quick resume are no failure", Cava.quickExits, 0);
            check("cava: the meter runs after them", Cava.levels.length, 3);
            Cava.active = false;
        } }]);
    }

    // Steps run one after another, each after its wait; DONE follows the last.
    property var steps: []
    property int step: 0

    function runSteps() {
        if (root.step >= root.steps.length) {
            console.log(`[test] DONE passed=${root.passed} failed=${root.failed}`);
            Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)]);
            return;
        }
        stepTimer.interval = root.steps[root.step].wait;
        stepTimer.start();
    }

    Timer {
        id: stepTimer

        onTriggered: {
            const current = root.steps[root.step];
            root.step += 1;
            try {
                current.run();
            } catch (e) {
                root.failed += 1;
                console.log(`[test] FAIL step ${root.step}: threw ${e}`);
            }
            root.runSteps();
        }
    }

    function testWidgets() {
        check("widgets: unknown option keys dropped, booleans kept",
              Widgets.validOptions("clock", { hours24: false, seconds: true, evil: 1 }), { hours24: false });
        check("widgets: no options for a kind there is not", [Widgets.validOptions("stocks", {}), Widgets.validOptions("evil", {})],
              [null, null]);

        const W = 1920, H = 1080, top = 40;
        const apart = list => !list.some((a, i) => list.some((b, j) => i < j && Widgets.overlaps(a, b, 0)));
        const inside = (list, w, h) => list.every(a => a.x >= 0 && a.y >= top && a.x + a.w <= w && a.y + a.h <= h);
        const r = Widgets.rects(Widgets.defaults.layout, W, H, top);
        check("widgets: every default drawn, apart, inside", [r.length, apart(r), inside(r, W, H)],
              [Widgets.defaults.layout.length, true, true]);
        check("widgets: a cell is an eighth of the shorter side", r.find(a => a.size === "small").h, Math.round(H * 0.125));
        const g = Widgets.grid(2560, 1440, 37);
        check("widgets: the reference screen's grid", [g.cell, g.gap, g.pitch, g.x0, g.y0, g.cols, g.rows],
              [150, 14, 164, 14, 51, 15, 8]);
        check("widgets: a cell the laptop panel's at the bar's fit, an eighth of a smaller screen's side",
              [[2560, 1440], [1920, 1200], [3840, 2160], [1366, 768]].map(s => Widgets.grid(s[0], s[1], 37).cell),
              [150, 150, 225, 96]);
        const ids = list => ["calendar", "weather", "clock", "system"].map(id => list.find(a => a.id === id));
        const ref = ids(Widgets.rects(Widgets.defaults.layout, 2560, 1440, 37));
        check("widgets: the defaults on the reference screen, a gap from the edges and the bar",
              [ref[0].x, ref[0].y, ref[0].w, ref[1].y, ref[2].x, ref[3].y, ref[3].w], [14, 51, 314, 379, 178, 543, 314]);
        const lined = list => [list[1].y - (list[0].y + list[0].h), list[2].x - (list[1].x + list[1].w),
                               list[3].y - (list[1].y + list[1].h), list[0].x + list[0].w === list[2].x + list[2].w,
                               list[3].x + list[3].w === list[0].x + list[0].w, list[1].y === list[2].y];
        check("widgets: the defaults one gap apart, their edges in line", lined(ref), [14, 14, 14, true, true, true]);
        const panel = ids(Widgets.rects(Widgets.defaults.layout, 1920, 1200, 31));
        check("widgets: carried to the laptop's panel, the same grid smaller",
              [panel[1].w, panel[0].x, panel[0].y].concat(lined(panel)), [150, 14, 45, 14, 14, 14, true, true, true]);
        const spans = (w, h) => {
            const s = Widgets.rects([{ id: "s", kind: "calendar", size: "small", col: 0, row: 0 },
                                     { id: "m", kind: "calendar", size: "medium", col: 0, row: 1 },
                                     { id: "l", kind: "calendar", size: "large", col: 0, row: 2 }], w, h, 30);
            const gap = Widgets.grid(w, h, 30).gap;
            return [s[1].w, s[2].w, s[2].h].every(v => v === 2 * s[0].w + gap) && s[1].h === s[0].h;
        };
        check("widgets: a medium or large one spans two cells and their gap", [spans(2560, 1440), spans(1920, 1200)], [true, true]);
        const p = Widgets.rects(Widgets.defaults.layout, 1080, 1920, top);
        check("widgets: carried to a portrait screen, apart, inside", [p.length, apart(p), inside(p, 1080, 1920)],
              [Widgets.defaults.layout.length, true, true]);
        const edge = Widgets.rects([{ id: "e", kind: "clock", size: "small", col: -1, row: -1 },
                                    { id: "f", kind: "clock", size: "medium", col: -1, row: 0 }], 2560, 1440, 37);
        check("widgets: counted from the right and the bottom, flush with those margins on any width",
              [2560 - (edge[0].x + edge[0].w), 1440 - (edge[0].y + edge[0].h), 2560 - (edge[1].x + edge[1].w),
               1920 - (Widgets.rects([{ id: "e", kind: "clock", size: "small", col: -1, row: 0 }], 1920, 1200, 31)[0].x + 150)],
              [14, 14, 14, 14]);
        const two = Widgets.rects([{ id: "a", kind: "clock", size: "small", col: 1, row: 1 },
                                   { id: "b", kind: "clock", size: "small", col: 1, row: 1 }], W, H, top);
        check("widgets: of two at one place the later moves, the first stays",
              [two[0].col, two[0].row, apart(two), Math.abs(two[1].x - two[0].x) + Math.abs(two[1].y - two[0].y) <= Widgets.grid(W, H, top).pitch],
              [1, 1, true, true]);
        const far = Widgets.rects([{ id: "z", kind: "clock", size: "medium", col: 40, row: -40 }], W, H, top)[0];
        check("widgets: a place past the grid comes to its last cell", [far.col, far.row, inside([far], W, H)],
              [Widgets.grid(W, H, top).cols - 2, -Widgets.grid(W, H, top).rows, true]);

        check("widgets: the clock placed by default", Widgets.placed("clock"), true);
        check("widgets: no such kind", Widgets.placed("evil"), false);
        Widgets.adopt(JSON.stringify({ mode: "rm -rf", layout: [{ id: "x", kind: "evil", size: "small", col: 0, row: 0 },
            { id: "c", kind: "clock", size: "huge", col: 0, row: 0 }, { id: "ok", kind: "clock", size: "small", col: 3, row: -2 },
            { id: "s", kind: "stocks", size: "medium", col: 0, row: 1 }, { id: "n", kind: "clock", size: "small", col: 0.5, row: 1 },
            { id: "o", kind: "clock", size: "small", col: 999, row: 1, options: { hours24: "rm -rf", evil: 1 } }] }));
        check("widgets: a bad or retired kind, a bad size or place dropped, far places bounded",
              Widgets.layout.map(it => [it.id, it.col, it.row]), [["ok", 3, -2], ["o", 63, 1]]);
        check("widgets: options that are not switches fall back, unknown ones go", Widgets.optionsOf(Widgets.layout[1]),
              { hours24: true });
        check("widgets: a bad mode ignored", Widgets.mode, "mirror");
        Widgets.adopt(JSON.stringify({ version: 1, mode: "mirror", layout: [
            { id: "clock", kind: "clock", size: "small", x: 0.008203125, y: 0.18958333333333333, moved: true },
            { id: "calendar", kind: "calendar", size: "medium", x: 0.008203125, y: 0.04375, moved: true },
            { id: "weather", kind: "weather", size: "small", x: 0.090234375, y: 0.18958333333333333, moved: true },
            { id: "system", kind: "system", size: "medium", x: 0.008203125, y: 0.33541666666666664, moved: true },
            { id: "corner", kind: "clock", size: "small", x: 0.92, y: 0.86, moved: true }] }));
        check("widgets: version 1's shares taken to the nearest places, from the nearer edges",
              Widgets.layout.map(it => [it.id, it.col, it.row]),
              [["clock", 0, 1], ["calendar", 0, 0], ["weather", 1, 1], ["system", 0, 3], ["corner", -1, -1]]);
        Widgets.adopt(JSON.stringify({ mode: "mirror", layout: [
            { id: "clock", kind: "clock", size: "medium", col: 5, row: 5, options: { hours24: false } },
            { id: "calendar", kind: "calendar", size: "small", col: -2, row: 3, moved: true }] }));
        check("widgets: one never moved stands where and as large as the defaults put it, its options kept",
              [Widgets.layout[0].col, Widgets.layout[0].row, Widgets.layout[0].size, Widgets.optionsOf(Widgets.layout[0]).hours24],
              [1, 2, "small", false]);
        check("widgets: one moved keeps its place and size", [Widgets.layout[1].col, Widgets.layout[1].row, Widgets.layout[1].size, Widgets.layout[1].moved],
              [-2, 3, "small", true]);
        Widgets.layout = Widgets.defaults.layout;
        const drop = (x, y) => Widgets.landing(Quickshell.screens[0]?.name ?? "", "clock", x, y, 2560, 1440, 37);
        const leftTop = drop(220, 460);
        const rightBottom = drop(2560 - 190, 1440 - 200);
        check("widgets: a drop snaps to the nearest place, counted from the nearer edges",
              [leftTop.col, leftTop.row, rightBottom.col, rightBottom.row, rightBottom.x + rightBottom.w, rightBottom.y + rightBottom.h],
              [1, 2, -1, -1, 2546, 1426]);
        const onCalendar = drop(20, 60);
        check("widgets: a drop on another widget goes to the free place nearest", apart(Widgets.rects(Widgets.defaults.layout, 2560, 1440, 37)
              .filter(it => it.id !== "clock").concat([onCalendar])), true);
        Widgets.layout = Widgets.layout.filter(it => it.id === "clock");
        check("widgets: a removed kind no longer placed", [Widgets.placed("clock"), Widgets.placed("system")], [true, false]);
        Widgets.layout = Widgets.defaults.layout;
    }

    // The lock screen's lockout countdown (modules/lockout.js) by
    // pam_faillock's rule, and the island's parts it draws (Island.lockParts).
    function testLockout() {
        const pam = "auth requisite pam_faillock.so preauth deny=10 unlock_time=60 fail_interval=86400\n"
            + "auth  requisite  pam_faillock.so  preauth deny=15 unlock_time=120 fail_interval=86400  # two\n"
            + "-auth [success=2 default=ignore] pam_systemd_home.so\n"
            + "auth [default=die] pam_faillock.so authfail deny=0\n"
            + "# auth requisite pam_faillock.so preauth deny=1 unlock_time=1\n";
        check("lockout: the steps of the preauth lines, in order",
              Lockout.steps(pam, ""), [{ deny: 10, unlock: 60, interval: 86400 }, { deny: 15, unlock: 120, interval: 86400 }]);
        check("lockout: a bare line takes faillock.conf, then the module's defaults",
              [Lockout.steps("auth required pam_faillock.so preauth\n", "deny = 10\nunlock_time = 180\n"),
               Lockout.steps("auth required pam_faillock.so preauth\n", "")],
              [[{ deny: 10, unlock: 180, interval: 900 }], [{ deny: 3, unlock: 600, interval: 900 }]]);
        const listing = "test:\nWhen                Type  Source                                           Valid\n"
            + "2026-11-05 10:00:00 SVC   login                                                V\n"
            + "2026-11-05 10:00:05 TTY   /dev/tty1                                            V\n"
            + "2026-11-05 10:00:09 SVC   login                                                I\n";
        const times = Lockout.failures(listing);
        check("lockout: the tally's valid failures, local time", [times.length, times[1] - times[0]], [2, 5000]);
        const steps = Lockout.steps(pam, "");
        const base = new Date(2026, 10, 5, 10, 0, 0).getTime();
        const tries = n => Array.from({ length: n }, (_, i) => base + i * 1000);
        const latest = n => base + (n - 1) * 1000;
        check("lockout: nine open, the tenth locks a minute, the fifteenth two",
              [Lockout.until(tries(9), steps, latest(9)), Lockout.until(tries(10), steps, latest(10)),
               Lockout.until(tries(15), steps, latest(15))],
              [0, latest(10) + 60000, latest(15) + 120000]);
        check("lockout: open again once the step's time is out",
              Lockout.until(tries(10), steps, latest(10) + 61000), 0);
        check("lockout: failures past the interval do not count",
              Lockout.until(tries(10), [{ deny: 10, unlock: 60, interval: 5 }], latest(10)), 0);
        check("lockout: a step with no unlock time holds until reset",
              Lockout.until(tries(3), [{ deny: 3, unlock: 0, interval: 900 }], latest(3) + 1e9), Infinity);
        check("lockout: what is left as m:ss", [Lockout.clock(59001), Lockout.clock(65000), Lockout.clock(3840000)],
              ["1:00", "1:05", "64:00"]);
        check("lock island: the lock alone between events",
              Island.lockParts("", "", "", "transparent"), { lead: Theme.iconLock, trail: "", mark: "", tone: "" });
        check("lock island: a level, and a device come and gone",
              [Island.lockParts("volume", "V", "42%", "#37c058").trail, Island.lockParts("bt", "B", "Connected", "#37a3de").mark,
               Island.lockParts("bt", "B", "Disconnected", "#37a3de").mark, Island.lockParts("bt", "B", "Connected", "#37a3de").tone],
              ["42%", Theme.iconCheckCircle, Theme.iconCloseCircle, "#37a3de"]);
    }

    function testBadge() {
        const ids = Badge.marks.map(m => m.id);
        check("badge: ids are unique", ids.filter((id, i) => ids.indexOf(id) !== i), []);
        check("badge: every mark is a Font Logos code point",
              Badge.marks.filter(m => m.cp < 0xF300 || m.cp > 0xF3FF).map(m => m.id), []);
        check("badge: aliases name marks", Object.values(Badge.aliases).filter(id => !Badge.byId(id)), []);
        check("badge: an id of its own", Badge.markFor("arch", []).id, "arch");
        check("badge: an alias", Badge.markFor("opensuse-tumbleweed", []).id, "tumbleweed");
        check("badge: rhel", Badge.markFor("rhel", ["fedora"]).id, "redhat");
        check("badge: a derivative by ID_LIKE", Badge.markFor("someremix", ["ubuntu", "debian"]).id, "ubuntu");
        check("badge: nothing known is Tux", Badge.markFor("plan9", []).id, "tux");
        check("badge: fc-query's charset", Badge.parseCharset("d 20-7e f000-f385\n"),
              [[13, 13], [32, 126], [61440, 62341]]);
        const saved = Badge.coverage;
        Badge.coverage = Badge.parseCharset("20-7e f000-f37f");
        check("badge: a mark the font lacks is not offered", Badge.offered.some(m => m.id === "cachyos"), false);
        check("badge: one it has is", Badge.offered.some(m => m.id === "void"), true);
        check("badge: a missing own mark falls to ID_LIKE", Badge.markFor("cachyos", ["arch"]).id, "arch");
        Badge.coverage = saved;
        Badge.choose("void");
        check("badge: a choice", Badge.current.id, "void");
        Badge.choose("no-such-mark");
        check("badge: an unknown choice is automatic", Badge.choice, "auto");
        check("badge: automatic is the system's", Badge.current.id, Badge.autoMark.id);
    }

    // The cheatsheet's rows (services/Shortcuts.qml), from hyprctl's shape.
    function testShortcuts() {
        check("shortcuts: a mouse button by its side", Shortcuts.keyCap("mouse:272"), "Left click");
        check("shortcuts: a media key as printed", Shortcuts.keyCap("XF86AudioRaiseVolume"), "Volume +");
        check("shortcuts: an arrow as a key draws it", Shortcuts.keyCap("Down"), "↓");
        check("shortcuts: a letter in capitals", Shortcuts.keyCap("s"), "S");
        check("shortcuts: punctuation in either case", ["BracketLeft", "bracketright", "Slash"].map(k => Shortcuts.keyCap(k)),
              ["[", "]", "/"]);
        check("shortcuts: modifiers in a keyboard's order", Shortcuts.chord(65, "S").caps, ["Super", "Shift", "S"]);
        check("shortcuts: a lone Super is tapped", Shortcuts.chord(64, "SUPER_L"), { caps: ["Super"], note: "tap" });
        check("shortcuts: the lid is no key", Shortcuts.chord(0, "switch:on:Lid Switch"), { caps: [], note: "Lid closed" });
        const b = (description, modmask, key) => ({ description, modmask, key });
        const built = Shortcuts.build([
            b("Terminal", 64, "Return"), b("Move window down", 65, "J"), b("Move window down", 65, "Down"),
            b("Workspace 1", 64, "1"), b("Workspace 2", 64, "2"), b("Workspace 10", 64, "0"),
            b("", 64, "X"), b("Lock", 12, "L")
        ]);
        check("shortcuts: groups in their order, the empty left out", built.map(g => g.name),
              ["Applications", "Windows", "Workspaces", "Session"]);
        check("shortcuts: an action's chords on one row", built[1].rows[0].chords.map(c => c.caps.join("+")),
              ["Super+Shift+J", "Super+Shift+↓"]);
        check("shortcuts: numbered actions as a range", [built[2].rows[0].what, built[2].rows[0].to],
              ["Workspace 1–10", "0"]);
        check("shortcuts: a search by words", Shortcuts.filter(built, "lock").map(g => g.rows[0].what), ["Lock"]);
        // "lock" typed with the input method in Hangul: two jamo and one syllable.
        const lockInHangul = String.fromCodePoint(0x3163, 0x3150, 0xcc28);
        check("shortcuts: the wallpaper picker is the shell's", Shortcuts.groupOf("Pick the wallpaper"), "Shell");
        check("shortcuts: Hangul typed for latin", Shortcuts.latinOf(lockInHangul), "lock");
        check("shortcuts: and found", Shortcuts.filter(built, lockInHangul).map(g => g.rows[0].what), ["Lock"]);
        check("shortcuts: a search by a key", Shortcuts.filter(built, "j").length, 1);
        check("shortcuts: nothing found", Shortcuts.filter(built, "zzzz"), []);
    }

    // Which panels stand together (services/Surfaces.qml). The panels' own
    // reports are made here by hand, as each panel makes them.
    function testSurfaces() {
        const asked = [];
        const listen = name => asked.push(name);
        Surfaces.shown = [];
        Surfaces.shut.connect(listen);
        Surfaces.report("displays", true);
        Surfaces.report("controls", true);
        check("surfaces: a transient opens over the display panel", asked, []);
        check("surfaces: and has the keys", Surfaces.top, "controls");
        Surfaces.report("launcher", true);
        check("surfaces: one transient at a time", asked, ["controls"]);
        Surfaces.report("controls", false);
        check("surfaces: the display panel stays under", Surfaces.shown, ["displays", "launcher"]);
        Surfaces.report("launcher", false);
        check("surfaces: and has the keys back", Surfaces.top, "displays");
        asked.length = 0;
        Surfaces.report("session", true);
        check("surfaces: the session dialog shuts the rest", asked, ["displays"]);
        check("surfaces: nothing opens over it", Surfaces.mayOpen("launcher"), false);
        check("surfaces: but itself", Surfaces.mayOpen("session"), true);
        Surfaces.report("displays", false);
        Surfaces.report("session", false);
        check("surfaces: all may open after it", Surfaces.mayOpen("weather"), true);
        Surfaces.shut.disconnect(listen);
        Surfaces.shown = [];
    }

    // The control centre's Wi-Fi rows and glyphs, and its one open section.
    function testControls() {
        const n = (name, connected, known, signal, secured) => ({ name, connected, known, signal, secured });
        check("controls: in use, then saved, then the rest",
              Controls.networkOrder([n("b", false, false, 0.9, true), n("a", false, true, 0.2, true),
                                     n("c", true, true, 0.4, true)], 7).map(x => x.name), ["c", "a", "b"]);
        check("controls: strongest first within a group",
              Controls.networkOrder([n("weak", false, false, 0.2, true), n("strong", false, false, 0.8, true)], 7)
                  .map(x => x.name), ["strong", "weak"]);
        check("controls: one row per name, its strongest kept",
              Controls.networkOrder([n("x", false, false, 0.3, true), n("x", false, false, 0.8, true)], 7)
                  .map(x => x.signal), [0.8]);
        check("controls: a hidden network has no row", Controls.networkOrder([n("", false, false, 0.9, false)], 7), []);
        check("controls: at most the rows asked for",
              Controls.networkOrder([n("a", false, false, 0.1, false), n("b", false, false, 0.2, false),
                                     n("c", false, false, 0.3, false)], 2).map(x => x.name), ["c", "b"]);
        check("controls: four steps of signal",
              [0, 0.24, 0.25, 0.49, 0.5, 0.74, 0.75, 1].map(s => Controls.wifiGlyph(s, false).codePointAt(0)),
              [0xF091F, 0xF091F, 0xF0922, 0xF0922, 0xF0925, 0xF0925, 0xF0928, 0xF0928]);
        check("controls: a lock where a password is asked", Controls.wifiGlyph(0.8, true).codePointAt(0), 0xF092A);
        check("theme: the bar's Wi-Fi steps are the strength glyphs, no lock or warning among them",
              [Theme.iconWifi1, Theme.iconWifi2, Theme.iconWifi3, Theme.iconWifi4].map(g => g.codePointAt(0)),
              [0xF091F, 0xF0922, 0xF0925, 0xF0928]);
        Controls.expanded = "";
        Controls.expand("wifi");
        check("controls: a section opens", Controls.expanded, "wifi");
        Controls.expand("sound");
        check("controls: another takes its place", Controls.expanded, "sound");
        Controls.expand("sound");
        check("controls: and shuts again", Controls.expanded, "");
    }

    function testApps() {
        const terminal = [Paths.hyprScripts + "/terminal.sh", "-e"];
        check("apps: an entry's command", Apps.argvOf({ command: ["kakaotalk"], runInTerminal: false }), ["kakaotalk"]);
        check("apps: in a terminal when it asks for one", Apps.argvOf({ command: ["htop"], runInTerminal: true }),
              terminal.concat(["htop"]));
        check("apps: else its Exec line, field codes out", Apps.argvOf({ command: [], execString: "app %U --new" }),
              ["sh", "-c", "app  --new"]);
        check("apps: and nothing with neither", Apps.argvOf({ command: [], execString: " %f " }), []);
    }

    function testTray() {
        check("tray: mnemonics", ["_Exit", "Save__as", "a_b__c", "plain"].map(t => Tray.plainLabel(t)),
              ["Exit", "Save_as", "ab_c", "plain"]);
        let clicked = "";
        const entry = (text, extra) => Object.assign({ text: text, enabled: true, isSeparator: false, hasChildren: false,
                                                       checkState: Qt.Unchecked, triggered: () => { clicked = text; } },
                                                     extra ?? {});
        const sep = { isSeparator: true };
        const menu = Tray.menuEntries([sep, entry("_Open"), sep, sep, entry("Languages", { hasChildren: true }),
                                       entry("Signed in", { enabled: false }), entry("_Mute", { checkState: Qt.Checked }),
                                       sep, entry("_Exit"), sep]);
        check("tray: an item's menu, its top level, separators collapsed", menu.map(e => e.separator ? "-" : e.label),
              ["Open", "-", "Mute", "-", "Exit"]);
        check("tray: a checked entry", menu[2].checked, true);
        menu[4].action();
        check("tray: an entry triggers its own", clicked, "_Exit");
        check("tray: applications' items only", [Category.ApplicationStatus, Category.Communications, Category.SystemServices,
                                                Category.Hardware].map(c => Tray.isApplication({ category: c })),
              [true, true, false, false]);
        check("tray: Quit for a hider", Tray.processEntries({ name: "Hider", pid: 1, stuck: false }).map(e => e.label),
              ["Quit Hider"]);
        check("tray: Force quit once Quit has failed", Tray.processEntries({ name: "Hider", pid: 1, stuck: true }).map(e => e.label),
              ["Quit Hider", "Force quit Hider"]);
        const hider = { name: "Hider", pid: 1, entry: "hider", quitting: false, stuck: false };
        check("tray: Open first for a hider with a desktop entry", Tray.processEntries(hider).map(e => e.label),
              ["Open Hider", "Quit Hider"]);
        check("tray: no Open while it quits",
              Tray.processEntries(Object.assign({}, hider, { quitting: true })).map(e => e.label), ["Quit Hider"]);
        check("tray: nor once it is stuck, Force quit after Quit",
              Tray.processEntries(Object.assign({}, hider, { quitting: true, stuck: true })).map(e => e.label),
              ["Quit Hider", "Force quit Hider"]);
        check("tray: a click opens only a hider with an entry that is not quitting",
              [hider, Object.assign({}, hider, { entry: "" }), Object.assign({}, hider, { quitting: true })].map(p => Tray.canOpen(p)),
              [true, false, false]);
        check("tray: an entry id with no desktop entry behind it opens nothing",
              Tray.looks({ process: "qs-tray-hider", entry: "qs-no-such-entry" }).entry, "");
        check("tray: the suite's own hider list", Tray.hiders.map(h => h.process), ["qs-tray-hider"]);
    }

    readonly property string trayDir: Quickshell.env("TRAY_TEST_DIR") ?? ""

    // The stand-ins as the kernel sees them, read by trayLook() and kept in
    // trayProcs for the next step: a FileView moved from file to file gave
    // the previous file's text back for a file that was gone.
    property var trayProcs: ({})

    Process {
        id: trayProbe

        command: ["sh", "-c", 'for f in "$1"/*.pid; do [ -f "$f" ] || continue; t=${f##*/}; p=$(cat "$f"); '
                  + 'n=$(cat "/proc/$p/comm" 2>/dev/null); s=$(cut -d" " -f3 "/proc/$p/stat" 2>/dev/null); '
                  + 'echo "${t%.pid} $p ${n:--} ${s:--}"; done', "sh", root.trayDir]

        stdout: StdioCollector {
            onStreamFinished: {
                const procs = {};
                for (const line of this.text.split("\n")) {
                    const [tag, pid, name, state] = line.trim().split(" ");
                    if (tag)
                        procs[tag] = { pid: Number(pid), name: name, running: name !== "-" && state !== "Z" };
                }
                root.trayProcs = procs;
            }
        }
    }

    function trayLook() {
        trayProbe.running = true;
    }

    function trayPid(tag): int {
        return root.trayProcs[tag]?.pid ?? 0;
    }

    function trayRuns(tag): bool {
        return root.trayProcs[tag]?.running ?? false;
    }

    // A stand-in by its binary's name (qml.sh's copies of sleep), its pid in
    // TRAY_TEST_DIR/TAG.pid; one ignoring TERM as a hung application would.
    function trayStart(tag, binary, ignoreTerm) {
        Quickshell.execDetached(["sh", "-c", `${ignoreTerm ? "trap '' TERM; " : ""}"$1" 20 & echo $! > "$2"`,
                                 "sh", binary, `${root.trayDir}/${tag}.pid`]);
    }

    // Found by name, quit by TERM; one that ignores TERM is offered Force
    // quit after the grace; a pid that has changed hands is not signalled.
    function traySteps() {
        return [
            { wait: 0, run: () => {
                check("tray: no hider at the start", Tray.running.length, 0);
                root.trayStart("hider", "qs-tray-hider", false);
            } },
            { wait: 300, run: () => {
                Tray.scan();
                root.trayLook();
            } },
            { wait: 500, run: () => {
                check("tray: a hider is found by its name", Tray.running.map(p => [p.name, p.pid]),
                      [["Hider", root.trayPid("hider")]]);
                check("tray: with the icon it was given", Tray.running[0]?.icon, "file:///nonexistent/hider.png");
                check("tray: and no desktop entry, so no Open", Tray.processEntries(Tray.running[0]).map(e => e.label),
                      ["Quit Hider"]);
                Tray.quit(root.trayPid("hider"), false);
            } },
            { wait: 1000, run: () => root.trayLook() },
            { wait: 300, run: () => {
                check("tray: Quit ends it", root.trayRuns("hider"), false);
                check("tray: and its icon goes", Tray.running.length, 0);
                root.trayStart("stubborn", "qs-tray-hider", true);
            } },
            { wait: 300, run: () => {
                Tray.scan();
                root.trayLook();
            } },
            { wait: 500, run: () => {
                check("tray: one that ignores TERM", Tray.running.map(p => p.pid), [root.trayPid("stubborn")]);
                Tray.quit(root.trayPid("stubborn"), false);
            } },
            { wait: 1000, run: () => check("tray: is quitting, not stuck, within the grace",
                                           Tray.running.map(p => [p.quitting, p.stuck]), [[true, false]]) },
            { wait: Theme.trayQuitGraceMs, run: () => {
                check("tray: is stuck after it", Tray.running.map(p => p.stuck), [true]);
                check("tray: and is offered Force quit", Tray.processEntries(Tray.running[0]).length, 2);
                Tray.quit(root.trayPid("stubborn"), true);
            } },
            { wait: 1000, run: () => root.trayLook() },
            { wait: 300, run: () => {
                check("tray: Force quit ends it", [root.trayRuns("stubborn"), Tray.running.length], [false, 0]);
                root.trayStart("other", "qs-tray-other", false);
            } },
            { wait: 300, run: () => root.trayLook() },
            { wait: 300, run: () => {
                const pid = root.trayPid("other");
                Tray.running = [{ process: "qs-tray-hider", name: "Hider", icon: "", pid: pid, quitting: false, stuck: false }];
                Tray.quit(pid, false);
            } },
            { wait: 800, run: () => root.trayLook() },
            { wait: 300, run: () => {
                check("tray: Quit leaves a pid that changed hands alone", root.trayRuns("other"), true);
                check("tray: and drops its icon", Tray.running.length, 0);
                Quickshell.execDetached(["kill", String(root.trayPid("other"))]);
            } }
        ];
    }

    // Hyprland's screencastv2 data, as ScreenShare takes it.
    function testScreenShare() {
        ScreenShare.take("1,monitor,HEADLESS-1");
        check("share: not before it has lasted", ScreenShare.active, false);
        ScreenShare.take("0,monitor,HEADLESS-1");
        check("share: a screenshot's copy leaves nothing", Object.keys(ScreenShare.shares), []);
        ScreenShare.take("0,monitor,HEADLESS-1");
        check("share: a stop with no start is passed over", Object.keys(ScreenShare.shares), []);
        ScreenShare.take("1");
        ScreenShare.take("1,monitor");
        check("share: data without a type and a name is passed over", Object.keys(ScreenShare.shares), []);
        ScreenShare.take("1,window,a title, with commas");
        check("share: every window under one key", Object.keys(ScreenShare.shares), ["window,"]);
        ScreenShare.take("0,window,the title it has now");
        check("share: a window share stops under another name", Object.keys(ScreenShare.shares), []);
        check("share: the clock under an hour", ScreenShare.clockText(61000), "1:01");
        check("share: the clock past an hour", ScreenShare.clockText(3723000), "1:02:03");
        check("share: the clock before its first second", ScreenShare.clockText(-5), "0:00");
    }

    // Two shares at once, which last, and who shares them, from the
    // stand-in pw-dump (tests/unit/qml.sh).
    property real shareRead: 0

    function shareSteps() {
        return [
            { wait: 10, run: () => {
                ScreenShare.take("1,monitor,HEADLESS-1");
                ScreenShare.take("1,window,a call");
            } },
            { wait: Theme.shareLastsMs + 300, run: () => {
                check("share: counted once it has lasted", ScreenShare.lasting.map(s => s.type).sort(), ["monitor", "window"]);
                check("share: a whole screen named before a window", ScreenShare.kind, "monitor");
                check("share: the clock runs from the start", ScreenShare.now - ScreenShare.since >= Theme.shareLastsMs, true);
                root.shareRead = ScreenShare.now;
            } },
            { wait: 1500, run: () => {
                // Read last when the share came to count, a little after a
                // whole second of it; the next reading is on the next one.
                check("share: the clock read again on the next second", ScreenShare.now - root.shareRead > 500, true);
                check("share: on the share's own seconds", (ScreenShare.now - ScreenShare.since) % 1000 < 300, true);
                check("share: the program at the screen's far end in PipeWire", ScreenShare.apps, [{ name: "Share Test", icon: "" }]);
                ScreenShare.take("0,monitor,HEADLESS-1");
                check("share: one of two stopped, the other goes on", ScreenShare.kind, "window");
                ScreenShare.take("0,window,a call renamed");
                check("share: over when both have stopped", ScreenShare.active, false);
                check("share: and who shared goes with it", ScreenShare.apps, []);
            } }
        ];
    }

    // The island's system events (services/Island.qml): what comes first,
    // what waits, what replaces what, and how long each stays.
    function islandSteps() {
        return [
            { wait: 10, run: () => {
                // As the bar starts: testIsland made the arbiter seconds ago.
                Island.quiet = true;
                Island.alert("power", "", "Charging", "81%", 0.81, Theme.accentGreen);
                check("island: an alert as the bar starts is the state, not news", Island.kind, "");
                Island.quiet = false;
                Island.show("volume", "", "Volume", "40", 0.4, -1, Theme.islandBlue, true);
                Island.alert("power", "", "Charging", "81%", 0.81, Theme.accentGreen);
                check("island: a readout comes at once", Island.kind, "volume");
                check("island: an alert waits while a readout is up", Island.text, "Volume");
            } },
            { wait: Theme.islandReadoutMs + 200, run: () => {
                check("island: the alert once the readout has gone", Island.text, "Charging");
                check("island: with its value and its cell", [Island.value, Island.battery, Island.level], ["81%", 0.81, -1]);
                Island.alert("bluetooth", "", "Headphones", "Connected", -1, Theme.accentAzure);
                check("island: a newer alert replaces an older one", Island.text, "Headphones");
                Island.show("brightness", "", "Brightness", "60", 0.6, -1, Theme.accentAmber, true);
                check("island: a readout comes over an alert", Island.kind, "brightness");
            } },
            { wait: Theme.islandReadoutMs + 200, run: () => {
                check("island: an alert a readout came over comes back while time is left", Island.text, "Headphones");
            } },
            { wait: Theme.islandAlertMs, run: () => {
                check("island: and goes when its time is up", Island.kind, "");
            } }
        ];
    }

    // The island's colours and what the power and Bluetooth say on it
    // (Theme, services/Island.qml, services/Media.qml), and OBS's protocol
    // as services/Obs.qml reads it, fed by hand: no OBS here.
    function testIsland() {
        check("island: a colour's companion is it times 0.40", String(Theme.islandDim(Theme.islandRed)), "#641514");
        check("island: a tinted button is it times 0.23", String(Theme.islandTint(Theme.islandRed)), "#3a0c0c");
        check("island: the clock under an hour", Theme.clockText(61000), "1:01");
        check("island: the clock past an hour", Theme.clockText(3723000), "1:02:03");

        const plugged = { charging: true, full: false, onBattery: false, percent: 64 };
        const unplugged = { charging: false, full: false, onBattery: true, percent: 64 };
        const first = Island.powerStep(null, unplugged);
        check("power: the first look is the state, not news", first.alert, null);
        const inStep = Island.powerStep(first.state, plugged);
        check("power: the cord in says charging", [inStep.alert?.text, inStep.alert?.value], ["Charging", "64%"]);
        const outStep = Island.powerStep(inStep.state, unplugged);
        check("power: the cord out says so too", [outStep.alert?.text, outStep.alert?.battery], ["Unplugged", 0.64]);
        check("power: nothing changed, nothing said", Island.powerStep(outStep.state, unplugged).alert, null);
        const full = Island.powerStep(inStep.state, { charging: false, full: true, onBattery: false, percent: 100 });
        check("power: full on the cord", full.alert?.text, "Fully charged");
        const low = Island.powerStep(outStep.state, { charging: false, full: false, onBattery: true, percent: 9 });
        check("power: low on the cell", low.alert?.text, "Low battery");

        const bt0 = Island.btStep(null, [{ address: "A", name: "Earbuds", battery: 0.75 }]);
        check("bluetooth: the first look is the state", bt0.alerts, []);
        const bt1 = Island.btStep(bt0.state, [{ address: "A", name: "Earbuds", battery: 0.75 },
                                              { address: "B", name: "Mouse", battery: -1 }]);
        check("bluetooth: a device in, with its battery or without",
              bt1.alerts.map(a => [a.text, a.value]), [["Mouse", "Connected"]]);
        const bt2 = Island.btStep(bt1.state, [{ address: "B", name: "Mouse", battery: -1 }]);
        check("bluetooth: a device gone is said too", bt2.alerts.map(a => [a.text, a.value]), [["Earbuds", "Disconnected"]]);

        // Wired outputs, as AudioDevices.islandView hands them over: USB devices by
        // card, the jack's verdict from AudioPolicy.
        const view = (outs, jack, jackLabel) => ({ outs: outs, jack: jack ?? "", jackLabel: jackLabel ?? "" });
        const told = step => step.alerts.map(a => [a.text, a.value]);
        const usbOut = { label: "USB Earphones", kind: "usb" };
        const out0 = Island.outputsStep(null, view({ "87": usbOut }));
        check("outputs: the first look is the state", out0.alerts, []);
        const outIn = Island.outputsStep(view({}), view({ "87": usbOut }));
        check("outputs: a USB output plugged in", told(outIn), [["USB Earphones", "Connected"]]);
        check("outputs: drawn as the Bluetooth pair is",
              [outIn.alerts[0].glyph, String(outIn.alerts[0].tone)], [Theme.iconHeadphones, String(Theme.islandBlue)]);
        check("outputs: and pulled out", told(Island.outputsStep(outIn.state, view({}))), [["USB Earphones", "Disconnected"]]);
        check("outputs: plugged in again within one settle reads as plugged in",
              told(Island.outputsStep(outIn.state, view({ "93": usbOut }))),
              [["USB Earphones", "Disconnected"], ["USB Earphones", "Connected"]]);
        check("outputs: the same card, nothing to tell", told(Island.outputsStep(outIn.state, view({ "87": usbOut }))), []);
        // The lock screen's island: one glyph leading, one number or mark trailing.
        const lockRest = Island.lockCompact("", "", "", Theme.islandText);
        check("lock island: the lock alone between events", [lockRest.lead, lockRest.trail, lockRest.mark], [Theme.iconLock, "", ""]);
        const lockLevel = Island.lockCompact("volume", Theme.iconVolume, "45", Theme.islandBlue);
        check("lock island: the event's glyph in its colour",
              lockLevel.lead, `<span foreground="${Island.hexOf(Theme.islandBlue)}">${Theme.iconVolume}</span>`);
        check("lock island: a level padded to one width, a clear % in front so it ends at the right",
              [lockLevel.trail, lockLevel.mark],
              [`<span font_features="tnum"><span alpha="1">%</span><span foreground="${Island.hexOf(Theme.islandBlue)}"> 45</span></span>`, ""]);
        check("lock island: a percentage padded the same, a full one not",
              [Island.lockCompact("power", Theme.iconBolt, "70%", Theme.islandGreen).trail,
               Island.lockCompact("power", Theme.iconBolt, "100%", Theme.islandGreen).trail,
               Island.lockCompact("power", Theme.iconBolt, "5%", Theme.islandGreen).trail],
              [" 70%", "100%", "  5%"].map(v => `<span font_features="tnum" foreground="${Island.hexOf(Theme.islandGreen)}">${v}</span>`));
        check("lock island: a device come gets the tick, gone the cross, no number",
              [Island.lockCompact("output", Theme.iconHeadphones, "Connected", Theme.islandBlue).mark,
               Island.lockCompact("output", Theme.iconHeadphonesOff, "Disconnected", Theme.islandSubtext).mark,
               Island.lockCompact("output", Theme.iconHeadphones, "Connected", Theme.islandBlue).trail],
              [`<span foreground="${Island.hexOf(Theme.islandBlue)}">${Theme.iconCheckCircle}</span>`,
               `<span foreground="${Island.hexOf(Theme.islandSubtext)}">${Theme.iconCloseCircle}</span>`, ""]);
        check("lock island: any other word is left out, the glyph alone",
              [Island.lockCompact("bluetooth", Theme.iconBtLinked, "Pairing", Theme.islandBlue).trail,
               Island.lockCompact("bluetooth", Theme.iconBtLinked, "Pairing", Theme.islandBlue).mark], ["", ""]);
        check("lock island: markup in a glyph is escaped", Island.lockCompact("x", "<b>&", "1", Theme.islandText).lead,
              `<span foreground="${Island.hexOf(Theme.islandText)}">&lt;b&gt;&amp;</span>`);
        check("lock island: colours as hyprlock's markup reads them", Island.hexOf(Qt.rgba(55 / 255, 163 / 255, 222 / 255, 1)), "#37a3de");
        check("outputs: the jack as AudioPolicy tells it",
              [told(Island.outputsStep(view({}), view({}, "plugged", "Headphones"))),
               told(Island.outputsStep(view({}), view({}, "pulled", "Headphones")))],
              [[["Headphones", "Connected"]], [["Headphones", "Disconnected"]]]);

        // The policy, on snapshots as AudioDevices.snapshot() makes them: the
        // laptop's card 45 and what is plugged in; `at` in ms.
        const dev = (dir, name, kind, priority, serial, more) => Object.assign(
            { dir: dir, name: name, label: name, kind: kind, card: "45", priority: priority, serial: serial, webcam: false }, more ?? {});
        const card = {
            "spk#52": dev("sink", "spk", "fallback", 712, 52), "hp#53": dev("sink", "hp", "jack", 1000, 53),
            "hdmi#54": dev("sink", "hdmi", "", 664, 54),
            "mic#57": dev("source", "mic", "fallback", 1584, 57), "hs#58": dev("source", "hs", "jack", 1728, 58)
        };
        const usbPair = {
            "usbOut#161": dev("sink", "usbOut", "usb", 1109, 161, { card: "87" }),
            "usbIn#162": dev("source", "usbIn", "usb", 2109, 162, { card: "87" })
        };
        const shot = (at, extra, sink, source, more) => Object.assign({
            at: at, nodes: Object.assign({}, card, extra),
            sink: { def: sink[0], conf: sink[1] }, source: { def: source[0], conf: source[1] }
        }, more ?? {});
        // What AudioDevices carries over: the step's jackIn and cardSince on the snapshot.
        const carried = (snap, step) => Object.assign({}, snap, { jackIn: step.jackIn, cardSince: step.cardSince });
        const run = (was, now, quiet) => {
            const step = AudioPolicy.step(was, now, quiet ?? false);
            return { step: step, state: carried(now, step) };
        };
        const wants = r => r.step.intents.map(i => [i.dir, i.name, i.why]);
        const calm = run(null, shot(0, {}, ["hp", "hp"], ["hs", "hs"]));
        check("policy: nothing plugged in from the first snapshot",
              wants(run(null, shot(0, usbPair, ["hp", "hp"], ["hs", "hs"]))), []);
        check("policy: but the speaker as the choice gives way to the jack at once",
              wants(run(null, shot(0, {}, ["spk", "spk"], ["hs", "hs"]))), [["sink", "hp", "jack first"]]);
        check("policy: and the built-in microphone to the headset jack",
              wants(run(null, shot(0, {}, ["hp", "hp"], ["mic", "mic"]))), [["source", "hs", "jack first"]]);
        const plugIn = run(calm.state, shot(10000, usbPair, ["hp", "hp"], ["hs", "hs"]));
        check("policy: a USB headset plugged in takes output and microphone",
              wants(plugIn), [["sink", "usbOut", "plugged"], ["source", "usbIn", "plugged"]]);
        check("policy: nothing to write when it is the choice already",
              wants(run(calm.state, shot(10000, usbPair, ["usbOut", "usbOut"], ["usbIn", "usbIn"]))), []);
        const outOnly = run(calm.state, shot(10000, { "usbOut#161": usbPair["usbOut#161"] }, ["hp", "hp"], ["hs", "hs"]));
        check("policy: its microphone a settle later still follows it",
              wants(run(outOnly.state, shot(10300, usbPair, ["usbOut", "usbOut"], ["hs", "hs"]))), [["source", "usbIn", "plugged"]]);
        const settled = run(plugIn.state, shot(20000, usbPair, ["usbOut", "usbOut"], ["usbIn", "usbIn"]));
        check("policy: a new node of a card seen for long is a change of profile, not a plug",
              wants(run(settled.state, shot(30000, { "usbOut#170": usbPair["usbOut#161"], "usbIn#162": usbPair["usbIn#162"] },
                                         ["hp", "hp"], ["usbIn", "usbIn"]))), []);
        check("policy: plugged in wins over the jack rule in the same settle",
              wants(run(run(null, shot(0, {}, ["spk", "spk"], ["hs", "hs"])).state, shot(10000, usbPair, ["spk", "spk"], ["hs", "hs"]))),
              [["sink", "usbOut", "plugged"], ["source", "usbIn", "plugged"]]);
        check("policy: pulled out writes nothing; WirePlumber falls back",
              wants(run(settled.state, shot(30000, {}, ["spk", ""], ["mic", ""]))), []);
        check("policy: a webcam's microphone is not taken",
              wants(run(calm.state, shot(10000, { "cam#200": dev("source", "cam", "usb", 2109, 200, { card: "90", webcam: true }) },
                                          ["hp", "hp"], ["hs", "hs"]))), []);
        const btPair = { "btOut#300": dev("sink", "btOut", "bluetooth", 1010, 300, { card: "95" }),
                         "btIn#301": dev("source", "btIn", "bluetooth", 2010, 301, { card: "95" }) };
        check("policy: Bluetooth takes both, its microphone being WirePlumber's loopback",
              wants(run(calm.state, shot(10000, btPair, ["hp", "hp"], ["hs", "hs"]))),
              [["sink", "btOut", "plugged"], ["source", "btIn", "plugged"]]);
        check("policy: of two outputs arriving at once, the higher ranked",
              wants(run(calm.state, shot(10000, { "a#400": dev("sink", "a", "bluetooth", 1010, 401, { card: "96" }),
                                                   "b#401": dev("sink", "b", "bluetooth", 1020, 400, { card: "97" }) },
                                          ["hp", "hp"], ["hs", "hs"]))),
              [["sink", "b", "plugged"]]);
        check("policy: the configured device among those arriving stays the choice",
              wants(run(calm.state, shot(10000, Object.assign({}, usbPair, btPair), ["hp", "btOut"], ["hs", "btIn"]))), []);
        check("policy: held back while quiet",
              wants(run(calm.state, shot(1000, usbPair, ["hp", "hp"], ["hs", "hs"]), true)), []);
        const noCard = run(null, shot(0, {}, ["", ""], ["", ""], { nodes: {} }));
        check("policy: the built-in card coming anew is a restart, its company no plug",
              [run(noCard.state, shot(1000, usbPair, ["usbOut", ""], ["usbIn", ""])).step.restarted,
               wants(run(noCard.state, shot(1000, usbPair, ["usbOut", ""], ["usbIn", ""])))], [true, []]);
        check("policy: an application's own sink as the choice is left alone",
              wants(run(calm.state, shot(10000, {}, ["hp", "zoomcombine"], ["hs", "hs"]))), []);
        check("policy: so is a monitor's speakers",
              wants(run(calm.state, shot(10000, {}, ["hdmi", "hdmi"], ["hs", "hs"]))), []);
        check("policy: the jack rule keeps to one card",
              wants(run(null, shot(0, { "spk2#90": dev("sink", "spk2", "fallback", 700, 90, { card: "99" }) },
                                   ["spk2", "spk2"], ["hs", "hs"]))), []);

        // The jack, read off the default.
        const onSpk = run(null, shot(0, {}, ["spk", "hp"], ["mic", "mic"]));
        check("policy: nothing known of the jack until the default has been on it", onSpk.step.jackIn, null);
        const jackIn = run(onSpk.state, shot(5000, {}, ["hp", "hp"], ["mic", "mic"]));
        check("policy: the default onto the jack is a plug", [jackIn.step.jack, jackIn.step.jackLabel, jackIn.step.jackIn], ["plugged", "hp", true]);
        const jackOut = run(jackIn.state, shot(9000, {}, ["spk", "hp"], ["mic", "mic"]));
        check("policy: and off it, still there, with nothing else chosen, a pull that pauses",
              [jackOut.step.jack, jackOut.step.pause, jackOut.step.jackIn], ["pulled", true, false]);
        check("policy: a pull too when the choice is a USB device that is gone",
              run(jackIn.state, shot(9000, {}, ["spk", ""], ["mic", "mic"])).step.jack, "pulled");
        const picked = run(jackIn.state, shot(9000, {}, ["spk", "spk"], ["mic", "mic"]));
        check("policy: the speaker picked by hand is no pull", [picked.step.jack, picked.step.pause], ["", false]);
        check("policy: and the jack coming back after it is no plug",
              run(picked.state, shot(9300, {}, ["hp", "hp"], ["mic", "mic"])).step.jack, "");
        check("policy: falling back onto the jack from a device that went away is no plug",
              run(settled.state, shot(30000, {}, ["hp", ""], ["mic", ""])).step.jack, "");
        check("policy: a USB device taking over from the jack is no pull",
              run(jackIn.state, shot(9000, usbPair, ["usbOut", "usbOut"], ["mic", "mic"])).step.jack, "");
        check("policy: a default not read yet is no move",
              run(jackIn.state, shot(9000, {}, ["", "hp"], ["mic", "mic"])).step.jack, "");
        check("policy: no pull from the first snapshot", run(null, shot(0, {}, ["spk", "hp"], ["mic", "mic"])).step.pause, false);

        check("meter: an island colour stays itself", String(Media.vivid([Theme.islandBlue])), String(Theme.islandBlue));
        check("meter: a grey cover gives white", String(Media.vivid([Qt.rgba(0.5, 0.5, 0.5, 1)])), String(Theme.islandText));
        const island = Theme.islandColor;
        check("meter: an all-black cover gives the black island's complement",
              String(Media.vivid([Qt.rgba(0, 0, 0, 1), Qt.rgba(0, 0, 0, 1)])),
              String(Qt.rgba(1 - island.r, 1 - island.g, 1 - island.b, 1)));
        check("meter: and only then: a red cover keeps its hue", Media.lch(Media.vivid([Qt.rgba(0.8, 0.1, 0.1, 1)])).h < 40, true);
        const dull = Media.lch(Media.vivid([Qt.rgba(0.5, 0.25, 0.25, 1)]));
        check("meter: a dull cover is made as strong as the island's colours", dull.c > 0.2, true);

        Obs.receive("not json");
        Obs.receive(JSON.stringify({ op: 2, d: { negotiatedRpcVersion: 1 } }));
        check("obs: told who this is", Obs.identified, true);
        Obs.receive(JSON.stringify({ op: 7, d: { requestType: "GetRecordStatus", requestId: "record",
            requestStatus: { result: true, code: 100 },
            responseData: { outputActive: true, outputPaused: false, outputDuration: 61000 } } }));
        check("obs: recording, and for how long", [Obs.active, Obs.recording, Obs.recordMs], [true, true, 61000]);
        Obs.receive(JSON.stringify({ op: 5, d: { eventType: "RecordStateChanged",
            eventData: { outputActive: true, outputState: "OBS_WEBSOCKET_OUTPUT_PAUSED" } } }));
        check("obs: paused at once", Obs.paused, true);
        Obs.receive(JSON.stringify({ op: 5, d: { eventType: "RecordStateChanged",
            eventData: { outputActive: false, outputState: "OBS_WEBSOCKET_OUTPUT_STOPPED" } } }));
        check("obs: stopped", [Obs.recording, Obs.paused, Obs.active], [false, false, false]);
        Obs.receive(JSON.stringify({ op: 7, d: { requestType: "GetStreamStatus", requestId: "stream",
            requestStatus: { result: true, code: 100 },
            responseData: { outputActive: true, outputDuration: 5000 } } }));
        check("obs: live alone", [Obs.active, Obs.streaming], [true, true]);
        Obs.receive(JSON.stringify({ op: 7, d: { requestType: "GetStreamStatus", requestId: "stream",
            requestStatus: { result: false, code: 600 }, responseData: { outputActive: false } } }));
        check("obs: a failed request changes nothing", Obs.streaming, true);
        Obs.lost();
        check("obs: the connection gone, nothing shows", [Obs.identified, Obs.active], [false, false]);

        check("event: unbounded, as wide as it holds", freeEvent.natural > tightEvent.room, true);
        check("event: held to its room", tightEvent.natural, tightEvent.room);
        check("event: the words give way, not the level or the value", tightEvent.others, freeEvent.others);
    }

    // One readout twice: free, and given less room than it holds.
    IslandEvent {
        id: freeEvent

        visible: false
        glyph: Theme.iconVolume
        text: "Brightness"
        value: "75%"
        level: 0.75
    }

    IslandEvent {
        id: tightEvent

        visible: false
        room: freeEvent.natural - Theme.px(30)
        glyph: Theme.iconVolume
        text: "Brightness"
        value: "75%"
        level: 0.75
    }

    function testBrightness() {
        check("internal: eDP", Brightness.isInternal("eDP-1"), true);
        check("internal: HDMI", Brightness.isInternal("HDMI-A-1"), false);
        check("internal: a prefix only", Brightness.isInternal("eDPX-1"), false);
    }

    // After the modules are complete, so every function they own is there.
    Timer {
        running: true
        interval: 50

        onTriggered: {
            const suites = [root.testTheme, root.testNotifications, root.testScreensaver, root.testKeyFeed,
                            root.testBrightness, root.testCamera, root.testBadge, root.testControls, root.testSurfaces,
                            root.testShortcuts, root.testWidgets, root.testLockout,
                            root.testApps, root.testTray, root.testBarOptions,
                            root.testScreenShare, root.testIsland];
            if (modules.item)
                suites.push(() => modules.item.testLauncher(root.check), () => modules.item.testDisplays(root.check));
            else
                console.log("[test] SKIP Launcher and Displays: no Wayland display");
            for (const suite of suites) {
                try {
                    suite();
                } catch (e) {
                    root.failed += 1;
                    console.log(`[test] FAIL ${suite.name}: threw ${e}`);
                }
            }
            root.steps = root.keyLockSteps()
                .concat(root.keyDir !== "" ? root.keyFeedSteps() : [])
                .concat(root.imeDir !== "" ? root.imeSteps() : [])
                .concat(root.capsFile !== "" ? root.capsSteps() : [])
                .concat(root.cavaSteps())
                .concat(root.shareSteps())
                .concat(root.islandSteps())
                .concat(root.camDir !== "" ? root.cameraSteps() : [])
                .concat(root.weatherDir !== "" ? root.weatherSteps() : [])
                .concat(root.drmDir !== "" ? root.vramSteps() : [])
                .concat(root.trayDir !== "" ? root.traySteps() : [])
                // Its programs are looked for as it starts, in a process.
                .concat(modules.item ? [{ wait: 800, run: () => modules.item.testSessionMenu(root.check) }] : []);
            if (root.camDir === "")
                console.log("[test] SKIP camera events: no CAMERA_TEST_DIR");
            if (root.keyDir === "")
                console.log("[test] SKIP key reader: no KEYFEED_TEST_DIR");
            if (root.imeDir === "")
                console.log("[test] SKIP input method: no IME_TEST_DIR");
            if (root.weatherDir === "")
                console.log("[test] SKIP weather: no WEATHER_TEST_DIR");
            if (root.drmDir === "")
                console.log("[test] SKIP system VRAM: no BAR_DRM_DIR");
            if (root.trayDir === "")
                console.log("[test] SKIP tray hiders: no TRAY_TEST_DIR");
            root.runSteps();
        }
    }
}
