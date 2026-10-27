pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import qs.services

// OBS Studio's recording and stream, for the island (MediaChip.qml), shown
// the way what plays is (the user, 2026-10-26). Told by OBS itself over its
// WebSocket server (obs-websocket 5, built in since OBS 28): nothing outside
// shows whether it records, its microphone and capture staying open for the
// preview either way. The server runs only once switched on (Tools >
// WebSocket Server Settings); until then OBS shows nothing here. Its port and
// password are read by scripts/obs-auth.py, which also answers the challenge,
// so the password never enters the bar.
//
// Asked only while OBS is open (a window, or its tray item), never polled: a
// refused connection is tried again a few times, then once a minute, a local
// connect each. A refused password waits until OBS reopens. The socket
// (ObsSocket.qml) loads only while OBS is open, from its own file: without
// Qt's WebSockets module only that file fails, not the island.
Singleton {
    id: root

    // OBS_WEBSOCKET_PORT points the tests at a stand-in server, which stands
    // for OBS being open.
    readonly property int testPort: Number(Quickshell.env("OBS_WEBSOCKET_PORT") ?? 0) || 0
    readonly property bool open: root.testPort > 0
        || ToplevelManager.toplevels.values.some(t => root.isObs(t?.appId))
        || SystemTray.items.values.some(i => root.isObs(i?.id))

    function isObs(name): bool {
        return /^(com\.obsproject\.studio|obs)$/i.test(String(name ?? ""));
    }

    // What OBS reports; nothing until it has answered.
    property bool identified: false
    property bool recording: false
    property bool paused: false
    property bool streaming: false
    // A recording's and a stream's length when OBS last gave it, and when.
    property real recordMs: 0
    property real recordAt: 0
    property real streamMs: 0
    property real streamAt: 0

    readonly property bool active: root.identified && (root.recording || root.streaming)

    // The clocks, read again on each whole second of the recording, or of
    // the stream when only that runs.
    property real now: Date.now()
    readonly property real recordElapsed: root.paused ? root.recordMs : root.recordMs + Math.max(0, root.now - root.recordAt)
    readonly property real streamElapsed: root.streamMs + Math.max(0, root.now - root.streamAt)

    Timer {
        id: tick

        onTriggered: root.ticked()
    }

    function ticked(): void {
        root.now = Date.now();
        const running = (root.recording && !root.paused) || root.streaming;
        if (!root.identified || !running) {
            tick.stop();
            return;
        }
        const elapsed = root.recording && !root.paused ? root.recordElapsed : root.streamElapsed;
        tick.interval = 1000 - elapsed % 1000 + 20;
        tick.restart();
    }

    // ---- the connection -------------------------------------------------

    property int port: root.testPort
    property int attempts: 0
    property bool refused: false
    property bool identifying: false

    onOpenChanged: root.opened()
    // Open already as the bar starts or reloads, it emits no change.
    Component.onCompleted: root.opened()

    function opened(): void {
        if (root.open) {
            root.attempts = 0;
            root.refused = false;
            // OBS starts its server a moment after its window shows.
            retry.interval = 1500;
            retry.restart();
        } else if (!root.identified) {
            retry.stop();
        }
    }

    Timer {
        id: retry

        onTriggered: root.connect()
    }

    function connect(): void {
        const socket = socketLoader.item;
        if (!root.open || root.refused || socket === null || socket.active)
            return;
        if (root.port > 0) {
            socket.active = true;
            return;
        }
        if (!portLookup.running)
            portLookup.running = true;
    }

    // The port once per opening of OBS; the default one when OBS says its
    // server is off, so that switching it on is found by the retries alone.
    Process {
        id: portLookup

        command: ["python3", "-I", "-S", Quickshell.shellPath("scripts/obs-auth.py"), "port"]

        stdout: StdioCollector {
            onStreamFinished: {
                const port = parseInt(this.text.trim(), 10);
                root.port = port > 0 && port < 65536 ? port : 4455;
                if (root.open && socketLoader.item !== null)
                    socketLoader.item.active = true;
            }
        }
    }

    Loader {
        id: socketLoader

        active: root.open || root.identified
        source: "ObsSocket.qml"

        onStatusChanged: {
            if (socketLoader.status === Loader.Error)
                console.warn("[obs] no WebSocket module (qt6-websockets); OBS will not show on the island");
        }
    }

    function lost(): void {
        // Closed while it was being told who this is: OBS refused the answer.
        if (root.identifying && !root.identified)
            root.refused = true;
        root.identifying = false;
        root.identified = false;
        root.recording = false;
        root.paused = false;
        root.streaming = false;
        if (socketLoader.item !== null)
            socketLoader.item.active = false;
        root.ticked();
        if (root.open && !root.refused) {
            retry.interval = [2000, 5000, 15000][root.attempts] ?? 60000;
            root.attempts += 1;
            retry.restart();
        }
    }

    function send(op: int, d: var): void {
        socketLoader.item?.send(JSON.stringify({ op: op, d: d }));
    }

    function request(type: string, id: string): void {
        root.send(6, { requestType: type, requestId: id });
    }

    function identify(answer: string): void {
        root.identifying = true;
        // 64: the Outputs events, recording and streaming among them.
        const d = { rpcVersion: 1, eventSubscriptions: 64 };
        if (answer !== "")
            d.authentication = answer;
        root.send(1, d);
    }

    Process {
        id: answerer

        stdout: StdioCollector {
            onStreamFinished: root.identify(this.text.trim())
        }
    }

    // One message from OBS: Hello (0), Identified (2), an Event (5) or the
    // answer to a request (7).
    function receive(text: string): void {
        let msg;
        try {
            msg = JSON.parse(text);
        } catch (e) {
            return;
        }
        const d = msg?.d ?? {};
        if (msg?.op === 0) {
            const auth = d.authentication;
            if (auth && typeof auth.challenge === "string" && typeof auth.salt === "string") {
                answerer.command = ["python3", "-I", "-S", Quickshell.shellPath("scripts/obs-auth.py"),
                                    "answer", auth.challenge, auth.salt];
                answerer.running = true;
            } else {
                root.identify("");
            }
        } else if (msg?.op === 2) {
            root.identifying = false;
            root.identified = true;
            root.attempts = 0;
            root.request("GetRecordStatus", "record");
            root.request("GetStreamStatus", "stream");
        } else if (msg?.op === 5) {
            const data = d.eventData ?? {};
            if (d.eventType === "RecordStateChanged") {
                // Shown at once; the length comes with the status asked for.
                root.recording = data.outputActive === true;
                if (data.outputState === "OBS_WEBSOCKET_OUTPUT_PAUSED")
                    root.paused = true;
                else if (data.outputState === "OBS_WEBSOCKET_OUTPUT_RESUMED" || !root.recording)
                    root.paused = false;
                root.request("GetRecordStatus", "record");
            } else if (d.eventType === "StreamStateChanged") {
                root.streaming = data.outputActive === true;
                root.request("GetStreamStatus", "stream");
            }
            root.ticked();
        } else if (msg?.op === 7 && d.requestStatus?.result === true) {
            const r = d.responseData ?? {};
            if (d.requestId === "record") {
                root.recording = r.outputActive === true;
                root.paused = root.recording && r.outputPaused === true;
                root.recordMs = Number(r.outputDuration) || 0;
                root.recordAt = Date.now();
            } else if (d.requestId === "stream") {
                root.streaming = r.outputActive === true;
                root.streamMs = Number(r.outputDuration) || 0;
                root.streamAt = Date.now();
            }
            root.ticked();
        }
    }

    // ---- what the card asks of it ---------------------------------------

    function togglePause(): void {
        root.request("ToggleRecordPause", "pause");
    }

    function stopRecording(): void {
        root.request("StopRecord", "stop");
    }

    // OBS's window brought forward, or, hidden in its tray, shown from there.
    function show(): void {
        const windows = ToplevelManager.toplevels.values.filter(t => root.isObs(t?.appId));
        if (windows.length > 0) {
            windows[windows.length - 1].activate();
            return;
        }
        SystemTray.items.values.find(i => root.isObs(i?.id))?.activate();
    }
}
