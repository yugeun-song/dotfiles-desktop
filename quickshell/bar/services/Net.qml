pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import qs.services

Singleton {
    id: root

    readonly property var devices: Networking.devices?.values ?? []

    // quickshell picks a backend once at startup and never retries, so this
    // stays set even if NetworkManager starts later. An empty device list is
    // not unknown: devices arrive over D-Bus a second or two after login.
    readonly property string unknown: Networking.backend === NetworkBackendType.None
                                      ? "NetworkManager was not running when the bar started"
                                      : ""

    readonly property var wifiDevice: root.devices.find(d => d.type === DeviceType.Wifi) ?? null

    // From NetworkManager, not /sys/class/net: NM's Wired type excludes
    // bridges, tunnels, veth pairs and modems.
    readonly property var wiredDevice: root.devices.find(d => d.type === DeviceType.Wired) ?? null

    readonly property bool wifiRadioOn: Networking.wifiEnabled
    readonly property bool wifiConnected: root.wifiDevice?.connected ?? false
    // connected = activated (carries traffic); hasLink = cable carrier only.
    readonly property bool wiredConnected: root.wiredDevice?.connected ?? false
    readonly property bool wiredHasLink: root.wiredDevice?.hasLink ?? false

    readonly property var wifiNetwork: {
        const networks = root.wifiDevice?.networks?.values ?? [];
        return networks.find(n => n.connected) ?? null;
    }

    readonly property string ssid: root.wifiNetwork?.name ?? ""
    // quickshell normalises signalStrength to 0.0..1.0 (wifi.hpp; wireless.cpp
    // divides NM's 0..100 by 100). -1 = no figure yet; 0 is a real strength.
    readonly property int signal: root.wifiNetwork
                                  ? Math.round(root.wifiNetwork.signalStrength * 100)
                                  : -1

    // Wired wins when both are up: it is the route traffic takes.
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
