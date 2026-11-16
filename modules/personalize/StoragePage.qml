import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// General → Almacenamiento (como en macOS): barra de colores con lo que ocupa cada
// cosa y la lista de categorías con su tamaño y una acción (vaciar papelera, limpiar…).
ColumnLayout {
    id: page
    spacing: 16

    property real total: 0
    property real used: 0
    property var sizes: ({})
    property bool loading: true

    readonly property var cats: [
        { k: "apps", t: I18n.t("Aplicaciones y sistema"), i: "apps", c: "#FF3B30" },
        { k: "docs", t: I18n.t("Documentos"), i: "description", c: "#FF9500" },
        { k: "downloads", t: I18n.t("Descargas"), i: "download", c: "#FFCC00" },
        { k: "pictures", t: I18n.t("Fotos"), i: "photo_library", c: "#34C759" },
        { k: "videos", t: I18n.t("Videos"), i: "movie", c: "#5AC8FA" },
        { k: "music", t: I18n.t("Música"), i: "music_note", c: "#AF52DE" },
        { k: "pkg", t: I18n.t("Caché de paquetes"), i: "inventory_2", c: "#8E8E93" },
        { k: "cache", t: I18n.t("Caché de apps"), i: "cached", c: "#A2845E" },
        { k: "trash", t: I18n.t("Papelera"), i: "delete", c: "#636366" },
    ]
    function gb(b: real): string {
        return b >= 1e9 ? (b / 1e9).toFixed(b >= 1e11 ? 0 : 1) + " GB" : b >= 1e6 ? Math.round(b / 1e6) + " MB" : b > 0 ? Math.round(b / 1e3) + " KB" : "0 KB";
    }
    function refresh(): void { loading = true; du.running = true; }
    Component.onCompleted: refresh()

    Process {
        id: du
        command: ["sh", "-c", `df -B1 --output=size,used / | tail -1 | awk '{print "total " $1; print "used " $2}'
s() { [ -d "$2" ] && echo "$1 $(du -sxb "$2" 2>/dev/null | tail -1 | cut -f1)"; }
s docs "$(xdg-user-dir DOCUMENTS)"; s downloads "$(xdg-user-dir DOWNLOAD)"; s pictures "$(xdg-user-dir PICTURES)"
s videos "$(xdg-user-dir VIDEOS)"; s music "$(xdg-user-dir MUSIC)"; s cache "$HOME/.cache"; s trash "$HOME/.local/share/Trash"
s pkg /var/cache/pacman/pkg; s apps /usr`]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) {
                    const p = l.trim().split(" ");
                    if (p.length === 2) o[p[0]] = Number(p[1]) || 0;
                }
                page.total = o.total ?? 0;
                page.used = o.used ?? 0;
                page.sizes = o;
                page.loading = false;
            }
        }
    }
    Process { id: act; onExited: page.refresh() }
    function run(cmd: string): void { act.command = ["sh", "-c", cmd]; act.running = true; }

    Group {
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 12
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Txt { text: I18n.t("Disco del sistema"); font.weight: Font.DemiBold; Layout.fillWidth: true }
                Txt {
                    text: page.total > 0 ? page.gb(page.used) + " " + I18n.t("usados de") + " " + page.gb(page.total) : "—"
                    color: Theme.fgMuted
                }
            }
            // barra: cada categoría con su color, el resto usado en gris oscuro y lo libre en gris claro
            Rectangle {
                id: bar
                Layout.fillWidth: true
                implicitHeight: 22
                radius: 6
                color: Theme.alpha(Theme.fg, 0.1)
                clip: true
                Row {
                    height: parent.height
                    Repeater {
                        model: page.cats
                        Rectangle {
                            required property var modelData
                            width: page.total > 0 ? bar.width * (page.sizes[modelData.k] ?? 0) / page.total : 0
                            height: bar.height
                            color: modelData.c
                        }
                    }
                    Rectangle {
                        readonly property real known: page.cats.reduce((a, c) => a + (page.sizes[c.k] ?? 0), 0)
                        width: page.total > 0 ? bar.width * Math.max(0, page.used - known) / page.total : 0
                        height: bar.height
                        color: Theme.alpha(Theme.fg, 0.35)
                    }
                }
            }
            Txt {
                text: page.loading ? I18n.t("Calculando…") : page.gb(Math.max(0, page.total - page.used)) + " " + I18n.t("disponibles")
                color: Theme.fgMuted
                font.pixelSize: Theme.textSmall
            }
        }
    }

    Group {
        title: I18n.t("Recomendaciones")
        OptionRow {
            title: I18n.t("Vaciar la papelera")
            help: I18n.t("Borra para siempre lo que hay en la papelera") + " (" + page.gb(page.sizes.trash ?? 0) + ")."
            icon: "delete"; iconColor: "#636366"
            PillButton { text: I18n.t("Vaciar…"); implicitHeight: 28; enabled_: (page.sizes.trash ?? 0) > 0; onClicked: page.run("gio trash --empty") }
        }
        OptionRow {
            title: I18n.t("Limpiar la caché de paquetes")
            help: I18n.t("Quita las versiones viejas de los paquetes descargados (se abre una terminal).") + " (" + page.gb(page.sizes.pkg ?? 0) + ")"
            icon: "inventory_2"; iconColor: "#8E8E93"
            PillButton {
                text: I18n.t("Limpiar…"); implicitHeight: 28
                onClicked: Quickshell.execDetached(["kitty", "sh", "-c", "if command -v paccache >/dev/null; then sudo paccache -rk1; else sudo pacman -Sc; fi; printf '\\nPulsa Enter para cerrar.'; read _"])
            }
        }
    }

    Group {
        title: I18n.t("Categorías")
        Repeater {
            model: page.cats
            OptionRow {
                required property var modelData
                title: modelData.t
                icon: modelData.i
                iconColor: modelData.c
                Txt { text: page.loading ? "…" : page.gb(page.sizes[modelData.k] ?? 0); color: Theme.fgMuted }
            }
        }
    }
}
