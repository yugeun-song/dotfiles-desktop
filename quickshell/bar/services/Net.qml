pragma Singleton

import Quickshell
import Quickshell.Networking
import qs.services

Singleton {
    id: root

    // Interfaces that are never a real uplink. NetworkManager reports docker
    // bridges and virtual taps as ordinary devices, so they are filtered by
    // name; the Networking module only distinguishes Wifi from everything else.
    readonly property var virtualPrefixes: ["lo", "docker", "veth", "virbr", "br-", "tun", "tap", "wg", "vmnet"]

    function isVirtual(name: string): bool {
        return root.virtualPrefixes.some(p => name.startsWith(p));
    }

    readonly property var devices: Networking.devices?.values ?? []

    readonly property var wifiDevice: root.devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: root.devices.find(d => d.type !== DeviceType.Wifi && !root.isVirtual(d.name ?? "")) ?? null

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
}
