pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The tablet mirror's state and settings, for its panel (modules/MirrorPanel.qml),
// its desktop widget (modules/MirrorWidget.qml) and its tile in the control centre,
// one reading for all (the user,
// 2026-11-07: write on the tablet, share it in a call). scripts/mirror.sh does the
// work. Rare, so nothing runs while neither is on the screen: they count themselves
// in `watchers`, and only then does this listen for USB devices coming and going.
// udev says when, so nothing polls the bus; only a mirror that is running is asked
// after, since a closed window sends no USB event.
Singleton {
    id: root

    // ---- the settings, kept in the bar's state ------------------------------
    // USB's 480 Mbps has room for far more than these (SM-X620 is USB 2.0). The
    // laptop only shows by default, so that a stray click cannot draw on the page,
    // and the tablet's sound stays out of the call. 30 frames since that is what
    // the call sends on, and every frame costs Zoom's encoder, which is CPU only.
    readonly property var defaults: ({ maxSize: 1920, bitRate: 16, fps: 30, codec: "h264", control: false, audio: false, fullscreen: false })
    property var saved: ({})
    readonly property var options: Object.assign({}, root.defaults, root.saved)

    function set(change: var): void {
        root.saved = Object.assign({}, root.saved, change);
        store.setText(JSON.stringify(root.saved) + "\n");
    }

    // scrcpy's words for them. Plain values in and out, for the tests. A laptop
    // that controls the tablet can also keep it awake, which scrcpy refuses without
    // control; writing keeps it awake otherwise. scrcpy's own shortcuts on Alt alone:
    // by default Super too, which is Hyprland's on this desktop (the user, 2026-11-07:
    // it must not eat Super+Q and the like; hypr/config/rules.lua has the other half).
    function args(o: var): var {
        const out = ["--window-title=Tablet", `--video-bit-rate=${o.bitRate}M`, `--max-fps=${o.fps}`];
        if (o.maxSize > 0)
            out.push(`--max-size=${o.maxSize}`);
        out.push(o.control ? "--stay-awake" : "--no-control");
        if (!o.audio)
            out.push("--no-audio");
        if (o.fullscreen)
            out.push("--fullscreen");
        if (o.codec === "h265")
            out.push("--video-codec=h265");
        out.push("--shortcut-mod=lalt");
        return out;
    }

    // ---- what is the case ---------------------------------------------------
    property string usb: "none"
    property string name: ""
    property bool running: false
    property string via: ""
    property string error: ""

    // One word for the panel, the widget and the tests.
    readonly property string state: root.running ? "running" : root.usb === "on" ? "ready" : root.usb === "off" ? "debugging" : "absent"
    readonly property bool canStart: root.state === "ready"

    function title(state: string): string {
        return ({ running: "Mirroring", ready: "Ready", debugging: "USB debugging is off", absent: "No tablet" })[state] ?? "";
    }

    function hint(state: string, error: string, name: string): string {
        if (error !== "" && state === "ready")
            return /unauthorized/i.test(error) ? "Allow USB debugging on the tablet, then start again." : error;
        return ({
            running: "Share this window or its screen in the call.",
            ready: name,
            debugging: "On the tablet: Developer options, USB debugging.",
            absent: "Plug it in by USB, in file transfer mode."
        })[state] ?? "";
    }

    function adopt(text: string): void {
        try {
            const r = JSON.parse(text);
            root.usb = r.usb ?? "none";
            root.name = r.name ?? "";
            root.running = r.running === true;
            root.via = r.via ?? "";
            root.error = r.error ?? "";
        } catch (e) {
            console.warn("[mirror] could not read the state:", e);
        }
    }

    function refresh(): void {
        if (status.running)
            status.again = true;
        else
            status.running = true;
    }

    // The panel's Start: the tablet on USB, named so, since one on the network too
    // would leave scrcpy asking which.
    function start(): void {
        if (!root.canStart)
            return;
        control.command = [Quickshell.shellPath("scripts/mirror.sh"), "start", "--select-usb"].concat(root.args(root.options));
        control.running = true;
    }

    // ---- what can be reached, while the control centre's list is open -----------
    property var devices: []
    property bool searched: false
    // While its section is open: the only time adb runs for this.
    property int scanners: 0

    onScannersChanged: {
        if (root.scanners > 0) {
            root.scan();
        } else {
            root.searched = false;
            root.devices = [];
            release.running = true;
        }
    }

    function scan(): void {
        if (root.scanners <= 0 || scanner.running)
            return;
        scanner.command = [Quickshell.shellPath("scripts/mirror.sh"), "devices", root.options.wifi ?? ""];
        scanner.running = true;
    }

    function adoptDevices(text: string): void {
        try {
            root.devices = JSON.parse(text).devices ?? [];
            root.searched = true;
        } catch (e) {
            console.warn("[mirror] could not read the devices:", e);
        }
    }

    // Words for a row of the list. Plain, for the tests.
    function deviceDetail(d: var): string {
        if (d.state === "debugging")
            return "Turn on USB debugging";
        if (d.state === "unauthorized")
            return "Allow it on the tablet";
        return d.via === "wifi" ? `Wi-Fi ${d.address.split(":")[0]}` : "USB";
    }

    function usable(d: var): bool {
        return d.state === "ready" || d.state === "offered";
    }

    function isCurrent(d: var): bool {
        return root.running && d.via === root.via;
    }

    // A row tapped: the mirror there starts, or stops if that is what runs.
    function connect(d: var): void {
        if (!root.usable(d))
            return;
        if (root.running) {
            root.stop();
            return;
        }
        if (d.via === "wifi") {
            root.set({ wifi: d.address });
            control.command = [Quickshell.shellPath("scripts/mirror.sh"), "start-wifi", d.address].concat(root.args(root.options));
        } else {
            control.command = [Quickshell.shellPath("scripts/mirror.sh"), "start", "--select-usb"].concat(root.args(root.options));
        }
        control.running = true;
    }

    // Closes the tablet's port and stops looking for it there.
    function forget(): void {
        const address = root.options.wifi ?? "";
        if (address === "")
            return;
        root.set({ wifi: "" });
        forgetter.command = [Quickshell.shellPath("scripts/mirror.sh"), "forget", address];
        forgetter.running = true;
    }

    function stop(): void {
        control.command = [Quickshell.shellPath("scripts/mirror.sh"), "stop"];
        control.running = true;
    }

    function toggle(): void {
        if (root.running)
            root.stop();
        else
            root.start();
    }

    // ---- the panel ----------------------------------------------------------
    property bool panelOpen: false
    property var panelScreen: null

    function togglePanel(screen: var): void {
        if (!root.panelOpen && !Surfaces.mayOpen("mirror"))
            return;
        if (!root.panelOpen)
            root.panelScreen = screen;
        root.panelOpen = !root.panelOpen;
    }

    // Transient, one panel at a time (services/Surfaces.qml).
    onPanelOpenChanged: Surfaces.report("mirror", root.panelOpen)

    Connections {
        target: Surfaces

        function onShut(name) {
            if (name === "mirror")
                root.panelOpen = false;
        }
    }

    // ---- listening, only while someone looks ------------------------------------
    property int watchers: 0

    onWatchersChanged: {
        if (root.watchers > 0)
            root.refresh();
    }

    Process {
        running: root.watchers > 0
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("UDEV "))
                    settle.restart();
            }
        }
    }

    // A device coming up is a burst of events, and debugging switched on is a
    // device going and coming back.
    Timer {
        id: settle

        interval: 500
        onTriggered: {
            root.refresh();
            root.scan();
        }
    }

    // Nothing announces a tablet on the network: asked again while the list is open.
    Timer {
        interval: 5000
        repeat: true
        running: root.scanners > 0
        onTriggered: root.scan()
    }

    Process {
        id: scanner

        stdout: StdioCollector {
            onStreamFinished: root.adoptDevices(this.text)
        }
    }

    Process {
        id: release

        command: [Quickshell.shellPath("scripts/mirror.sh"), "release"]
    }

    Process {
        id: forgetter

        onExited: root.scan()
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.watchers > 0 && root.running
        onTriggered: root.refresh()
    }

    Process {
        id: status

        property bool again: false

        command: [Quickshell.shellPath("scripts/mirror.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: root.adopt(this.text)
        }
        onExited: {
            if (status.again) {
                status.again = false;
                status.running = true;
            }
        }
    }

    Process {
        id: control

        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "")
                    root.error = this.text.trim();
            }
        }
        onExited: {
            root.refresh();
            root.scan();
        }
    }

    // A mirror outlives the bar (scripts/mirror.sh), so one is looked for as this
    // starts: the temporary widget stands on it (Widgets.drawnFor).
    Component.onCompleted: root.refresh()

    // For scripts and the end-to-end tests: qs ipc call mirror toggle.
    IpcHandler {
        target: "mirror"

        function toggle(): void {
            root.toggle();
        }
        function panel(): void {
            root.togglePanel(Screens.focused);
        }
        function state(): string {
            return root.state;
        }
        function list(): string {
            return JSON.stringify(root.devices);
        }
        function connect(index: int): void {
            const d = root.devices[index];
            if (d)
                root.connect(d);
        }
    }

    FileView {
        id: store

        path: Paths.stateDir + "/mirror.json"
        // Missing until the first change: the defaults then stand.
        printErrors: false
        onLoaded: {
            try {
                root.saved = JSON.parse(store.text());
            } catch (e) {
                console.warn("[mirror] could not read", store.path);
            }
        }
    }
}
