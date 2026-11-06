pragma Singleton

import QtQuick
import Quickshell
import qs.services

// The system's events on the island (MediaChip.qml, IslandEvent.qml), as the
// user asked (2026-10-26): volume and brightness, in place of an OSD, and
// what changes by itself (power, Bluetooth, and since 2026-11-02 wired
// audio outputs plugged in and pulled out).
//
// One event at a time, on the screen in use only, leaving the others alone:
//   readouts (volume, brightness) answer a key: shown at once over anything,
//     until Theme.islandReadoutMs after the last change;
//   alerts (power, Bluetooth, outputs) come unasked: they wait while a
//     readout is up, come back after one that came over them while time is
//     left, and a newer one replaces an older one;
//   what goes on (what plays, a call, OBS, a share) is MediaChip's own and
//     comes back once the event has gone.
// The fields are plain properties set together by show(): a held key
// changes them many times a second, with nothing allocated.
Singleton {
    id: root

    // The event shown; kind "" when there is none.
    property string kind: ""
    property string glyph: ""
    property string text: ""
    property string value: ""
    // 0 to 1 for a level's bar or a battery's cell, -1 for none.
    property real level: -1
    property real battery: -1
    property color tone: Theme.islandText
    // The screen it is shown on, by name.
    property string screen: ""
    property bool readout: false

    // An alert that came while a readout was up, or that one came over;
    // rare, so an object. When the alert shown began.
    property var waiting: null
    property real shownAt: 0

    function show(kind, glyph, text, value, level, battery, tone, isReadout, since): void {
        if (isReadout && root.kind !== "" && !root.readout)
            root.waiting = { kind: root.kind, glyph: root.glyph, text: root.text, value: root.value,
                             battery: root.battery, tone: root.tone, at: root.shownAt };
        root.screen = Screens.focused?.name ?? "";
        root.glyph = glyph;
        root.text = text;
        root.value = value;
        root.level = level;
        root.battery = battery;
        root.tone = tone;
        root.readout = isReadout;
        // Last, so that what reads the kind finds the rest set.
        root.kind = kind;
        if (!isReadout)
            root.shownAt = since ?? Date.now();
        hold.interval = isReadout ? Theme.islandReadoutMs
                                  : Math.max(300, Theme.islandAlertMs - (Date.now() - root.shownAt));
        hold.restart();
    }

    function alert(kind, glyph, text, value, battery, tone): void {
        if (root.quiet)
            return;
        if (root.readout && hold.running) {
            root.waiting = { kind, glyph, text, value, battery, tone, at: Date.now() };
            return;
        }
        root.show(kind, glyph, text, value, -1, battery, tone, false);
    }

    Timer {
        id: hold

        onTriggered: {
            const next = root.waiting;
            root.waiting = null;
            if (next !== null && Date.now() - next.at < Theme.islandAlertMs) {
                root.show(next.kind, next.glyph, next.text, next.value, -1, next.battery, next.tone, false, next.at);
                return;
            }
            root.kind = "";
            root.readout = false;
        }
    }

    // What is found as the bar starts or reloads is the state, not news.
    property bool quiet: true

    Timer {
        interval: 4000
        running: true
        onTriggered: root.quiet = false
    }

    // Readouts, called by shell.qml on the services' changes rather than the
    // keys', so outside changes show too; Volume and Brightness tell nothing
    // of their first value. Connected there so that this alone does not bring
    // PipeWire up (the unit tests have none).
    // Muted, the level still shows, in red: the keys change it under the
    // mute, and the user sets it there (2026-10-26).
    function volumeChanged(): void {
        root.show("volume", Theme.volumeIcon(Volume.percent, Volume.muted),
                  Volume.muted ? "Muted" : "Volume", `${Volume.percent}`,
                  Volume.percent / 100, -1,
                  Volume.muted ? Theme.islandRed : Theme.islandBlue, true);
    }

    function brightnessChanged(): void {
        root.show("brightness", Theme.iconBrightness, "Brightness", `${Brightness.percent}`,
                  Brightness.percent / 100, -1, Theme.islandYellow, true);
    }

    // Power: the cord in and out (both, as the user asked, 2026-10-26), the
    // cell full, the cell low. Several flags change at once, so they are read
    // once settled.
    property var powerWas: null

    Connections {
        target: Power

        function onChargingChanged(): void {
            Qt.callLater(root.powerSettle);
        }
        function onFullChanged(): void {
            Qt.callLater(root.powerSettle);
        }
        function onOnBatteryChanged(): void {
            Qt.callLater(root.powerSettle);
        }
        function onPercentChanged(): void {
            Qt.callLater(root.powerSettle);
        }
    }

    function powerSettle(): void {
        if (!Power.present || Power.percent < 0)
            return;
        const step = root.powerStep(root.powerWas, { charging: Power.charging, full: Power.full,
                                                     onBattery: Power.onBattery, percent: Power.percent });
        root.powerWas = step.state;
        const a = step.alert;
        if (a !== null)
            root.alert("power", a.glyph, a.text, a.value, a.battery, a.tone);
    }

    // What one settled change of the power says, from the state before; none
    // from the first, which is the state found rather than news.
    function powerStep(was: var, now: var): var {
        const low = !now.charging && now.percent <= Theme.batteryLowPercent;
        const state = { charging: now.charging, full: now.full, onBattery: now.onBattery, low: low };
        if (was === null)
            return { state: state, alert: null };
        const told = (glyph, text, tone) => ({ glyph: glyph, text: text, value: `${now.percent}%`,
                                               battery: now.percent / 100, tone: tone });
        let alert = null;
        if (now.charging && !was.charging)
            alert = told(Theme.iconBolt, "Charging", Theme.islandGreen);
        else if (now.full && !was.full && !now.onBattery)
            alert = told(Theme.iconBolt, "Fully charged", Theme.islandGreen);
        else if (now.onBattery && !was.onBattery)
            alert = told(Theme.batteryIcon(now.percent, false), "Unplugged", Theme.islandText);
        else if (low && !was.low)
            alert = told(Theme.iconBatteryAlert, "Low battery", Theme.islandRed);
        return { state: state, alert: alert };
    }

    // Bluetooth: a device connected or gone, by its address, both ways as
    // the power's; its battery when it tells one.
    property var btSeen: null

    Connections {
        target: Bt

        function onConnectedDevicesChanged(): void {
            Qt.callLater(root.btSettle);
        }
    }

    function btSettle(): void {
        const devices = Bt.connectedDevices.map(d => ({
            address: d.address,
            name: d.deviceName || d.name || d.address,
            battery: d.batteryAvailable ? d.battery : -1
        }));
        const step = root.btStep(root.btSeen, devices);
        root.btSeen = step.state;
        for (const a of step.alerts)
            root.alert("bluetooth", a.glyph, a.text, a.value, a.battery, a.tone);
    }

    // The devices come and gone since the last look, as { address: name }
    // before and after; none told from the first look.
    function btStep(was: var, devices: var): var {
        const state = {};
        for (const d of devices)
            state[d.address] = d.name;
        const alerts = [];
        if (was !== null) {
            for (const d of devices) {
                if (!(d.address in was))
                    alerts.push({ glyph: Theme.iconBtLinked, text: d.name,
                                  value: d.battery >= 0 ? `${Math.round(d.battery * 100)}%` : "Connected",
                                  battery: d.battery, tone: Theme.islandBlue });
            }
            for (const address in was) {
                if (!(address in state))
                    alerts.push({ glyph: Theme.iconBtOff, text: was[address], value: "Disconnected",
                                  battery: -1, tone: Theme.islandSubtext });
            }
        }
        return { state: state, alerts: alerts };
    }

    // Wired audio outputs, from AudioDevices.qml's snapshots, which
    // shell.qml hands over so that this file brings no PipeWire up.
    property var outputsSeen: null

    function outputsSettle(state: var): void {
        const step = root.outputsStep(root.outputsSeen, state);
        root.outputsSeen = step.state;
        for (const a of step.alerts)
            root.alert("output", a.glyph, a.text, a.value, a.battery, a.tone);
    }

    // What one view says against the one before; nothing from the first,
    // the state found. A USB device with an output is there or not, by its
    // card, so a change of profile tells nothing. The jack's sense never
    // reaches the bar: AudioPolicy.qml reads it off the default and hands
    // its verdict over (jack: "plugged", "pulled" or ""), the same one that
    // pauses the players. Gone before come, as a newer alert replaces an
    // older one: unplugged and plugged in within one settle reads as
    // plugged in.
    function outputsStep(was: var, now: var): var {
        const alerts = [];
        if (was === null)
            return { state: now, alerts: alerts };
        const told = (label, plugged) => ({
            glyph: plugged ? Theme.iconHeadphones : Theme.iconHeadphonesOff,
            text: label,
            value: plugged ? "Connected" : "Disconnected",
            battery: -1,
            tone: plugged ? Theme.islandBlue : Theme.islandSubtext
        });
        for (const key in was.outs) {
            if (!(key in now.outs))
                alerts.push(told(was.outs[key].label, false));
        }
        if (now.jack === "pulled")
            alerts.push(told(now.jackLabel, false));
        for (const key in now.outs) {
            if (!(key in was.outs))
                alerts.push(told(now.outs[key].label, true));
        }
        if (now.jack === "plugged")
            alerts.push(told(now.jackLabel, true));
        return { state: now, alerts: alerts };
    }

    // The lock screen's island (hypr/hyprlock.conf, LockIsland.qml) holds
    // the event as a phone's narrow pill does, as the user asked
    // (2026-11-02): one mark at each end and nothing between, the island no
    // larger, never two events at once. Leading, the event's glyph in its
    // colour, or the lock when there is none; trailing, a number (a level,
    // or a percentage) or, for a device come or gone, a tick or a cross.
    // hyprlock places a label by its middle, so a number is always one
    // width: tabular figures, figure spaces before short ones, and for a
    // level a transparent "%" in front, so that it ends at the island's
    // right end whatever its digits. Pango markup for hyprlock's three
    // labels; nothing a device names reaches it, only glyphs, digits and
    // the two marks.
    function lockCompact(kind: string, glyph: string, value: string, tone: color): var {
        if (kind === "")
            return { lead: Theme.iconLock, trail: "", mark: "" };
        const hex = root.hexOf(tone);
        const lead = `<span foreground="${hex}">${root.escaped(glyph)}</span>`;
        const number = /^(\d{1,3})(%?)$/.exec(value);
        if (number !== null) {
            const pad = " ".repeat(3 - number[1].length);
            const trail = number[2] === "%"
                ? `<span font_features="tnum" foreground="${hex}">${pad}${number[1]}%</span>`
                : `<span font_features="tnum"><span alpha="1">%</span><span foreground="${hex}">${pad}${number[1]}</span></span>`;
            return { lead: lead, trail: trail, mark: "" };
        }
        const mark = value === "Connected" ? Theme.iconCheckCircle
                   : value === "Disconnected" ? Theme.iconCloseCircle : "";
        return { lead: lead, trail: "", mark: mark === "" ? "" : `<span foreground="${hex}">${mark}</span>` };
    }

    // The same in parts, for the Quickshell lock screen (lock.qml), which
    // draws them itself: the leading glyph (the lock between events), the
    // trailing number with its sign, or the device's mark, and the tone.
    function lockParts(kind: string, glyph: string, value: string, tone: color): var {
        if (kind === "")
            return { lead: Theme.iconLock, trail: "", mark: "", tone: "" };
        const number = /^(\d{1,3})(%?)$/.exec(value);
        const mark = value === "Connected" ? Theme.iconCheckCircle
                   : value === "Disconnected" ? Theme.iconCloseCircle : "";
        return { lead: glyph, trail: number !== null ? `${number[1]}${number[2]}` : "",
                 mark: number !== null ? "" : mark, tone: root.hexOf(tone) };
    }

    function hexOf(c: color): string {
        const part = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return `#${part(c.r)}${part(c.g)}${part(c.b)}`;
    }

    function escaped(text: string): string {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    Component.onCompleted: {
        root.powerSettle();
        root.btSettle();
    }
}
