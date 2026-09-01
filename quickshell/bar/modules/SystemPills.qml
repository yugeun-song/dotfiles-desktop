import QtQuick
import Quickshell
import qs.services

Row {
    id: root

    // The same entry points the key bindings use. Naming a binary here would
    // mean every pill that opens something fails silently on a machine with a
    // different terminal, and these scripts already answer that question once.
    readonly property string hyprScripts: (Quickshell.env("XDG_CONFIG_HOME") ?? `${Quickshell.env("HOME")}/.config`) + "/hypr/scripts"
    readonly property var terminal: [root.hyprScripts + "/terminal.sh", "-e"]

    spacing: Theme.gap

    Pill {
        visible: CapsLock.active
        unknown: Theme.stale(CapsLock.asOf, 0)
        icon: Theme.iconCapsLock
        label: "CAPS LOCK"
        fill: Theme.capsLock
        tooltip: "Caps Lock is on"
    }

    Pill {
        visible: Ime.present
        unknown: Theme.stale(Ime.asOf, 0)
        icon: Theme.iconKeyboard
        label: Ime.label
        fill: Ime.hangul ? Theme.accentSaffron : Theme.accentQuiet
        tooltip: `Input     ${Ime.hangul ? "Hangul" : "Latin"}\nEngine    ${Ime.method}\nClick for input method actions`
        // No language toggle here on purpose. The menu opens directly under
        // the pointer, so the next click lands on the first entry: clicking
        // the pill twice would silently flip the input method. The Hangul key
        // does that job, and a menu is the wrong place for something with a
        // dedicated key.
        menuEntries: [
            {
                label: "Reload configuration",
                icon: Theme.iconRestart,
                detail: "fcitx5-remote -r",
                action: () => Ime.reloadConfig()
            },
            {
                label: "Restart fcitx5",
                icon: Theme.iconRestart,
                detail: Ime.method,
                action: () => Ime.restart()
            },
            {
                label: "Input method settings",
                icon: Theme.iconSettings,
                action: () => Ime.configure()
            }
        ]
    }

    Pill {
        visible: Alarms.hasAlarm
        unknown: Theme.stale(Alarms.asOf, 0)
        icon: Alarms.ringing ? Theme.iconAlarmRing : Theme.iconAlarm
        label: Alarms.ringing ? Theme.shorten(Alarms.ringing.label, 16) : Alarms.countdown
        fill: Alarms.ringing ? Theme.accentRed : Theme.accentQuiet
        tooltip: {
            if (Alarms.ringing)
                return `Ringing   ${Alarms.ringing.label}\nSet for   ${Alarms.ringing.at} ${Alarms.timezone}\nClick to dismiss`;
            const lines = [];
            for (const a of Alarms.pending.slice(0, 6))
                lines.push(`  ${a.at}  ${a.daily ? "daily" : "once "}  ${Theme.shorten(a.label, 24)}`);
            if (Alarms.pending.length > 6)
                lines.push(`  and ${Alarms.pending.length - 6} more`);
            return [
                `${Alarms.pending.length} alarm${Alarms.pending.length === 1 ? "" : "s"}, next in ${Alarms.countdown}`,
                ...lines,
                `Times are ${Alarms.timezone}`,
                "Managed with scripts/alarm.sh"
            ].join("\n");
        }
        // Only a ringing alarm can be dismissed, so only then is it clickable.
        interactive: Alarms.ringing
        onActivated: {
            if (Alarms.ringing)
                Alarms.dismiss();
        }
    }

    Pill {
        unknown: Net.unknown
        icon: Net.preferWired ? Theme.iconEthernet : Net.wifiIcon()
        label: {
            if (Net.preferWired)
                return "wired";
            if (!Net.wifiDevice)
                return "none";
            if (!Net.wifiRadioOn)
                return "off";
            if (!Net.wifiConnected)
                return "down";
            return Net.ssid !== "" ? Theme.shorten(Net.ssid, 16) : "on";
        }
        fill: Net.preferWired || Net.wifiConnected ? Theme.accentJade : Theme.muted
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "nmtui"])
        tooltip: {
            const lines = [];
            // A port with a cable in it carrying no connection and a port with
            // nothing plugged in used to read the same "(no link)". They ask
            // for different things: one wants a profile or a working switch,
            // the other wants a cable.
            if (Net.wiredConnected)
                lines.push(`Wired     ${Net.wiredDevice?.name ?? "connected"}`);
            else if (Net.wiredDevice)
                lines.push(`Wired     ${Net.wiredDevice.name} (${Net.wiredHasLink ? "cable in, not connected" : "no cable"})`);
            else
                lines.push("Wired     no interface");

            if (!Net.wifiDevice)
                lines.push("Wi-Fi     no interface");
            else if (!Net.wifiRadioOn)
                lines.push("Wi-Fi     radio off");
            else if (!Net.wifiConnected)
                lines.push("Wi-Fi     not connected");
            else
                lines.push(`Wi-Fi     ${Net.ssid !== "" ? Net.ssid : "connected"}   ${Net.signal >= 0 ? Net.signal + "%" : "strength unknown"}`);

            const addr = Net.preferWired ? Net.wiredDevice?.address : Net.wifiDevice?.address;
            if (addr)
                lines.push(`Address   ${addr}`);
            lines.push("Click to open nmtui");
            return lines.join("\n");
        }
    }

    Pill {
        unknown: Bt.unknown
        icon: Bt.icon()
        label: {
            if (!Bt.present)
                return "none";
            if (!Bt.enabled)
                return "off";
            if (Bt.connectedCount === 0)
                return "on";
            return Bt.connectedCount === 1 ? Theme.shorten(Bt.firstName, 14) : `${Bt.connectedCount} devices`;
        }
        fill: Bt.connectedCount > 0 ? Theme.accentAzure : Theme.muted
        // Not bluetoothctl directly. It puts the connected device in its
        // prompt and points argument-less commands at it, so it opens scoped
        // to whatever is already paired, which is the wrong place to start
        // when the reason for opening it is usually some other machine.
        // bluetui opens on the adapter, with the device list, scanning and
        // pairing all in reach.
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "bluetui", "bluetoothctl"])
        tooltip: {
            if (!Bt.present)
                return "No Bluetooth adapter";
            const lines = [`Adapter   ${Bt.adapter?.name ?? "unknown"}`, `Radio     ${Bt.enabled ? "on" : "off"}`];
            if (Bt.connectedDevices.length > 0) {
                lines.push(`Connected ${Bt.connectedCount}`);
                for (const d of Bt.connectedDevices) {
                    const battery = d.batteryAvailable ? `   ${Math.round(d.battery * 100)}%` : "";
                    lines.push(`  ${Theme.shorten(d.deviceName ?? d.name ?? d.address, 26)}${battery}`);
                }
            } else {
                lines.push("Connected none");
            }
            const idle = Bt.pairedDevices.filter(d => !d.connected);
            if (idle.length > 0) {
                lines.push(`Paired    ${idle.length} not connected`);
                for (const d of idle.slice(0, 4))
                    lines.push(`  ${Theme.shorten(d.deviceName ?? d.name ?? d.address, 26)}`);
            }
            lines.push("Click to open bluetoothctl");
            return lines.join("\n");
        }
    }

    Pill {
        // Two different absences. No battery at all -- a desktop, or a cell
        // pulled out -- is a reading, and the pill leaves on it. A battery
        // upower has not answered for is not, and there the pill holds its
        // place and says so, because a readout that vanishes instead reads as
        // a machine that never had a battery.
        visible: Power.present || Power.unknown !== ""
        unknown: Power.unknown
        iconComponent: BatteryGauge {
            percent: Power.percent
            charging: Power.charging
            strokeColor: Theme.ink
        }
        label: `${Power.percent}%`
        labelWidth: Theme.percentWidth
        fill: Theme.batteryColor(Power.percent)
        tooltip: {
            const lines = [`Charge    ${Power.percent}%`, `State     ${Power.stateLabel()}`];
            const remaining = Power.charging ? Power.humanTime(Power.secondsToFull) : Power.humanTime(Power.secondsToEmpty);
            if (remaining !== "")
                lines.push(Power.charging ? `Until full  ${remaining}` : `Remaining ${remaining}`);
            if (Power.energyFull > 0)
                lines.push(`Capacity  ${Power.energyNow.toFixed(1)} of ${Power.energyFull.toFixed(1)} Wh`);
            if (Power.rate > 0)
                lines.push(`Draw      ${Power.rate.toFixed(1)} W`);
            if (Power.healthKnown)
                lines.push(`Health    ${Power.health}% of design`);
            return lines.join("\n");
        }
    }

    // Five consecutive misses of the 1s sample, for both pills below. Long
    // enough that one late read does not blink them, short enough that a
    // wedged /proc is on screen while it is still the thing that just happened.
    Pill {
        unknown: Theme.stale(Resources.cpuAsOf, 5000)
        icon: Theme.iconCpu
        labelPrefix: "CPU:"
        label: `${Resources.cpuPercent}%`
        labelWidth: Theme.percentWidth
        fill: Theme.loadColor(Resources.cpuUsage, Theme.accentOrange)
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "btop", "htop", "top"])
        tooltip: `CPU       ${Resources.cpuPercent}% busy\nSampled   every 1s from /proc/stat\nClick to open btop`
    }

    Pill {
        unknown: Theme.stale(Resources.memAsOf, 5000)
        icon: Theme.iconMemory
        labelPrefix: "RAM:"
        label: `${Resources.memPercent}%`
        labelWidth: Theme.percentWidth
        fill: Theme.loadColor(Resources.memUsage, Theme.accentViolet)
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "btop", "htop", "top"])
        tooltip: `Memory    ${Resources.memUsedGb.toFixed(1)} of ${Resources.memTotalGb.toFixed(1)} GB\nIn use    ${Resources.memPercent}%\nSource    MemAvailable in /proc/meminfo\nClick to open btop`
    }
    // Deliberately last, so it sits at the outer right edge of the bar.
    Pill {
        icon: Theme.iconBell
        label: Notifications.unread > 0 ? `${Notifications.unread}` : ""
        labelWidth: Notifications.unread > 0 ? Theme.countWidth : 0
        fill: Notifications.unread > 0 ? Theme.accentRose : Theme.muted
        tooltip: Notifications.history.length === 0
                 ? "No notifications yet\nClick to open the history"
                 : `Unread    ${Notifications.unread}\nKept      ${Notifications.history.length}\nClick to open the history`

        interactive: true
        onActivated: Notifications.toggleCentre()
    }

}
