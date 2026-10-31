pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.services

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    readonly property var all: adapter ? adapter.devices.values : []
    readonly property var connected: all.filter(d => d.connected)

    // Dispositivos para la página Bluetooth: emparejados primero, luego los
    // encontrados con nombre real (los que solo tienen la MAC se ocultan).
    readonly property var paired: all.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var nearby: all.filter(d => !(d.paired || d.bonded) && root.named(d))
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property string label: !available ? I18n.t("No disponible") : !enabled ? I18n.t("Apagado") : connected.length > 0 ? connected[0].name : I18n.t("Encendido")
    readonly property string icon: !enabled ? "bluetooth_disabled" : connected.length > 0 ? "bluetooth_connected" : "bluetooth"

    // Mensaje de la última acción (como Net.status)
    property string status: ""
    property bool statusError: false
    // Dispositivo que se está emparejando, para conectarlo al terminar
    property var pairingTarget: null

    function toggle(): void {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }

    // BlueZ usa la MAC (AA-BB-...) como nombre cuando no conoce el real
    function named(d: var): bool {
        return d.name !== "" && !/^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(d.name);
    }

    function startScan(): void {
        if (adapter && adapter.enabled && !adapter.discovering)
            adapter.discovering = true;
    }

    function stopScan(): void {
        if (adapter && adapter.discovering)
            adapter.discovering = false;
    }

    function setStatus(text: string, error: bool): void {
        status = text;
        statusError = error;
        statusTimer.restart();
    }

    function busy(d: var): bool {
        return d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting;
    }

    // Clic en un dispositivo: conectar/desconectar, o emparejar si es nuevo
    function activate(d: var): void {
        if (!d || busy(d))
            return;
        if (d.connected) {
            d.disconnect();
            setStatus(I18n.t("Desconectado de ") + d.name, false);
        } else if (d.paired || d.bonded) {
            d.connect();
        } else {
            pairingTarget = d;
            d.trusted = true;
            d.pair();
            setStatus(I18n.t("Emparejando con ") + d.name + "…", false);
        }
    }

    function forget(d: var): void {
        if (!d)
            return;
        const n = d.name;
        d.forget();
        setStatus(I18n.t("Olvidado: ") + n, false);
    }

    function deviceIcon(d: var): string {
        const i = d.icon || "";
        if (i.includes("headset") || i.includes("headphone"))
            return "headphones";
        if (i.includes("audio") || i.includes("speaker"))
            return "speaker";
        if (i.includes("phone"))
            return "smartphone";
        if (i.includes("keyboard"))
            return "keyboard";
        if (i.includes("mouse"))
            return "mouse";
        if (i.includes("gaming") || i.includes("joystick"))
            return "sports_esports";
        if (i.includes("computer"))
            return "computer";
        if (i.includes("watch"))
            return "watch";
        return "bluetooth";
    }

    function hint(d: var): string {
        if (d.pairing)
            return I18n.t("Emparejando…");
        if (d.state === BluetoothDeviceState.Connecting)
            return I18n.t("Conectando…");
        if (d.state === BluetoothDeviceState.Disconnecting)
            return I18n.t("Desconectando…");
        if (d.connected)
            return d.batteryAvailable ? I18n.t("Conectado") + " · " + Math.round(d.battery * 100) + "%" : I18n.t("Conectado");
        if (d.paired || d.bonded)
            return I18n.t("Emparejado");
        return I18n.t("Toca para emparejar");
    }

    Timer {
        id: statusTimer
        interval: 6000
        onTriggered: root.status = ""
    }

    // Al terminar de emparejar: conectar (o avisar del fallo)
    Connections {
        target: root.pairingTarget
        function onPairingChanged(): void {
            const d = root.pairingTarget;
            if (!d || d.pairing)
                return;
            root.pairingTarget = null;
            if (d.paired || d.bonded) {
                d.connect();
                root.setStatus(I18n.t("Emparejado con ") + d.name, false);
            } else {
                root.setStatus(I18n.t("No se pudo emparejar con ") + d.name, true);
            }
        }
    }

    // La búsqueda solo corre mientras la página Bluetooth está abierta
    Connections {
        target: Shell
        function onBtPageChanged(): void {
            if (Shell.btPage)
                root.startScan();
            else
                root.stopScan();
        }
    }

    // Si se enciende el adaptador con la página abierta, empezar a buscar
    Connections {
        target: root.adapter
        function onEnabledChanged(): void {
            if (root.adapter.enabled && Shell.btPage)
                root.startScan();
        }
    }

    // Automatización y pruebas: qs -c caelestia ipc call bt <función>
    IpcHandler {
        target: "bt"
        function scan(): void { root.startScan(); }
        function stop(): void { root.stopScan(); }
        function count(): int { return root.paired.length + root.nearby.length; }
        function status(): string { return root.status; }
    }
}
