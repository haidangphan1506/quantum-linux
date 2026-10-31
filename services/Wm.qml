pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Gestor de ventanas (Wayfire) a través de protocolos estándar de Wayland:
// ventanas abiertas para la barra de tareas y la pantalla donde mostrar paneles.
Singleton {
    id: root

    readonly property var windows: ToplevelManager.toplevels.values
    readonly property var active: ToplevelManager.activeToplevel

    // Los paneles se abren en la pantalla de la ventana activa (o en la primera).
    readonly property var screen: active?.screens?.[0] ?? Quickshell.screens[0]

    // Las ventanas propias del shell (Personalizar) llegan como «org.quickshell».
    function iconFor(appId: string): string {
        if (appId === "org.quickshell") return "quantum-personalize";
        return DesktopEntries.heuristicLookup(appId)?.icon ?? appId;
    }

    // Grupos de la barra de tareas: fijadas primero (en su orden) y luego las
    // demás abiertas. Cada grupo: { id, name, icon, entry, pinned, wins }.
    // Se cachea y solo se recalcula cuando cambia el estado real (evita parpadeo).
    property var groups: []

    function updateGroups(): void {
        const pinned = (Settings.dock.pinned ?? []).slice();
        const out = [];
        const byId = {};
        const add = (id, entry, isPinned) => {
            const g = { id, entry, pinned: isPinned, wins: [],
                        name: entry?.name ?? root.nameFor(id), icon: entry?.icon ?? root.iconFor(id) };
            byId[id] = g;
            out.push(g);
            return g;
        };
        for (let i = 0; i < pinned.length; i++) {
            const pid = pinned[i];
            const e = DesktopEntries.byId(pid) ?? DesktopEntries.heuristicLookup(pid);
            if (e)
                add(e.id, e, true);
            else
                add(pid, null, true);
        }
        for (let i = 0; i < root.windows.length; i++) {
            const w = root.windows[i];
            const e = DesktopEntries.heuristicLookup(w.appId);
            const id = e?.id ?? w.appId;
            const g = byId[id] ?? add(id, e, false);
            if (g.wins.indexOf(w) === -1)
                g.wins.push(w);
        }
        groups = out;
    }

    Component.onCompleted: updateGroups()
    onWindowsChanged: updateGroups()
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged(): void { root.updateGroups(); }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged(): void { root.updateGroups(); }
    }
    Connections {
        target: Settings.dock
        function onPinnedChanged(): void { root.updateGroups(); }
    }

    function togglePin(id: string): void {
        const list = (Settings.dock.pinned ?? []).slice();
        const i = list.indexOf(id);
        if (i >= 0) list.splice(i, 1);
        else list.push(id);
        Settings.setPinned(list);
    }

    // Mueve una app de la barra a la posición «to» (índice entre todos los íconos).
    // Las fijadas van primero: si se suelta una app no fijada entre las fijadas, queda fijada ahí.
    function moveGroup(id: string, to: int): void {
        const list = (Settings.dock.pinned ?? []).slice();
        const from = list.indexOf(id);
        if (from >= 0) {
            list.splice(from, 1);
            list.splice(Math.max(0, Math.min(list.length, to)), 0, id);
        } else if (to <= list.length) {
            list.splice(Math.max(0, to), 0, id);
        } else {
            return;
        }
        Settings.setPinned(list);
    }

    function nameFor(appId: string): string {
        if (appId === "org.quickshell") return I18n.t("Personalizar");
        return DesktopEntries.heuristicLookup(appId)?.name ?? appId;
    }

    // Hyprland no tiene "minimizado": hyprlands/minimize.lua mueve la ventana al workspace
    // oculto "special:minimized" cuando se pide minimizar. Aquí se lee de ahí.
    readonly property string minimizedWs: "special:minimized"
    readonly property var minimizedWins: Hyprland.toplevels.values
        .filter(t => t.workspace?.name === root.minimizedWs)
        .map(t => t.wayland)

    function isMinimized(win: var): bool {
        return !!win && (win.minimized || root.minimizedWins.indexOf(win) >= 0);
    }

    // Minimizar / restaurar: se pide por wlr-foreign-toplevel y Hyprland (minimize.lua) lo hace.
    function minimize(win: Toplevel): void { win.minimized = true; }
    function restore(win: Toplevel): void { win.minimized = false; }

    // Enfocar una ventana; si está minimizada, primero vuelve del dock (como en macOS).
    function focus(win: Toplevel): void {
        if (root.isMinimized(win)) root.restore(win);
        else win.activate();
    }

    // Clic en el dock: si ya está activa se minimiza, si está minimizada vuelve, si no, se enfoca.
    function toggle(win: Toplevel): void {
        if (root.isMinimized(win))
            root.restore(win);
        else if (win.activated)
            root.minimize(win);
        else
            win.activate();
    }

    function logout(): void {
        Quickshell.execDetached(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]);
    }
}
