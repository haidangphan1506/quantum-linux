import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Proceso aparte para detectar inactividad (screensaver). IdleMonitor de Quickshell
// se cuelga (SIGSEGV) al destruirse, y en el shell principal eso pasaba en cada recarga
// o al cerrarlo. Aquí vive solo, casi nunca se recarga, y avisa al shell por IPC:
//   qs -c caelestia ipc call screensaver idle true|false
// Lo arranca modules/screensaver/Screensaver.qml (qs -p ... -n -d: una sola instancia).
ShellRoot {
    id: root
    property int timeout: 600
    property bool enabled: true

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quantum/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text()).screensaver ?? {};
                root.timeout = Math.max(5, s.timeout ?? 600);
                root.enabled = s.enabled ?? true;
            } catch (e) {}
        }
    }

    IdleMonitor {
        id: idle
        enabled: root.enabled
        timeout: root.timeout
        respectInhibitors: false
        onIsIdleChanged: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "screensaver", "idle", isIdle ? "true" : "false"])
    }
}
