pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.services

Singleton {
    id: root

    // Interfaces that are never a real uplink. sysfs lists docker bridges and
    // virtual taps beside the real links, so they are filtered by name.
    readonly property var virtualPrefixes: ["lo", "docker", "veth", "virbr", "br-", "tun", "tap", "wg", "vmnet"]

    function isVirtual(name: string): bool {
        return root.virtualPrefixes.some(p => name.startsWith(p));
    }

    readonly property var devices: Networking.devices?.values ?? []

    readonly property var wifiDevice: root.devices.find(d => d.type === DeviceType.Wifi) ?? null

    // Networking.devices holds Wi-Fi and nothing else: DeviceType has only None
    // and Wifi, and the NetworkManager backend builds a device for the Wifi case
    // alone. Ethernet has to be read from sysfs, or the pill falls through to
    // the Wi-Fi icon and says "off" while a dock is carrying every packet.
    property var wiredDevice: null

    readonly property bool wifiRadioOn: Networking.wifiEnabled
    readonly property bool wifiConnected: root.wifiDevice?.connected ?? false
    readonly property bool wiredConnected: root.wiredDevice?.connected ?? false

    readonly property var wifiNetwork: {
        const networks = root.wifiDevice?.networks?.values ?? [];
        return networks.find(n => n.connected) ?? null;
    }

    readonly property string ssid: root.wifiNetwork?.name ?? ""
    // quickshell normalises this to 0.0..1.0 (wifi.hpp: "from 0.0 to 1.0";
    // wireless.cpp divides NetworkManager's 0..100 Strength by 100), so the
    // percentage has to be reconstructed. Reading it raw pins the value at 0
    // or 1 and leaves the icon on its weakest bar no matter how good the link.
    readonly property int signal: Math.round((root.wifiNetwork?.signalStrength ?? 0) * 100)

    // A wired link wins when both are up: that is the route traffic takes.
    readonly property bool preferWired: root.wiredConnected

    function wifiIcon(): string {
        if (!root.wifiRadioOn)
            return Theme.iconWifiOff;
        if (!root.wifiConnected)
            return Theme.iconWifiDown;
        if (root.signal >= 75)
            return Theme.iconWifi4;
        if (root.signal >= 50)
            return Theme.iconWifi3;
        if (root.signal >= 25)
            return Theme.iconWifi2;
        return Theme.iconWifi1;
    }

    // A link with a backing device and no wireless directory is an ethernet
    // port. carrier reads EINVAL while the interface is down, which is why the
    // field can come back empty rather than 0. address is the MAC, matching
    // what the Networking module reports for Wi-Fi.
    Process {
        id: wiredProbe

        command: ["sh", "-c", "for d in /sys/class/net/*; do [ -e \"$d/wireless\" ] && continue; [ -e \"$d/device\" ] || continue; c=\"\"; a=\"\"; read -r c 2>/dev/null < \"$d/carrier\"; read -r a 2>/dev/null < \"$d/address\"; printf '%s\\t%s\\t%s\\n' \"${d##*/}\" \"$c\" \"$a\"; done"]

        stdout: StdioCollector {
            id: wiredOut

            onStreamFinished: {
                const found = wiredOut.text.trim().split("\n").map(line => line.split("\t")).filter(f => f.length === 3 && !root.isVirtual(f[0])).map(f => ({
                            name: f[0],
                            connected: f[1] === "1",
                            address: f[2]
                        }));
                root.wiredDevice = found.find(d => d.connected) ?? found[0] ?? null;
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: wiredProbe.running = true
    }
}
