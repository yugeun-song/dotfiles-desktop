import QtQuick
import qs.services

Row {
    id: root

    readonly property var terminal: ["kitty", "-e"]

    spacing: Theme.gap

    Pill {
        visible: InputMethod.present
        icon: Theme.iconKeyboard
        label: InputMethod.label
        fill: InputMethod.hangul ? Theme.accentAmber : Theme.accentQuiet
        tooltip: `Input     ${InputMethod.hangul ? "Hangul" : "Latin"}\nEngine    ${InputMethod.method}\nClick for input method actions`
        menuEntries: [
            {
                label: InputMethod.hangul ? "Switch to Latin" : "Switch to Hangul",
                icon: Theme.iconSwap,
                action: () => InputMethod.toggle()
            },
            {
                separator: true
            },
            {
                label: "Reload configuration",
                icon: Theme.iconRestart,
                detail: "fcitx5-remote -r",
                action: () => InputMethod.reloadConfig()
            },
            {
                label: "Restart fcitx5",
                icon: Theme.iconRestart,
                detail: InputMethod.method,
                action: () => InputMethod.restart()
            },
            {
                label: "Input method settings",
                icon: Theme.iconSettings,
                action: () => InputMethod.configure()
            }
        ]
    }

    Pill {
        visible: CapsLock.active
        icon: Theme.iconCapsLock
        label: "CAPS LOCK"
        fill: Theme.capsLock
        tooltip: "Caps Lock is on"
    }

    Pill {
        visible: Alarms.hasAlarm
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
        onActivated: {
            if (Alarms.ringing)
                Alarms.dismiss();
        }
    }

    Pill {
        visible: Weather.ready
        icon: Theme.weatherIcon(Weather.code, Weather.day)
        label: `${Weather.temp}°`
        fill: Theme.accentSky
        tooltip: `Sky       ${Theme.weatherText(Weather.code)}
Now       ${Weather.temp}°C, feels ${Weather.feels}°C
Today     ${Weather.todayMin}° to ${Weather.todayMax}°C
Humidity  ${Weather.humidity}%
Wind      ${Weather.wind} km/h
Location  ${Weather.place}`
    }

    Pill {
        icon: Net.preferWired ? Theme.iconEthernet : Net.wifiIcon()
        label: {
            if (Net.preferWired)
                return "wired";
            if (!Net.wifiRadioOn)
                return "off";
            if (!Net.wifiConnected)
                return "down";
            return Net.ssid !== "" ? Theme.shorten(Net.ssid, 16) : "on";
        }
        fill: Net.preferWired || Net.wifiConnected ? Theme.accentGreen : Theme.muted
        command: root.terminal.concat(["nmtui"])
        tooltip: {
            const lines = [];
            if (Net.wiredConnected)
                lines.push(`Wired     ${Net.wiredDevice?.name ?? "connected"}`);
            else if (Net.wiredDevice)
                lines.push(`Wired     ${Net.wiredDevice.name} (no link)`);
            else
                lines.push("Wired     no interface");

            if (!Net.wifiRadioOn)
                lines.push("Wi-Fi     radio off");
            else if (!Net.wifiConnected)
                lines.push("Wi-Fi     not connected");
            else
                lines.push(`Wi-Fi     ${Net.ssid !== "" ? Net.ssid : "connected"}   ${Net.signal}%`);

            const addr = Net.preferWired ? Net.wiredDevice?.address : Net.wifiDevice?.address;
            if (addr)
                lines.push(`Address   ${addr}`);
            lines.push("Click to open nmtui");
            return lines.join("\n");
        }
    }

    Pill {
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
        fill: Bt.connectedCount > 0 ? Theme.accentIndigo : Theme.muted
        command: root.terminal.concat(["bluetoothctl"])
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
        visible: Power.present
        iconComponent: BatteryGauge {
            percent: Power.percent
            charging: Power.charging
            strokeColor: Theme.ink
        }
        label: `${Power.percent}%`
        fill: Theme.batteryColor(Power.percent, Power.charging)
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

    Pill {
        icon: Theme.iconCpu
        label: `${Resources.cpuPercent}%`
        fill: Theme.loadColor(Resources.cpuUsage, Theme.accentOrange)
        command: root.terminal.concat(["btop"])
        tooltip: `CPU       ${Resources.cpuPercent}% busy\nSampled   every 1s from /proc/stat\nClick to open btop`
    }

    Pill {
        icon: Theme.iconMemory
        label: `${Resources.memPercent}%`
        fill: Theme.loadColor(Resources.memUsage, Theme.accentPurple)
        command: root.terminal.concat(["btop"])
        tooltip: `Memory    ${Resources.memUsedGb.toFixed(1)} of ${Resources.memTotalGb.toFixed(1)} GB\nIn use    ${Resources.memPercent}%\nSource    MemAvailable in /proc/meminfo\nClick to open btop`
    }
}
