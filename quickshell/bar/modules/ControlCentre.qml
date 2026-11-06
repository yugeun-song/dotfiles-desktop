pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.services

// The control centre, opened by the power button at the bar's right end (the
// user, 2026-11-04, after GNOME's quick settings): what is changed often and
// quickly, nothing else. At the top the battery and four round buttons (a
// capture, the display panel, the lock, and the session dialog the power key
// opens); under them the sound, with its output, and the brightness; then
// the toggles two to a row, Wi-Fi, Bluetooth, the microphone, the cameras
// and the power mode, a section opening in place under its row as GNOME's
// menus do.
//
// Only the shell's face: every switch is a service the bar already reads
// (Net, Bt, Volume, AudioDevices, Brightness, Camera) or quickshell's own
// object, and nothing here changes how they work. What is rare or asks for
// a secret goes to a program's window, never into the shell (the user,
// 2026-11-04: windows, not terminals): KDE's network and Bluetooth settings
// and pavucontrol-qt, installed already and drawn in the Qt palette, with
// the terminal programs as the last resort; a new network's password is
// asked by NetworkManager's agent, KDE's, in its own window.
//
// A modal, as the user asked: it holds the keys, and Esc or a click beside
// the panel closes it at once, an open section with it, and so does a lock.
// The screen stays clear: only the session dialog dims (the user, 2026-11-04). It
// stands in the column of the toasts and the notification panel, and one
// transient panel shows at a time (services/Surfaces.qml).
Scope {
    id: root

    // shell.qml opens the Displays panel and the wallpaper picker, siblings
    // this module cannot reach.
    signal displaysAsked
    signal wallpaperAsked

    // tests/e2e reads the panel's buttons through this.
    readonly property var window: loader.item

    readonly property string hyprScripts: Paths.hyprScripts
    // The first installed of each (launch.sh): a window first, kcmshell6 for
    // the one settings page alone, the terminal programs the bar's own items
    // open last.
    readonly property var wifiTool: [root.hyprScripts + "/launch.sh",
        "kcmshell6 kcm_networkmanagement", "systemsettings kcm_networkmanagement", "nm-connection-editor",
        root.hyprScripts + "/terminal.sh -e nmtui"]
    readonly property var bluetoothTool: [root.hyprScripts + "/launch.sh",
        "kcmshell6 kcm_bluetooth", "systemsettings kcm_bluetooth", "blueman-manager",
        root.hyprScripts + "/terminal.sh -e bluetui"]
    readonly property var mixerTool: [root.hyprScripts + "/launch.sh", "pavucontrol-qt", "pavucontrol"]

    // A network picked that needs a password: the prompt is NetworkManager's
    // agent's (KDE's, in kded6), in a window of its own. Where none answers
    // (kded6 starts with the first KDE program, not at login) NetworkManager
    // reports NoSecrets and the network settings take it from there; a
    // prompt cancelled reads the same, and that window is where a password
    // is typed anyway.
    property var asked: null

    Connections {
        target: root.asked

        function onConnectionFailed(reason) {
            const noSecrets = reason === ConnectionFailReason.NoSecrets;
            root.asked = null;
            if (noSecrets)
                Apps.open(root.wifiTool);
        }

        function onConnectedChanged() {
            if (root.asked?.connected)
                root.asked = null;
        }
    }

    // A program with a window of its own: the panel goes first, so that
    // window is not under it and gets the keys.
    function hand(argv: var): void {
        Controls.close();
        Apps.open(argv);
    }

    function capture(): void {
        Controls.close();
        captureLater.restart();
    }

    function displays(): void {
        Controls.close();
        root.displaysAsked();
    }

    function wallpaper(): void {
        Controls.close();
        root.wallpaperAsked();
    }

    // As the session dialog locks: loginctl, so hypridle's lock_cmd runs
    // lock.sh, which turns fcitx5 off first (PowerMenu.qml says why).
    function lock(): void {
        Controls.close();
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function session(): void {
        Controls.close();
        Session.menuOpen = true;
    }

    // Here, not in the window: the window is gone by the time it fires.
    Timer {
        id: captureLater

        interval: Theme.controlCaptureDelayMs
        onTriggered: Apps.open([root.hyprScripts + "/capture.sh", "region"])
    }

    // A lock takes the keyboard; the panel would hold it again after.
    Connections {
        target: KeyFeed

        function onLockedChanged() {
            if (KeyFeed.locked)
                Controls.close();
        }
    }

    // No key of its own, the power button being the way in; named so one can
    // be bound in keybinds.lua as the other surfaces are.
    GlobalShortcut {
        name: "controlCentre"
        description: "Show or hide the control centre"
        onPressed: Controls.toggle(null)
    }

    // A section opened in place. A group, so it sits in the well (Theme's
    // line roles); it opens and shuts at the notification panel's pace, and
    // keeps what it showed while it shuts.
    component Section: Item {
        id: section

        required property bool shown
        property Component content: null

        width: parent ? parent.width : 0
        height: section.shown ? well.height + Theme.controlGap : 0
        visible: height > 0
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: section.shown ? Theme.notifEnterMs : Theme.notifLeaveMs
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            id: well

            y: Theme.controlGap
            width: parent.width
            height: rows.height + Theme.controlRowInset * 2
            radius: Theme.controlWellRadius
            color: Theme.surfaceWell

            Loader {
                id: rows

                x: Theme.controlRowInset
                y: Theme.controlRowInset
                width: parent.width - Theme.controlRowInset * 2
                active: section.shown || section.height > 0
                sourceComponent: section.content
            }
        }
    }

    // Between a section's list and the program behind it, as between a
    // menu's groups: fainter than the panel's edge.
    component Rule: Item {
        width: parent ? parent.width : 0
        height: Theme.menuSeparatorHeight

        Rectangle {
            x: Theme.menuRowPad
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 2 * x
            height: Theme.surfaceBorder
            color: Theme.surfaceSeparator
        }
    }

    LazyLoader {
        id: loader

        active: Controls.open

        PanelWindow {
            id: win

            // The screen whose bar was clicked, else the focused one.
            screen: Controls.screen ?? Screens.focused
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:control-centre"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // The panel's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            // The microphone, read as Volume reads the sink, and tracked only
            // while the panel is up.
            readonly property var source: Pipewire.defaultAudioSource
            readonly property bool micKnown: win.source?.ready ?? false
            readonly property bool micMuted: win.source?.audio?.muted ?? false

            PwObjectTracker {
                objects: win.source ? [win.source] : []
            }

            // Wi-Fi scans while its section is open, as GNOME's menu asks for
            // one, and stops with it.
            Binding {
                target: Net.wifiDevice
                property: "scannerEnabled"
                value: true
                when: Net.wifiDevice !== null && Controls.expanded === "wifi"
            }

            // The brightness service knows a level once it has written or read
            // one; read here, so the slider opens where the screen is.
            Component.onCompleted: {
                if (Brightness.available)
                    Brightness.read();
                Mirror.watchers += 1;
            }
            Component.onDestruction: Mirror.watchers -= 1

            // The toggles in GNOME's order, each only where its device or
            // service is there; the rest close up, two to a row.
            readonly property var tiles: [
                Net.wifiDevice !== null || Net.wiredDevice !== null ? "wifi" : "",
                Bt.present ? "bluetooth" : "",
                win.source !== null ? "mic" : "",
                Camera.installed && Camera.state !== "none" && Camera.state !== "unknown" ? "camera" : "",
                Controls.profilesAnswered ? "power" : "",
                "tablet"
            ].filter(t => t !== "")
            readonly property var rows: {
                const out = [];
                for (let i = 0; i < win.tiles.length; i += 2)
                    out.push(win.tiles.slice(i, i + 2));
                return out;
            }

            // The network tile shows the link in use, the user's call
            // (2026-11-04): a cable, when one is up, as the bar's item shows
            // it (Net.preferWired: it is the route traffic takes), or a wired
            // machine with no Wi-Fi at all. A cable has no radio to switch
            // off, so the tile then only opens its section, where Wi-Fi keeps
            // a switch of its own.
            readonly property bool wired: Net.preferWired || Net.wifiDevice === null

            function linkSpeed(): string {
                const mbps = Net.wiredDevice?.linkSpeed ?? 0;
                if (!Net.wiredConnected)
                    return Net.wiredHasLink ? "Connecting…" : "Cable unplugged";
                if (mbps >= 1000)
                    return `Connected · ${Math.round(mbps / 100) / 10} Gb/s`;
                return mbps > 0 ? `Connected · ${mbps} Mb/s` : "Connected";
            }

            function tile(id: string): var {
                switch (id) {
                case "wifi":
                    if (win.wired)
                        return {
                            icon: Theme.iconEthernet,
                            title: "Ethernet",
                            detail: win.linkSpeed(),
                            active: Net.wiredConnected,
                            expandable: true,
                            opensOnly: true
                        };
                    return {
                        icon: !Net.wifiRadioOn ? Theme.iconWifiOff
                              : !Net.wifiConnected ? Theme.iconWifiDown
                              : Controls.wifiGlyph(Math.max(0, Net.signal) / 100, false),
                        title: "Wi-Fi",
                        detail: !Net.wifiRadioOn ? "Off" : Net.wifiConnected ? Net.ssid : "Not connected",
                        active: Net.wifiRadioOn,
                        expandable: true
                    };
                case "bluetooth":
                    return {
                        icon: Bt.icon(),
                        title: "Bluetooth",
                        detail: !Bt.enabled ? "Off"
                                : Bt.connectedCount > 1 ? `${Bt.firstName} +${Bt.connectedCount - 1}`
                                : Bt.connectedCount === 1 ? Bt.firstName : "On",
                        active: Bt.enabled,
                        expandable: true
                    };
                case "mic":
                    return {
                        icon: win.micMuted ? Theme.iconMicOff : Theme.iconMic,
                        title: "Microphone",
                        detail: !win.micKnown ? "" : win.micMuted ? "Muted" : "On",
                        active: win.micKnown && !win.micMuted
                    };
                case "camera":
                    return {
                        icon: Camera.state === "on" ? Theme.iconCamera : Theme.iconCameraOff,
                        title: "Cameras",
                        detail: ({ on: "On", off: "Off", stuck: "On, one held off", leak: "Off, one still on" })[Camera.state] ?? "",
                        active: Camera.state === "on"
                    };
                case "tablet":
                    return {
                        icon: Theme.iconTablet,
                        title: "Tablet",
                        detail: Mirror.running ? (Mirror.via === "wifi" ? "Mirroring · Wi-Fi" : "Mirroring · USB") : Mirror.title(Mirror.state),
                        active: Mirror.running,
                        expandable: true,
                        opensOnly: true
                    };
                case "power":
                    return {
                        icon: win.profile(PowerProfiles.profile).icon,
                        title: "Power mode",
                        detail: win.profile(PowerProfiles.profile).label,
                        // Lit off the default, as GNOME lights it.
                        active: PowerProfiles.profile !== PowerProfile.Balanced,
                        expandable: true,
                        opensOnly: true
                    };
                }
                return {};
            }

            function flip(id: string): void {
                switch (id) {
                case "wifi":
                    Networking.wifiEnabled = !Networking.wifiEnabled;
                    break;
                case "bluetooth":
                    if (Bt.adapter)
                        Bt.adapter.enabled = !Bt.adapter.enabled;
                    break;
                // Through PipeWire, as Volume mutes the sink; the keys' script
                // while the source is not read yet.
                case "mic":
                    if (win.micKnown)
                        win.source.audio.muted = !win.source.audio.muted;
                    else
                        Quickshell.execDetached([root.hyprScripts + "/volume.sh", "mic-mute"]);
                    break;
                // Off asks for nothing; on asks for a password (camera.sh) in
                // the polkit agent's window, which could take no keys while the
                // panel holds them, so the panel goes first. A camera live
                // behind a switch that is off is switched off again.
                case "camera":
                    if (Camera.state === "off")
                        root.hand([root.hyprScripts + "/camera.sh", "on"]);
                    else
                        Quickshell.execDetached([root.hyprScripts + "/camera.sh", "off"]);
                    break;
                }
            }

            // ---- Wi-Fi -------------------------------------------------------
            readonly property var networks: {
                const list = (Net.wifiDevice?.networks?.values ?? []).map(n => ({
                    name: n.name,
                    connected: n.connected,
                    known: n.known,
                    signal: n.signalStrength,
                    // OWE encrypts without a password.
                    secured: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
                    state: n.state,
                    ref: n
                }));
                return Controls.networkOrder(list, Theme.controlRowsMost);
            }

            // A saved network or an open one connects here. One that wants a
            // password closes the panel first, whose hold on the keys the
            // agent's prompt would wait behind; the shell never sees it.
            function pickNetwork(n: var): void {
                if (n.connected)
                    return;
                if (n.known || !n.secured) {
                    n.ref.connect();
                    return;
                }
                root.asked = n.ref;
                Controls.close();
                n.ref.connect();
            }

            function networkDetail(n: var): string {
                if (n.state === ConnectionState.Connecting)
                    return "Connecting…";
                if (n.state === ConnectionState.Disconnecting)
                    return "Disconnecting…";
                return n.connected ? "" : n.known ? "Saved" : "";
            }

            // ---- Bluetooth -------------------------------------------------
            // Paired devices only: finding and pairing a new one is bluetui's.
            readonly property var devices: Bt.pairedDevices.slice()
                .sort((a, b) => (b.connected - a.connected)
                      || (a.deviceName || a.name || "").localeCompare(b.deviceName || b.name || ""))
                .slice(0, Theme.controlRowsMost)

            function deviceDetail(d: var): string {
                if (d.state === BluetoothDeviceState.Connecting)
                    return "Connecting…";
                if (d.state === BluetoothDeviceState.Disconnecting)
                    return "Disconnecting…";
                return d.connected && d.batteryAvailable ? `${Math.round(d.battery * 100)}%` : "";
            }

            // ---- Sound -----------------------------------------------------
            // The devices AudioDevices takes snapshots of, and the default from
            // its last snapshot: plain values, so nothing here reads PipeWire's
            // defaults while PipeWire is changing them (AudioDevices.qml).
            readonly property string sinkName: AudioDevices.seen?.sink?.def ?? ""
            readonly property var outputs: AudioDevices.nodes
                .filter(n => n.ready && n.type === PwNodeType.AudioSink)
                .map(n => Object.assign({ node: n }, AudioDevices.described(n)))

            function outputGlyph(kind: string): string {
                switch (kind) {
                case "bluetooth":
                    return Theme.iconHeadset;
                case "jack":
                case "usb":
                    return Theme.iconHeadphones;
                case "fallback":
                    return Theme.iconSpeaker;
                }
                // HDMI and DisplayPort: the screen's own speakers.
                return Theme.iconMonitor;
            }

            // ---- Power mode ------------------------------------------------
            readonly property var profiles: [
                PowerProfiles.hasPerformanceProfile
                    ? { profile: PowerProfile.Performance, label: "Performance", icon: Theme.iconSpeedFast } : null,
                { profile: PowerProfile.Balanced, label: "Balanced", icon: Theme.iconSpeedMid },
                { profile: PowerProfile.PowerSaver, label: "Power saver", icon: Theme.iconSpeedSlow }
            ].filter(p => p !== null)

            function profile(value: var): var {
                return win.profiles.find(p => p.profile === value)
                       ?? win.profiles.find(p => p.profile === PowerProfile.Balanced) ?? {};
            }

            // Why performance is held back, when the daemon says it is.
            readonly property string degraded: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
                                               ? "Held back on a lap"
                                               : PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature
                                               ? "Held back, too hot" : ""

            // What can be mirrored, found while this is open (services/Mirror.qml),
            // the settings a row behind.
            Component {
                id: tabletRows

                Column {
                    Component.onCompleted: {
                        Mirror.watchers += 1;
                        Mirror.scanners += 1;
                    }
                    Component.onDestruction: {
                        Mirror.scanners -= 1;
                        Mirror.watchers -= 1;
                    }

                    Repeater {
                        model: Mirror.devices

                        ControlRow {
                            id: tabletRow

                            required property var modelData

                            width: parent.width
                            icon: tabletRow.modelData.via === "wifi" ? Theme.iconWifi4 : Theme.iconTablet
                            label: tabletRow.modelData.name
                            detail: Mirror.deviceDetail(tabletRow.modelData)
                            checked: Mirror.isCurrent(tabletRow.modelData)
                            quiet: !Mirror.usable(tabletRow.modelData)
                            onActivated: Mirror.connect(tabletRow.modelData)
                        }
                    }

                    ControlRow {
                        width: parent.width
                        visible: Mirror.devices.length === 0
                        quiet: true
                        label: Mirror.searched ? "No tablet found" : "Searching…"
                        detail: Mirror.searched ? "Plug it in by USB" : ""
                    }

                    Rule {}

                    ControlRow {
                        width: parent.width
                        visible: (Mirror.options.wifi ?? "") !== ""
                        icon: Theme.iconWifiOff
                        label: "Close Wi-Fi access"
                        detail: (Mirror.options.wifi ?? "").split(":")[0]
                        onActivated: Mirror.forget()
                    }

                    ControlRow {
                        width: parent.width
                        icon: Theme.iconSettings
                        label: "Mirror settings"
                        onActivated: Mirror.togglePanel(win.screen)
                    }
                }
            }

            Component {
                id: wifiRows

                Column {
                    // Under a cable the tile switches nothing: Wi-Fi's own
                    // switch is here.
                    ControlRow {
                        width: parent.width
                        visible: win.wired && Net.wifiDevice !== null
                        icon: Net.wifiRadioOn ? Theme.iconWifi4 : Theme.iconWifiOff
                        label: Net.wifiRadioOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
                        onActivated: Networking.wifiEnabled = !Networking.wifiEnabled
                    }

                    Repeater {
                        model: Net.wifiDevice !== null && Net.wifiRadioOn ? win.networks : []

                        ControlRow {
                            id: networkRow

                            required property var modelData

                            width: parent.width
                            icon: Controls.wifiGlyph(networkRow.modelData.signal, networkRow.modelData.secured)
                            label: networkRow.modelData.name
                            checked: networkRow.modelData.connected
                            detail: win.networkDetail(networkRow.modelData)
                            onActivated: win.pickNetwork(networkRow.modelData)
                        }
                    }

                    ControlRow {
                        width: parent.width
                        visible: Net.wifiDevice !== null && (Net.wifiRadioOn ? win.networks.length === 0 : !win.wired)
                        quiet: true
                        label: !Net.wifiRadioOn ? "Wi-Fi is off" : "Searching…"
                    }

                    Rule {}

                    ControlRow {
                        width: parent.width
                        icon: Theme.iconSettings
                        label: "Network settings"
                        onActivated: root.hand(root.wifiTool)
                    }
                }
            }

            Component {
                id: bluetoothRows

                Column {
                    Repeater {
                        model: Bt.enabled ? win.devices : []

                        ControlRow {
                            id: deviceRow

                            required property var modelData

                            width: parent.width
                            icon: deviceRow.modelData.connected ? Theme.iconBtLinked : Theme.iconBt
                            label: deviceRow.modelData.deviceName || deviceRow.modelData.name || deviceRow.modelData.address
                            checked: deviceRow.modelData.connected
                            detail: win.deviceDetail(deviceRow.modelData)
                            onActivated: {
                                if (deviceRow.modelData.connected)
                                    deviceRow.modelData.disconnect();
                                else
                                    deviceRow.modelData.connect();
                            }
                        }
                    }

                    ControlRow {
                        width: parent.width
                        visible: !Bt.enabled || win.devices.length === 0
                        quiet: true
                        label: !Bt.enabled ? "Bluetooth is off" : "No paired devices"
                    }

                    Rule {}

                    ControlRow {
                        width: parent.width
                        icon: Theme.iconSettings
                        label: "Bluetooth settings"
                        onActivated: root.hand(root.bluetoothTool)
                    }
                }
            }

            Component {
                id: soundRows

                Column {
                    Repeater {
                        model: win.outputs

                        ControlRow {
                            id: outputRow

                            required property var modelData

                            width: parent.width
                            icon: win.outputGlyph(outputRow.modelData.kind)
                            label: outputRow.modelData.label
                            checked: outputRow.modelData.name === win.sinkName
                            // The configured default, the value a mixer's click
                            // writes; AudioPolicy's rules then hold as for any.
                            onActivated: Pipewire.preferredDefaultAudioSink = outputRow.modelData.node
                        }
                    }

                    Rule {}

                    ControlRow {
                        width: parent.width
                        icon: Theme.iconSettings
                        label: "Sound settings"
                        onActivated: root.hand(root.mixerTool)
                    }
                }
            }

            Component {
                id: powerRows

                Column {
                    Repeater {
                        model: win.profiles

                        ControlRow {
                            id: profileRow

                            required property var modelData

                            width: parent.width
                            icon: profileRow.modelData.icon
                            label: profileRow.modelData.label
                            checked: PowerProfiles.profile === profileRow.modelData.profile
                            detail: profileRow.modelData.profile === PowerProfile.Performance ? win.degraded : ""
                            onActivated: PowerProfiles.profile = profileRow.modelData.profile
                        }
                    }
                }
            }

            function sectionFor(id: string): var {
                switch (id) {
                case "wifi":
                    return wifiRows;
                case "bluetooth":
                    return bluetoothRows;
                case "power":
                    return powerRows;
                case "tablet":
                    return tabletRows;
                }
                return null;
            }

            FittedStage {
                id: stage

                fit: win.fit
                focus: true

                // Esc closes at once, an open section with it (the user,
                // 2026-11-04: Esc once, not twice).
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Escape)
                        return;
                    Controls.close();
                    event.accepted = true;
                }

                // A click beside the panel closes it, as beside any modal.
                MouseArea {
                    anchors.fill: parent
                    onClicked: Controls.close()
                }

                Rectangle {
                    id: panel

                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Theme.barHeight + Theme.notifBarGap
                    anchors.rightMargin: Theme.edgeMarginRight + Theme.menuItemPadX
                    width: Theme.controlWidth
                    height: body.implicitHeight + Theme.controlPad * 2
                    radius: Theme.controlRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

                    // Swallows clicks so a near miss does not close the panel.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: body

                        x: Theme.controlPad
                        y: Theme.controlPad
                        width: panel.width - Theme.controlPad * 2
                        spacing: Theme.controlGap

                        // The battery at the left, as GNOME's; the buttons at
                        // the right, the session dialog's outermost, where the
                        // power button that opened the panel stands.
                        Item {
                            width: body.width
                            height: Theme.controlButtonSize

                            Row {
                                visible: Power.present
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.px(6)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.statusGlyphGap

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Theme.batteryIcon(Power.percent, Power.charging)
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.menuIconSize
                                    color: Theme.fg
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `${Power.percent}%`
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.controlTitleSize
                                    font.weight: Font.Medium
                                    font.features: ({ "tnum": 1 })
                                    color: Theme.fg
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.controlGap

                                ControlButton {
                                    icon: Theme.iconScreenshot
                                    onClicked: root.capture()
                                }

                                ControlButton {
                                    icon: Theme.iconMonitor
                                    onClicked: root.displays()
                                }

                                ControlButton {
                                    icon: Theme.iconWallpaper
                                    onClicked: root.wallpaper()
                                }

                                ControlButton {
                                    icon: Theme.iconLock
                                    onClicked: root.lock()
                                }

                                ControlButton {
                                    objectName: "e2e-controls-power"
                                    icon: Theme.iconPower
                                    onClicked: root.session()
                                }
                            }
                        }

                        // The sound and, behind its chevron, where it plays;
                        // the chevron only with more than one output to pick.
                        Column {
                            width: body.width
                            visible: Volume.present

                            ControlSlider {
                                width: parent.width
                                icon: Theme.volumeIcon(Volume.percent, Volume.muted)
                                value: Volume.known ? Volume.percent / 100 : -1
                                iconClickable: true
                                expandable: win.outputs.length > 1
                                expanded: Controls.expanded === "sound"
                                onIconClicked: Volume.toggleMute()
                                onMoved: value => Volume.set(value * 100)
                                onExpandRequested: Controls.expand("sound")
                            }

                            Section {
                                shown: Controls.expanded === "sound"
                                content: soundRows
                            }
                        }

                        ControlSlider {
                            width: body.width
                            visible: Brightness.available
                            icon: Theme.iconBrightness
                            value: Brightness.percent >= 0 ? Brightness.percent / 100 : -1
                            onMoved: value => Brightness.set(value * 100)
                        }

                        Repeater {
                            model: win.rows

                            Column {
                                id: tileRow

                                required property var modelData

                                readonly property bool holds: tileRow.modelData.indexOf(Controls.expanded) !== -1
                                // What the section under this row shows, kept
                                // while it shuts so it shuts on its own rows.
                                property string kept: ""
                                readonly property string showing: tileRow.holds ? Controls.expanded : tileRow.kept

                                onShowingChanged: tileRow.kept = tileRow.showing
                                width: body.width

                                Row {
                                    spacing: Theme.controlGap

                                    Repeater {
                                        model: tileRow.modelData

                                        ControlTile {
                                            id: tile

                                            required property string modelData
                                            readonly property var info: win.tile(tile.modelData)

                                            // Whole pixels: a half one blurs the text.
                                            width: Math.floor((body.width - Theme.controlGap) / 2)
                                            icon: tile.info.icon ?? ""
                                            title: tile.info.title ?? ""
                                            detail: tile.info.detail ?? ""
                                            active: tile.info.active ?? false
                                            expandable: tile.info.expandable ?? false
                                            opensOnly: tile.info.opensOnly ?? false
                                            expanded: Controls.expanded === tile.modelData
                                            onToggled: win.flip(tile.modelData)
                                            onExpandRequested: Controls.expand(tile.modelData)
                                        }
                                    }
                                }

                                Section {
                                    shown: tileRow.holds
                                    content: win.sectionFor(tileRow.showing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
