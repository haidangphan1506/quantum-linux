pragma Singleton

import QtQuick
import Quickshell

// Dónde está cada icono del dock en la pantalla, para el efecto genie (modules/effects/GenieFx.qml):
// como en macOS, la ventana vuela a su icono (abrir/cerrar) o al final del dock (minimizar/restaurar).
// Solo el dock de la pantalla principal se registra.
Singleton {
    id: root

    property var dock: null           // PanelWindow del dock (Dock.qml)
    property var taskbar: null        // fila de apps (Taskbar.qml)
    property var buttons: ({})        // id del grupo (id del .desktop) -> DockButton

    function register(id: string, item: var): void {
        if (id) root.buttons[id] = item;
    }
    function unregister(id: string, item: var): void {
        if (id && root.buttons[id] === item) delete root.buttons[id];
    }

    // Centro del icono de la app en coordenadas de pantalla, o null si no está en el dock
    function appPoint(id: string): var {
        const b = root.buttons[id];
        if (!b || !root.dock) return null;
        return root.dock.screenPoint(b, b.width / 2, b.height / 2);
    }

    // Justo después del último icono: ahí aparecen las ventanas minimizadas
    function endPoint(): var {
        const t = root.taskbar;
        if (!t || !root.dock) return null;
        return root.dock.vertical ? root.dock.screenPoint(t, t.width / 2, t.height + 25)
                                  : root.dock.screenPoint(t, t.width + 25, t.height / 2);
    }
}
