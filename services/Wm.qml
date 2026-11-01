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

    // Las ventanas propias del shell (Personalizar) llegan como «org.quickshell», pero el
    // sistema trae su propio org.quickshell.desktop (icono de Quickshell): hay que preferir
    // el de Personalizar, si no, la ventana y la barra muestran el icono equivocado.
    function entryFor(appId: string): var {
        if (appId === "org.quickshell")
            return DesktopEntries.byId("quantum-personalize") ?? DesktopEntries.heuristicLookup(appId);
        return DesktopEntries.heuristicLookup(appId);
    }

    function iconFor(appId: string): string {
        return root.entryFor(appId)?.icon ?? appId;
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
            // solo apps que existen en el sistema (las desinstaladas no se muestran;
            // Apps.cleanPinned() las quita de la lista)
            const e = DesktopEntries.byId(pid);
            if (e && !byId[e.id])
                add(e.id, e, true);
        }
        const nPinned = out.length;
        for (let i = 0; i < root.windows.length; i++) {
            const w = root.windows[i];
            const e = root.entryFor(w.appId);
            const id = e?.id ?? w.appId;
            const g = byId[id] ?? add(id, e, false);
            if (g.wins.indexOf(w) === -1)
                g.wins.push(w);
        }
        // las abiertas sin fijar siguen el orden que les diste al arrastrarlas (en memoria);
        // las nuevas van al final, en el orden en que llegaron
        const open = out.slice(nPinned);
        const rank = id => { const k = root.openOrder.indexOf(id); return k >= 0 ? k : 1e6; };
        open.sort((a, b) => rank(a.id) - rank(b.id));
        groups = out.slice(0, nPinned).concat(open);
    }

    // Orden de las apps abiertas sin fijar (solo en memoria; se pierde al reiniciar el shell)
    property var openOrder: []

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

    // Mueve una app de la barra a la posición «to» (índice entre todos los íconos, como se ve).
    // Las fijadas van primero: si cae dentro del bloque de fijadas queda fijada; si cae después,
    // se desfija (abierta sin fijar). Así arrastrar una app abierta (brave, herdr…) a la zona
    // fijada la fija, y arrastrar una fijada a la zona de abiertas la quita.
    function moveGroup(id: string, to: int): void {
        const moved = root.groups.find(g => g.id === id);
        if (!moved) return;
        const others = root.groups.filter(g => g.id !== id);
        const pinnedOthers = others.filter(g => g.pinned).length;
        const t = Math.max(0, Math.min(others.length, to));
        // solo se puede fijar una app que tenga .desktop (si no, no sobreviviría al recalcular)
        const pinnedNow = t <= pinnedOthers && !!moved.entry;
        const ids = others.map(g => g.id);
        ids.splice(t, 0, id);
        const pinnedIds = [], openIds = [];
        for (const x of ids) {
            const isPinned = x === id ? pinnedNow : others.find(g => g.id === x).pinned;
            (isPinned ? pinnedIds : openIds).push(x);
        }
        root.openOrder = openIds;
        Settings.setPinned(pinnedIds);
        root.updateGroups();
    }

    function nameFor(appId: string): string {
        if (appId === "org.quickshell") return I18n.t("Personalizar");
        return root.entryFor(appId)?.name ?? appId;
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

    // Como macOS: las ventanas minimizadas van a la derecha del divisor del dock,
    // cada una con su propio icono (la app sigue en su sitio con el punto de «abierta»).
    readonly property var minimizedItems: root.windows
        .filter(w => root.isMinimized(w))
        .map(w => ({ win: w, appId: w.appId, title: w.title,
                     icon: root.iconFor(w.appId) }))

    // Clic en un icono del dock: alterna mostrar/ocultar. Si la app esta al frente se
    // minimizan sus ventanas visibles; si no, se activa (o se restaura una minimizada).
    function activateGroup(g: var): void {
        if (g.wins.some(w => w.activated && !root.isMinimized(w))) {
            g.wins.filter(w => !root.isMinimized(w)).forEach(w => root.minimize(w));
            return;
        }
        const w = g.wins.find(x => !root.isMinimized(x)) ?? g.wins[0];
        root.focus(w);
    }

    // Minimizar / restaurar: se pide por wlr-foreign-toplevel y Hyprland (minimize.lua) lo hace.
    function minimize(win: Toplevel): void { win.minimized = true; }
    function restore(win: Toplevel): void { win.minimized = false; }

    // Activar sin mover el cursor y subiendo la ventana encima de las demás: el «activate» de
    // wlr-foreign-toplevel de Hyprland siempre lleva el cursor a la ventana, así que se usa
    // cael_activate() de hyprlands/minimize.lua. Sin dirección de Hyprland, el activate normal.
    function hyprAddress(win: Toplevel): string {
        const t = Hyprland.toplevels.values.find(h => h.wayland === win);
        const a = t?.address ?? "";
        return a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a);
    }
    function activate(win: Toplevel): void {
        const a = root.hyprAddress(win);
        if (a) Quickshell.execDetached(["hyprctl", "eval", `cael_activate('${a}')`]);
        else win.activate();
    }

    // Enfocar una ventana; si está minimizada, primero vuelve del dock (como en macOS).
    function focus(win: Toplevel): void {
        if (root.isMinimized(win)) root.restore(win);
        else root.activate(win);
    }

    // Clic en el dock: si ya está activa se minimiza, si está minimizada vuelve, si no, se enfoca.
    function toggle(win: Toplevel): void {
        if (root.isMinimized(win))
            root.restore(win);
        else if (win.activated)
            root.minimize(win);
        else
            root.activate(win);
    }

    function logout(): void {
        Quickshell.execDetached(["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""]);
    }
}
