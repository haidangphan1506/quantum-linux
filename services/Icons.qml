pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Paquetes de íconos (bienvenida y Personalizar → Colores y fondo). Vienen del repo
// [quantum]: el que no está instalado se descarga al elegirlo (pide la contraseña).
// quantum-theme elige la variante (carpetas violetas en Caelestial, rosadas en Serpantium;
// oscura o clara) y recarga el escritorio, porque el shell toma sus íconos al arrancar.
Singleton {
    id: root

    readonly property var packs: [
        { id: "papirus", name: "Papirus", desc: "Los de siempre: claros y completos.", pkg: "papirus-icon-theme", size: "" },
        { id: "tela", name: "Tela", desc: "Redondeados y muy coloridos.", pkg: "tela-icon-theme", size: "19 MB" },
        { id: "fluent", name: "Fluent", desc: "Como Windows 11.", pkg: "fluent-icon-theme", size: "11 MB" },
        { id: "whitesur", name: "WhiteSur", desc: "Como macOS.", pkg: "whitesur-icon-theme", size: "10 MB" },
        { id: "colloid", name: "Colloid", desc: "Planos, suaves y modernos.", pkg: "colloid-icon-theme", size: "21 MB" },
        { id: "candy", name: "Candy", desc: "Degradados de neón, para gamers.", pkg: "candy-icons-git", size: "2 MB" },
    ]
    readonly property string current: Settings.appearance.iconTheme || "papirus"
    property var installed: ({ papirus: true })
    property string installing: ""

    function preview(id: string): string {
        return Quickshell.shellDir + "/assets/icon-previews/" + id + "-" + (Serp.on ? "pink" : "purple") + ".png";
    }
    function refresh(): void { check.running = true; }
    function choose(id: string): void {
        if (id === current || installing) return;
        const pk = packs.find(p => p.id === id);
        if (!pk) return;
        if (installed[id]) { Settings.set("appearance", "iconTheme", id); return; }
        installing = id;
        Quickshell.execDetached(["notify-send", "-a", "Quantum", "-i", "folder-download", "Descargando los íconos " + pk.name,
                                 "Te pedirá tu contraseña. El escritorio se recarga un segundo al terminar."]);
        install.command = ["pkexec", "pacman", "-S", "--needed", "--noconfirm", pk.pkg];
        install.running = true;
    }

    Component.onCompleted: refresh()
    Process {
        id: check
        // instalado con pacman, o puesto a mano en ~/.local/share/icons o /usr/share/icons
        command: ["sh", "-c", "for x in tela-icon-theme:Tela fluent-icon-theme:Fluent whitesur-icon-theme:WhiteSur colloid-icon-theme:Colloid candy-icons-git:candy-icons; do " +
                  "p=${x%%:*}; d=${x#*:}; if pacman -Q $p >/dev/null 2>&1 || [ -e \"${XDG_DATA_HOME:-$HOME/.local/share}/icons/$d/index.theme\" ] || [ -e /usr/share/icons/$d/index.theme ]; then echo $p; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const inst = { papirus: true };
                for (const pk of root.packs) if (lines.includes(pk.pkg)) inst[pk.id] = true;
                root.installed = inst;
            }
        }
    }
    Process {
        id: install
        onExited: code => {
            const pk = root.packs.find(p => p.id === root.installing);
            if (code === 0 && pk) {
                const inst = Object.assign({}, root.installed); inst[pk.id] = true; root.installed = inst;
                Settings.set("appearance", "iconTheme", pk.id);
            } else if (pk) {
                Quickshell.execDetached(["notify-send", "-a", "Quantum", "-i", "dialog-warning", "No se pudieron descargar los íconos " + pk.name,
                                         "Revisa tu internet e inténtalo de nuevo en Personalizar → Colores y fondo."]);
            }
            root.installing = "";
        }
    }
}
