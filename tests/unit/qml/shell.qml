import QtQuick
import Quickshell
import Quickshell.Io
import "modules"
import qs.services

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
        check("art: an allowed host", Theme.localArt("https://i.scdn.co/image/x"), "https://i.scdn.co/image/x");
        check("art: a local file", Theme.localArt("file:///tmp/cover.png"), "file:///tmp/cover.png");
        check("art: plain http", Theme.localArt("http://i.scdn.co/image/x"), "");
        check("art: an allowed name as a prefix of another host", Theme.localArt("https://i.scdn.co.evil.example/x"), "");
        check("art: an allowed name as userinfo", Theme.localArt("https://i.scdn.co@evil.example/x"), "");
        check("art: userinfo before an allowed host", Theme.localArt("https://user@i.scdn.co/x"), "https://user@i.scdn.co/x");
        check("art: a port on an allowed host", Theme.localArt("https://i.scdn.co:8443/x"), "https://i.scdn.co:8443/x");
        check("art: upper case host", Theme.localArt("https://I.SCDN.CO/x"), "https://I.SCDN.CO/x");
        check("art: empty", Theme.localArt(""), "");
        check("shorten: short", Theme.shorten("kitty", 8), "kitty");
        check("shorten: long", Theme.shorten("abcdefghij", 5), "abcd…");
        check("fit: no screen", Theme.fit(null), 1);
    }

    function testNotifications() {
        check("img: removed", Notifications.withoutImages("a<img src=\"https://x/y.png\">b"), "ab");
        check("img: upper case", Notifications.withoutImages("<IMG SRC=x>text"), "text");
        check("img: spaces", Notifications.withoutImages("< img src=x >text"), "text");
        check("img: unclosed", Notifications.withoutImages("text<img src=https://x"), "text");
        check("img: other markup kept", Notifications.withoutImages("<b>bold</b>"), "<b>bold</b>");
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
        check("camera: tooltip head", Camera.describe(reading("off", [cam("A", "off")]), "").split("\n")[0], "Cameras off");
        check("camera: nothing to say while on", Camera.describe(reading("on", [cam("A", "on")]), ""), "");
        check("camera: a leak names the node",
              Camera.describe(reading("off", [cam("A", "on")]), "").split("\n")[1], "On        A  video0");
        check("camera: a failed check is said",
              Camera.describe(reading("off", [cam("A", "off")]), "exited with 1").split("\n").pop(), "Not rechecked: exited with 1");
        const gaps = reading("off", [cam("A", "off")]);
        gaps.missing = ["the udev rule is not installed"];
        check("camera: setup gaps are pointed at", Camera.describe(gaps, "").indexOf("Setup     incomplete") !== -1, true);
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
                            root.testBrightness, root.testCamera];
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
            root.steps = root.camDir !== "" ? root.cameraSteps() : [];
            if (root.camDir === "")
                console.log("[test] SKIP camera events: no CAMERA_TEST_DIR");
            root.runSteps();
        }
    }
}
