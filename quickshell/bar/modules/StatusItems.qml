import QtQuick
import Quickshell
import qs.services

// The right-hand group: the status menus, and the clock at the outer edge.
//
// This was SystemPills, eight coloured chips. Colour was doing two jobs there
// -- telling one pill from the next, and saying a reading had left its range
// -- and the first made the second illegible. Here identity comes from
// position and shape, and an accent appears only when something wants
// attention, so every fill that survived is conditional.
//
// The clock and weather moved here from the left end, which on a menu bar
// belongs to the application.
//
// No tray. There was one, briefly, on the argument that in a menu bar the
// status group IS the tray. That is true in general and was wrong here: this
// machine registers exactly two items, fcitx5 and Spotify, and the bar already
// carries both -- the input method as the item below, and the player in the
// island, with transport controls a tray icon does not have. Two icons that
// duplicate what is beside them, one of which does not even answer a click.
// Restore modules/TrayItems.qml from git if an application ever turns up that
// has no other way to be reached.
Row {
    id: root

    readonly property string hyprScripts: (Quickshell.env("XDG_CONFIG_HOME") ?? `${Quickshell.env("HOME")}/.config`) + "/hypr/scripts"
    readonly property var terminal: [root.hyprScripts + "/terminal.sh", "-e"]

    // One colour for every reading that has left its range, and it is the one
    // the calendar marks Sunday with. Written once so the three readouts
    // cannot drift apart.
    function alerting(over: bool): color {
        return over ? Theme.accentRed : Theme.fg;
    }

    spacing: Theme.statusItemGap

    // Wakes on the minute rather than on a free-running interval, for the
    // reason it always did: a 1000 ms Timer ticks sixty times per visible
    // change and drifts off the minute boundary as it goes.
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // "UTC+9" rather than "KST": an abbreviation has to be recognised before
    // it says anything and several are ambiguous across regions, where an
    // offset is the same number everywhere. It is in the tooltip rather than
    // on the bar now, because a menu bar clock is a time and not a dossier.
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
        // The glyph alone. It is only ever drawn while caps lock is on, so its
        // presence is the whole reading and a colour behind it adds nothing.
        tooltip: "Caps Lock is on"
    }

    // The one status item that keeps a word rather than a glyph, because the
    // word is the reading: which script the next keystroke composes in.
    StatusItem {
        visible: Ime.present
        unknown: Theme.stale(Ime.asOf, 0)
        // The word is the whole readout. It was a filled pill in Hangul for a
        // while, on the microphone analogy; an input method is not a thing
        // that is switched on, it is a thing that is set to one of two values,
        // and both values are already written out.
        label: Ime.label
        // Dimmed while nothing focused takes text, on the same rule as the two
        // radios beside it: a thing that is off is drawn darker than a thing
        // that is on and idle.
        accent: Ime.idle ? Theme.muted : Theme.fg
        tooltip: {
            const lines = [`Input     ${Ime.hangul ? "Hangul" : "Latin"}`];
            lines.push(`Engine    ${Ime.method !== "" ? Ime.method : "none selected"}`);
            // The line that answers the question this state raises. It looked
            // like a broken input method and it is a window that takes no
            // text.
            if (Ime.idle)
                lines.push("Context   none -- this window takes no text input");
            lines.push("Click for input method actions");
            return lines.join("\n");
        }
        // No language toggle in the menu, still. The menu opens under the
        // pointer, so the next click lands on the first entry and clicking
        // twice would silently flip the input method. The Hangul key does
        // that job and a menu is the wrong place for something with a key.
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
        // The countdown is in the tooltip. On the bar the glyph says an alarm
        // is set, and the fill says one is going off now.
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

    // Network and Bluetooth lose their labels. The SSID and the device name
    // were the widest things on the old bar and both are one hover away; what
    // the glyph has to carry is whether there is a connection, which the
    // signal-strength icon and the dimming already say.
    StatusItem {
        unknown: Net.unknown
        icon: Net.preferWired ? Theme.iconEthernet : Net.wifiIcon()
        iconScale: Theme.statusIconBoostMore
        accent: Net.preferWired || Net.wifiConnected ? Theme.fg : Theme.muted
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "nmtui"])
        tooltip: {
            const lines = [];
            // A port with a cable carrying no connection and a port with
            // nothing plugged in ask for different things: one wants a profile
            // or a working switch, the other wants a cable.
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
        // One step below the wifi arcs beside it. The Bluetooth mark fills
        // more of its em box than they fill theirs, so the same factor made it
        // the largest glyph in the group.
        iconScale: Theme.statusIconBoost
        accent: Bt.connectedCount > 0 ? Theme.fg : Theme.muted
        // Not bluetoothctl directly: it puts the connected device in its
        // prompt and points argument-less commands at it, so it opens scoped
        // to whatever is already paired, which is the wrong place to start
        // when the reason for opening it is usually some other machine.
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

    // The load readouts keep their numbers and lose their prefixes. "CPU:" and
    // "RAM:" were disambiguating two pills that looked alike; the glyphs
    // already differ in silhouette -- a die with legs against a DIMM -- and
    // that is what the two were chosen for.
    //
    // Five consecutive misses of the 1 s sample marks either one unread: long
    // enough that a late read does not blink it, short enough that a wedged
    // /proc is on screen while it is still the thing that just happened.
    StatusItem {
        unknown: Theme.stale(Resources.cpuAsOf, 5000)
        // Caption over value, no glyph: the reference draws its load readouts
        // this way, and it is the form that lets a number stay on the bar
        // permanently without taking a word's worth of room.
        caption: "CPU"
        label: `${Resources.cpuPercent}%`
        labelWidth: Theme.percentWidth
        // One threshold, not two. A middle band in orange meant the readouts
        // were coloured most of the time on a machine that is usually busy,
        // and a colour that is usually on says nothing. Red at the ceiling
        // only, and the same red the calendar marks Sunday with, so the shell
        // has one colour for "look at this" rather than one per widget.
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
        // Two different absences. No battery at all -- a desktop, a cell pulled
        // out -- is a reading and the item leaves on it. A battery upower has
        // not answered for is not, and there it holds its place and says so:
        // a readout that vanishes instead reads as a machine that never had one.
        visible: Power.present || Power.unknown !== ""
        unknown: Power.unknown
        // A word, like the two readouts before it, rather than a drawn gauge.
        // The gauge said the level twice -- once as a fill and once as the
        // number beside it -- and the three readouts now read as one group
        // instead of two words and a picture.
        //
        // Charging is the caption's job: it is the one battery state that is
        // not a level, and spelling it changes nothing else about the item.
        caption: Power.charging ? "CHG" : "BAT"
        label: `${Power.percent}%`
        labelWidth: Theme.percentWidth
        // Red under the low mark and nothing otherwise. Charging was green for
        // a while, which spent a colour on a state the caption already spells.
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
        // No count and no state in the colour. The bell is a door to the
        // history, and a door is there whether or not anything came through
        // it; dimming it when the list was read made it look disabled. The
        // toast already interrupted if there was anything worth interrupting
        // for, and the count is in the tooltip.
        accent: Theme.fg
        tooltip: Notifications.history.length === 0
                 ? "No notifications yet\nClick to open the history"
                 : `Unread    ${Notifications.unread}\nKept      ${Notifications.history.length}\nClick to open the history`

        interactive: true
        onActivated: Notifications.toggleCentre()
    }

    // The weather keeps its place rather than leaving when a reading is old:
    // an item that disappears reads as a change to the bar, one that says it
    // has no reading reads as a change to the feed, which is what happened.
    // An hour against a fifteen-minute poll is four consecutive misses.
    StatusItem {
        visible: Weather.ready
        unknown: Weather.unknown || Theme.stale(Weather.asOf, 3600000)
        icon: Theme.weatherIcon(Weather.code, Weather.day)
        iconScale: Theme.statusIconBoostWeather
        // Sky, place and temperature, which is what this readout has always
        // said. It was cut to the glyph alone for a while on the argument that
        // a menu bar carries no words; the place is the part that makes the
        // number mean something, and everything else here is a machine reading
        // where this one is not.
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

    // Last, at the outer edge, which is where a menu bar's clock is. No glyph:
    // it is the only item here that needs no saying what it is.
    StatusItem {
        id: clockItem

        // Weekday, day, month, time -- the order a menu bar uses. Day before
        // month, which is what hyprlock already does, so the two never
        // disagree about which number is which.
        label: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
        // No tooltip. Hovering opens the month instead, which answers every
        // question the tooltip did and several it could not.
        tooltip: ""

        CalendarPopup {
            anchorItem: clockItem
            anchorHovered: clockItem.hovered
        }
    }
}
