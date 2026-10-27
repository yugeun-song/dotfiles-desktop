import QtQuick
import Quickshell
import qs.services

// The right-hand group: status items, then the clock and, at the outer edge,
// the session button. Identity comes from position and shape; colour appears
// only when a reading wants attention.
//
// No tray here: applications' tray items sit at the left (TrayIcons.qml), and
// fcitx5's state is this group's input method readout.
Row {
    id: root

    readonly property string hyprScripts: Paths.hyprScripts
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

    // How much wider the clock would be at its widest minute today, its
    // figures at the widest's width (tabular): the bar's idle width (Bar.qml)
    // counts it, so the island's most holds still as the minutes turn.
    readonly property real clockSlack: Math.max(0, clockWidest.advanceWidth - clockNow.advanceWidth)

    TextMetrics {
        id: clockNow

        font.family: Theme.uiFont
        font.pixelSize: Theme.statusTextSize
        text: clockItem.label
    }

    TextMetrics {
        id: clockWidest

        font.family: Theme.uiFont
        font.pixelSize: Theme.statusTextSize
        font.features: ({ "tnum": 1 })
        text: Qt.formatDateTime(clock.date, "ddd d MMM  ") + "00:00"
    }

    // "UTC+9" rather than "KST": zone abbreviations are ambiguous, offsets are not.
    function zoneLabel(d) {
        const mins = -d.getTimezoneOffset();
        const sign = mins < 0 ? "-" : "+";
        const h = Math.floor(Math.abs(mins) / 60);
        const m = Math.abs(mins) % 60;
        return "UTC" + sign + h + (m === 0 ? "" : ":" + (m < 10 ? "0" : "") + m);
    }

    // Only while the cameras are off (services/Camera.qml): presence is the
    // reading, like caps lock. Red when the switch is off and a camera is on
    // anyway, amber when a camera stayed off after turning them on.
    // The Mono font fits the glyph to one cell at 118x126 per 200 px, where
    // the bell draws 144x168 and the wifi arcs 156x153 after their boosts;
    // the wifi boost brings it to their size.
    StatusItem {
        visible: Camera.shown
        icon: Theme.iconCameraOff
        iconScale: Theme.statusIconBoostMore
        accent: Camera.state === "leak" ? Theme.accentRed
              : Camera.state === "stuck" ? Theme.accentAmber : Theme.fg
        alert: Camera.state === "leak"
    }

    // Shown only while on, so presence is the reading; no fill.
    StatusItem {
        visible: InputWatch.caps
        unknown: Theme.stale(InputWatch.capsAsOf, 0)
        icon: Theme.iconCapsLock
    }

    // A word rather than a glyph: the word is the reading.
    StatusItem {
        visible: Ime.present
        unknown: Theme.stale(Ime.asOf, 0)
        label: Ime.label
        // Dimmed while the focused window takes no text, like an off radio.
        accent: Ime.idle ? Theme.muted : Theme.fg
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
        // Glyph = an alarm is set, fill = ringing now.
        label: Alarms.ringing ? Theme.shorten(Alarms.ringing.label, 16) : ""
        active: Alarms.ringing
        activeFill: Theme.accentRed
        interactive: Alarms.ringing
        onActivated: {
            if (Alarms.ringing)
                Alarms.dismiss();
        }
    }

    // Network and Bluetooth carry no label: the glyph and dimming say whether
    // there is a connection.
    StatusItem {
        unknown: Net.unknown
        icon: Net.preferWired ? Theme.iconEthernet : Net.wifiIcon()
        iconScale: Theme.statusIconBoostMore
        // Radio off and radio on but unjoined both mean "no network" on the bar;
        // the glyph tells them apart.
        accent: Net.preferWired || Net.wifiConnected ? Theme.fg : Theme.offTone
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "nmtui"])
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
    }

    // The default output, a glyph for its level and its mute, dimmed while
    // muted like a radio that is off. A click mutes or unmutes it as the mute
    // key does, and the island shows the change. Unknown until Pipewire has
    // given the output's state: before that it reads as muted at zero.
    StatusItem {
        unknown: Volume.known ? "" : "Pipewire has not given the output's state"
        icon: Theme.volumeIcon(Volume.percent, Volume.muted)
        // The font fits the speaker to one cell at 118 px per 200, as it
        // does the cameras-off glyph, so it takes the same boost.
        iconScale: Theme.statusIconBoostMore
        accent: Volume.muted ? Theme.offTone : Theme.fg

        interactive: true
        onActivated: Volume.toggleMute()
    }

    // Glyphs before the values, not CPU, RAM and BAT captions: the user's
    // call. 5 s = five missed 1 s samples: a late read does not blink the
    // readout, a wedged /proc still shows promptly.
    StatusItem {
        unknown: Theme.stale(Resources.cpuAsOf, 5000)
        icon: Theme.iconCpu
        // Fitted to 118 px per 200 like the speaker; the same boost.
        iconScale: Theme.statusIconBoostMore
        label: `${Resources.cpuPercent}%`
        labelWidth: Theme.percentWidth
        // One threshold only: a middle band would be lit most of the time on a
        // busy machine, and a colour that is usually on says nothing.
        alert: Resources.cpuUsage >= Theme.loadAlertFraction
        accent: root.alerting(Resources.cpuUsage >= Theme.loadAlertFraction)
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "btop", "htop", "top"])
    }

    StatusItem {
        unknown: Theme.stale(Resources.memAsOf, 5000)
        icon: Theme.iconMemory
        // A DIMM is flat: at the processor's boost it is as wide, and lower.
        iconScale: Theme.statusIconBoostMore
        label: `${Resources.memPercent}%`
        labelWidth: Theme.percentWidth
        alert: Resources.memUsage >= Theme.loadAlertFraction
        accent: root.alerting(Resources.memUsage >= Theme.loadAlertFraction)
        command: root.terminal.concat([root.hyprScripts + "/launch.sh", "btop", "htop", "top"])
    }

    StatusItem {
        // No battery hides the item; an unanswered upower keeps it, marked
        // unknown, so it does not read as a machine without a battery.
        visible: Power.present || Power.unknown !== ""
        unknown: Power.unknown
        // The glyph carries the charging state, and the level while
        // discharging. No boost: unboosted it already stands as tall as the
        // boosted bell (171 and 167 px per 200).
        icon: Theme.batteryIcon(Power.percent, Power.charging)
        label: `${Power.percent}%`
        labelWidth: Theme.percentWidth
        alert: Power.percent <= Theme.batteryLowPercent
        accent: root.alerting(Power.percent <= Theme.batteryLowPercent)
    }

    StatusItem {
        icon: Theme.iconBell
        iconScale: Theme.statusIconBoost
        // Never dimmed or counted: dimming made it look disabled, and toasts
        // already interrupt.
        accent: Theme.fg

        interactive: true
        onActivated: Notifications.toggleCentre()
    }

    // A stale reading stays visible, marked unknown, so the failure reads as
    // the feed's rather than the bar's. 1 h = four missed 15 min polls. A
    // click opens the place panel (WeatherPanel.qml; the user, 2026-10-27);
    // a network up after the bar Weather handles by itself, when a link comes
    // up and the internet answers.
    StatusItem {
        id: weatherItem

        visible: Weather.ready
        unknown: Weather.unknown || Theme.stale(Weather.asOf, 3600000)
        icon: Theme.weatherIcon(Weather.code, Weather.day)
        iconScale: Theme.statusIconBoostWeather
        // The place stays: unlike the machine readouts, the number needs it.
        label: Weather.place !== "" ? `${Weather.place}, ${Weather.temp}°`
                                    : `${Weather.temp}°`
        interactive: true
        held: Weather.panelOpen
        onActivated: Weather.togglePanel(weatherItem.QsWindow.window?.screen ?? null)
    }

    // No glyph.
    StatusItem {
        id: clockItem

        // Day before month, matching hyprlock.
        label: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
        hoverable: true

        CalendarPopup {
            anchorItem: clockItem
            anchorHovered: clockItem.hovered
        }
    }

    // The dialog the power key opens, for the pointer: lock, sign out,
    // sleep, restart, shut down. The outermost item, where a desktop's
    // session menu is looked for.
    StatusItem {
        icon: Theme.iconPower
        iconScale: Theme.statusIconBoost

        interactive: true
        onActivated: Session.toggleMenu()
    }
}
