import QtQuick
import Quickshell
import qs.services

// The right-hand group: status items, clock at the outer edge. Identity comes
// from position and shape; colour appears only when a reading wants attention.
//
// No tray: the only SNI items here are fcitx5 and Spotify, both already on the
// bar. If one is ever needed, see IslandTray.qml in git (ae72a11).
Row {
    id: root

    readonly property string hyprScripts: (Quickshell.env("XDG_CONFIG_HOME") ?? `${Quickshell.env("HOME")}/.config`) + "/hypr/scripts"
    readonly property var terminal: [root.hyprScripts + "/terminal.sh", "-e"]

    // One alert colour for every out-of-range readout (the calendar's Sunday red).
    function alerting(over: bool): color {
        return over ? Theme.accentRed : Theme.fg;
    }

    spacing: Theme.statusItemGap

    // Minute precision: a 1 s Timer would tick 60x per change and drift.
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // "UTC+9" rather than "KST": zone abbreviations are ambiguous, offsets are not.
    function zoneLabel(d) {
        const mins = -d.getTimezoneOffset();
        const sign = mins < 0 ? "-" : "+";
        const h = Math.floor(Math.abs(mins) / 60);
        const m = Math.abs(mins) % 60;
        return "UTC" + sign + h + (m === 0 ? "" : ":" + (m < 10 ? "0" : "") + m);
    }

    StatusItem {
        visible: CapsLock.active
        unknown: Theme.stale(CapsLock.asOf, 0)
        icon: Theme.iconCapsLock
        // Shown only while on, so presence is the reading; no fill.
        tooltip: "Caps Lock is on"
    }

    // A word rather than a glyph: the word is the reading.
    StatusItem {
        visible: Ime.present
        unknown: Theme.stale(Ime.asOf, 0)
        label: Ime.label
        // Dimmed while the focused window takes no text, like an off radio.
        accent: Ime.idle ? Theme.muted : Theme.fg
        tooltip: {
            const lines = [`Input     ${Ime.hangul ? "Hangul" : "Latin"}`];
            lines.push(`Engine    ${Ime.method !== "" ? Ime.method : "none selected"}`);
            // Otherwise the idle state looks like a broken input method.
            if (Ime.idle)
                lines.push("Context   none -- this window takes no text input");
            lines.push("Click for input method actions");
            return lines.join("\n");
        }
        // No language toggle: the menu opens under the pointer, so a double
        // click would silently flip the input method. The Hangul key does that.
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

    StatusItem {
        visible: Alarms.hasAlarm
        unknown: Theme.stale(Alarms.asOf, 0)
        icon: Alarms.ringing ? Theme.iconAlarmRing : Theme.iconAlarm
        // Glyph = an alarm is set, fill = ringing now; countdown is in the tooltip.
        label: Alarms.ringing ? Theme.shorten(Alarms.ringing.label, 16) : ""
        active: Alarms.ringing
        activeFill: Theme.accentRed
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
        interactive: Alarms.ringing
        onActivated: {
            if (Alarms.ringing)
                Alarms.dismiss();
        }
    }

    // Network and Bluetooth carry no label: the glyph and dimming say whether
    // there is a connection; SSID and device names are in the tooltip.
    StatusItem {
        unknown: Net.unknown
        icon: Net.preferWired ? Theme.iconEthernet : Net.wifiIcon()
        iconScale: Theme.statusIconBoostMore
        // Radio off and radio on but unjoined both mean "no network" on the bar;
        // the tooltip tells them apart.
        accent: Net.preferWired || Net.wifiConnected ? Theme.fg : Theme.offTone
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "nmtui"])
        tooltip: {
            const lines = [];
            // Cable-in-but-unconnected and no-cable need different fixes.
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

    StatusItem {
        unknown: Bt.unknown
        icon: Bt.icon()
        // One step below wifi: the Bluetooth mark fills more of its em box.
        iconScale: Theme.statusIconBoost
        accent: Bt.connectedCount > 0 ? Theme.fg : Theme.offTone
        // bluetui first: bluetoothctl opens scoped to the connected device,
        // and the usual reason to open it is some other device.
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

    // 5 s = five missed 1 s samples: a late read does not blink the readout,
    // a wedged /proc still shows promptly.
    StatusItem {
        unknown: Theme.stale(Resources.cpuAsOf, 5000)
        // Caption over value, no glyph: keeps a permanent number narrow.
        caption: "CPU"
        label: `${Resources.cpuPercent}%`
        labelWidth: Theme.percentWidth
        // One threshold only: a middle band would be lit most of the time on a
        // busy machine, and a colour that is usually on says nothing.
        alert: Resources.cpuUsage >= Theme.loadAlertFraction
        accent: root.alerting(Resources.cpuUsage >= Theme.loadAlertFraction)
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "btop", "htop", "top"])
        tooltip: `CPU       ${Resources.cpuPercent}% busy\nSampled   every 1s from /proc/stat\nClick to open btop`
    }

    StatusItem {
        unknown: Theme.stale(Resources.memAsOf, 5000)
        caption: "RAM"
        label: `${Resources.memPercent}%`
        labelWidth: Theme.percentWidth
        alert: Resources.memUsage >= Theme.loadAlertFraction
        accent: root.alerting(Resources.memUsage >= Theme.loadAlertFraction)
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "btop", "htop", "top"])
        tooltip: `Memory    ${Resources.memUsedGb.toFixed(1)} of ${Resources.memTotalGb.toFixed(1)} GB\nIn use    ${Resources.memPercent}%\nSource    MemAvailable in /proc/meminfo\nClick to open btop`
    }

    StatusItem {
        // No battery hides the item; an unanswered upower keeps it, marked
        // unknown, so it does not read as a machine without a battery.
        visible: Power.present || Power.unknown !== ""
        unknown: Power.unknown
        // Caption over value like CPU/RAM; the caption carries the charging state.
        caption: Power.charging ? "CHG" : "BAT"
        label: `${Power.percent}%`
        labelWidth: Theme.percentWidth
        alert: Power.percent <= Theme.batteryLowPercent
        accent: root.alerting(Power.percent <= Theme.batteryLowPercent)
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

    StatusItem {
        icon: Theme.iconBell
        iconScale: Theme.statusIconBoost
        // Never dimmed or counted: dimming made it look disabled, and toasts
        // already interrupt. The unread count is in the tooltip.
        accent: Theme.fg
        tooltip: Notifications.history.length === 0
                 ? "No notifications yet\nClick to open the history"
                 : `Unread    ${Notifications.unread}\nKept      ${Notifications.history.length}\nClick to open the history`

        interactive: true
        onActivated: Notifications.toggleCentre()
    }

    // A stale reading stays visible, marked unknown, so the failure reads as
    // the feed's rather than the bar's. 1 h = four missed 15 min polls.
    StatusItem {
        visible: Weather.ready
        unknown: Weather.unknown || Theme.stale(Weather.asOf, 3600000)
        icon: Theme.weatherIcon(Weather.code, Weather.day)
        iconScale: Theme.statusIconBoostWeather
        // The place stays: unlike the machine readouts, the number needs it.
        label: Weather.place !== "" ? `${Weather.place}, ${Weather.temp}°`
                                    : `${Weather.temp}°`
        tooltip: {
            const lines = [`Sky       ${Theme.weatherText(Weather.code)}`];
            lines.push(Weather.feels > -999
                       ? `Now       ${Weather.temp}°C, feels ${Weather.feels}°C`
                       : `Now       ${Weather.temp}°C`);
            if (Weather.todayMin > -999 && Weather.todayMax > -999)
                lines.push(`Today     ${Weather.todayMin}° to ${Weather.todayMax}°C`);
            if (Weather.humidity >= 0)
                lines.push(`Humidity  ${Weather.humidity}%`);
            if (Weather.wind >= 0)
                lines.push(`Wind      ${Weather.wind} km/h`);
            if (Weather.place !== "")
                lines.push(`Location  ${Weather.place}`);
            return lines.join("\n");
        }
    }

    // Outer edge, no glyph.
    StatusItem {
        id: clockItem

        // Day before month, matching hyprlock.
        label: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
        // No tooltip: hovering opens the month.
        tooltip: ""

        CalendarPopup {
            anchorItem: clockItem
            anchorHovered: clockItem.hovered
        }
    }
}
