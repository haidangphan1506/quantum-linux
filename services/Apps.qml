pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Lista de apps y búsqueda tolerante (sin tildes, por nombre, descripción y palabras clave).
Singleton {
    id: root

    property var lastLaunch: ({})
    property int launchCooldown: 500

    // Todas las apps instaladas (también las NoDisplay), para la página «Aplicaciones».
    // Quickshell no incluye las NoDisplay en `applications`, pero byId() sí las encuentra:
    // se completan con los ids que encuentra el escaneo de .desktop (ver pkgProc).
    readonly property var everything: {
        const seen = {};
        const out = [];
        for (const a of DesktopEntries.applications.values) {
            seen[a.id] = true;
            out.push(a);
        }
        for (const id of Object.keys(root.packages)) {
            if (seen[id]) continue;
            const e = DesktopEntries.byId(id);
            if (e && !seen[e.id]) {
                seen[e.id] = true;
                out.push(e);
            }
        }
        return out.sort((a, b) => a.name.localeCompare(b.name, I18n.lang));
    }

    // Las que aparecen en el menú de apps.
    readonly property var all: everything.filter(a => root.isVisible(a))

    // Visible = lo que eligió el usuario; si no eligió nada, lo que dice el .desktop.
    function isVisible(app: var): bool {
        const id = app?.id ?? "";
        if ((Settings.apps.hidden ?? []).indexOf(id) >= 0) return false;
        if ((Settings.apps.shown ?? []).indexOf(id) >= 0) return true;
        return !app.noDisplay;
    }

    function isOverridden(app: var): bool {
        const id = app?.id ?? "";
        return (Settings.apps.hidden ?? []).indexOf(id) >= 0 || (Settings.apps.shown ?? []).indexOf(id) >= 0;
    }

    // Guarda solo lo que difiere del .desktop: así, si el paquete cambia, se respeta.
    function setVisible(app: var, on: bool): void {
        const id = app.id;
        const hidden = (Settings.apps.hidden ?? []).filter(x => x !== id);
        const shown = (Settings.apps.shown ?? []).filter(x => x !== id);
        if (on && app.noDisplay) shown.push(id);
        if (!on && !app.noDisplay) hidden.push(id);
        Settings.set("apps", "hidden", hidden);
        Settings.set("apps", "shown", shown);
    }

    function resetVisibility(): void {
        Settings.set("apps", "hidden", []);
        Settings.set("apps", "shown", []);
    }

    // Paquete dueño de cada .desktop: { "<id>": "firefox" | "flatpak" | "local" | "" }
    property var packages: ({})
    property bool packagesLoaded: false
    function loadPackages(): void {
        if (!pkgProc.running) pkgProc.running = true;
    }
    // Al iniciar y cada vez que cambian las apps instaladas (pacman, flatpak…)
    Component.onCompleted: loadPackages()
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged(): void { root.loadPackages(); }
    }
    Process {
        id: pkgProc
        // Busca los .desktop en los mismos directorios XDG y pregunta a pacman de una vez.
        command: ["sh", "-c",
            "IFS=:; for d in ${XDG_DATA_HOME:-$HOME/.local/share} ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do " +
            "for f in \"$d\"/applications/*.desktop; do [ -e \"$f\" ] || continue; " +
            "id=${f##*/}; id=${id%.desktop}; " +
            "case $f in */flatpak/*) echo \"$id\tflatpak\";; $HOME/*) echo \"$id\tlocal\";; " +
            "*) p=$(pacman -Qoq \"$f\" 2>/dev/null); echo \"$id\t$p\";; esac; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i > 0 && !(line.substring(0, i) in out))   // el primero gana, como en XDG
                        out[line.substring(0, i)] = line.substring(i + 1);
                }
                root.packages = out;
                root.packagesLoaded = true;
            }
        }
    }

    function normalize(s: string): string {
        return (s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    }

    function search(query: string): var {
        const q = normalize(query.trim());
        if (!q)
            return all;
        const scored = [];
        for (let i = 0; i < all.length; i++) {
            const app = all[i];
            const name = normalize(app.name);
            let score = -1;
            if (name.startsWith(q))
                score = 0;
            else if (name.indexOf(" ") >= 0 && name.split(/\s+/).some(w => w.startsWith(q)))
                score = 1;
            else if (name.includes(q))
                score = 2;
            else if (normalize(app.genericName).includes(q) || normalize(app.keywords).includes(q))
                score = 3;
            else if (normalize(app.comment).includes(q) || normalize(app.categories).includes(q))
                score = 4;
            if (score >= 0)
                scored.push({ app: app, score: score });
        }
        scored.sort((a, b) => {
            if (a.score !== b.score)
                return a.score - b.score;
            return a.app.name.localeCompare(b.app.name, I18n.lang);
        });
        const out = [];
        for (let i = 0; i < scored.length; i++)
            out.push(scored[i].app);
        return out;
    }

    function launch(app: DesktopEntry): void {
        if (!app)
            return;
        const key = app.id || app.name || "";
        const now = Date.now();
        if (key && root.lastLaunch[key] && (now - root.lastLaunch[key]) < root.launchCooldown)
            return;
        root.lastLaunch[key] = now;
        if (app.runInTerminal) {
            if (app.command && app.command.length > 0)
                Quickshell.execDetached(["kitty", "-e", ...app.command]);
            else
                Quickshell.execDetached(["kitty", "-e", app.exec || ""]);
        } else {
            try {
                app.execute();
            } catch (e) {
                if (app.command && app.command.length > 0)
                    Quickshell.execDetached(app.command);
                else if (app.exec)
                    Quickshell.execDetached(app.exec.split(/\s+/));
            }
        }
    }
}
