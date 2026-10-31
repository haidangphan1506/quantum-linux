pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)

    readonly property string label: !available ? I18n.t("No disponible") : !enabled ? I18n.t("Apagado") : connected.length > 0 ? connected[0].name : I18n.t("Encendido")
    readonly property string icon: !enabled ? "bluetooth_disabled" : connected.length > 0 ? "bluetooth_connected" : "bluetooth"

    function toggle(): void {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }
}
