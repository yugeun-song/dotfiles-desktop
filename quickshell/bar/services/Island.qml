pragma Singleton

import QtQuick
import Quickshell
import qs.services

// The system's events on the island (MediaChip.qml, IslandEvent.qml), as the
// user asked (2026-10-26): volume and brightness, in place of an OSD, and
// what changes by itself (power, Bluetooth).
//
// One event at a time, on the screen in use only, leaving the others alone:
//   readouts (volume, brightness) answer a key: shown at once over anything,
//     until Theme.islandReadoutMs after the last change;
//   alerts (power, Bluetooth) come unasked: they wait while a readout is up,
//     come back after one that came over them while time is left, and a
//     newer one replaces an older one;
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

    Component.onCompleted: {
        root.powerSettle();
        root.btSettle();
    }
}
