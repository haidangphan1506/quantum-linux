import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Pantalla bloqueada como en macOS: cuándo empieza el salvapantallas, bloquear ahora y,
// propio de Quantum, qué tarjetas se ven a cada lado y en qué orden.
ColumnLayout {
    id: page

    spacing: 16

    readonly property var info: ({
        weather: { k: "#32ADE6", t: I18n.t("Clima"), h: I18n.t("Temperatura y pronóstico de hoy"), i: "partly_cloudy_day" },
        fetch: { k: "#3A3A3C", t: I18n.t("Ficha del sistema"), h: I18n.t("Tu PC al estilo «fetch» y la paleta"), i: "terminal" },
        media: { k: "#FF2D55", t: I18n.t("Música"), h: I18n.t("Lo que suena, con controles"), i: "music_note" },
        stats: { k: "#34C759", t: I18n.t("Uso del sistema"), h: I18n.t("CPU, temperatura, RAM y disco"), i: "monitoring" },
        notifs: { k: "#FF3B30", t: I18n.t("Notificaciones"), h: I18n.t("Avisos agrupados por app"), i: "notifications" },
        calendar: { k: "#FF9500", t: I18n.t("Calendario"), h: I18n.t("El mes con el día de hoy"), i: "calendar_month" },
    })
    readonly property var all: ["weather", "fetch", "media", "stats", "notifs", "calendar"]
    readonly property var unused: all.filter(k => Settings.lock.left.indexOf(k) < 0 && Settings.lock.right.indexOf(k) < 0)

    function setSide(side: string, list: var): void { Settings.setPath("lock." + side, list); }
    function move(side: string, i: int, d: int): void {
        const l = Array.from(Settings.lock[side]);
        const j = i + d;
        if (j < 0 || j >= l.length) return;
        [l[i], l[j]] = [l[j], l[i]];
        setSide(side, l);
    }
    function remove(side: string, i: int): void {
        const l = Array.from(Settings.lock[side]);
        l.splice(i, 1);
        setSide(side, l);
    }
    function swapSide(side: string, i: int): void {
        const other = side === "left" ? "right" : "left";
        const a = Array.from(Settings.lock[side]), b = Array.from(Settings.lock[other]);
        b.push(a.splice(i, 1)[0]);
        Settings.setMany({ lock: { [side]: a, [other]: b } });
    }
    function add(k: string, side: string): void { setSide(side, Array.from(Settings.lock[side]).concat([k])); }

    Group {
        OptionRow {
            title: I18n.t("Iniciar el salvapantallas cuando esté inactivo")
            icon: "hourglass_top"
            iconColor: "#8E8E93"
            help: I18n.t("No aparece mientras ves un video o juegas a pantalla completa.")
            Choice {
                options: [{ v: 0, t: I18n.t("Nunca") }, { v: 60, t: I18n.t("Tras 1 minuto") }, { v: 120, t: I18n.t("Tras 2 minutos") },
                          { v: 300, t: I18n.t("Tras 5 minutos") }, { v: 600, t: I18n.t("Tras 10 minutos") }, { v: 1200, t: I18n.t("Tras 20 minutos") },
                          { v: 1800, t: I18n.t("Tras 30 minutos") }, { v: 3600, t: I18n.t("Tras 1 hora") }, { v: 7200, t: I18n.t("Tras 2 horas") }]
                value: Settings.screensaver.enabled ? Settings.screensaver.timeout : 0
                onPicked: v => Settings.setMany({ screensaver: v === 0 ? { enabled: false } : { enabled: true, timeout: v } })
            }
        }
        OptionRow {
            title: I18n.t("Salvapantallas")
            help: I18n.t("Lluvia de caracteres estilo Matrix. Mueve el ratón o pulsa una tecla para salir.")
            icon: "slideshow"
            iconColor: "#34C759"
            PillButton { text: I18n.t("Ver salvapantallas"); implicitHeight: 28; onClicked: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "screensaver", "start"]) }
        }
        OptionRow {
            title: I18n.t("Bloquear la pantalla")
            icon: "lock"
            iconColor: "#3A3A3C"
            help: I18n.t("También con Super + L.")
            RowLayout {
                spacing: 8
                PillButton { text: I18n.t("Vista previa"); implicitHeight: 28; onClicked: Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "lock", "preview"]) }
                PillButton { text: I18n.t("Bloquear ahora"); implicitHeight: 28; onClicked: Shell.lock() }
            }
        }
        NavRow {
            title: I18n.t("Vista previa de las notificaciones")
            icon: "notifications"
            iconColor: "#FF3B30"
            value: Settings.lock.showNotifContent ? I18n.t("Siempre") : I18n.t("Al desbloquear")
            onClicked: Shell.settingsGo("notifications")
        }
    }

    // columnas (una lista por lado, filas como en Ajustes del Sistema de macOS)
    Repeater {
        model: [{ s: "left", t: I18n.t("Lado izquierdo") }, { s: "right", t: I18n.t("Lado derecho") }]
        Group {
            id: sideGroup
            required property var modelData
            required property int index
            title: modelData.t
            help: index === 0 ? I18n.t("Ordénalas con las flechas, pásalas al otro lado o quítalas. La última de cada lado ocupa el espacio que sobra.") : ""
            OptionRow {
                visible: Settings.lock[sideGroup.modelData.s].length === 0
                title: I18n.t("Sin tarjetas")
                dim: true
            }
            Repeater {
                model: Settings.lock[sideGroup.modelData.s]
                OptionRow {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property var it: page.info[modelData] ?? { t: modelData, h: "", i: "widgets", k: "#8E8E93" }
                    title: it.t
                    help: it.h
                    icon: it.i
                    iconColor: it.k
                    RowLayout {
                        spacing: 2
                        IconButton { icon: "arrow_upward"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; opacity: row.index > 0 ? 1 : 0.3; onClicked: page.move(sideGroup.modelData.s, row.index, -1) }
                        IconButton { icon: "arrow_downward"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; opacity: row.index < Settings.lock[sideGroup.modelData.s].length - 1 ? 1 : 0.3; onClicked: page.move(sideGroup.modelData.s, row.index, 1) }
                        IconButton { icon: sideGroup.modelData.s === "left" ? "arrow_forward" : "arrow_back"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; onClicked: page.swapSide(sideGroup.modelData.s, row.index) }
                        IconButton { icon: "close"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; onClicked: page.remove(sideGroup.modelData.s, row.index) }
                    }
                }
            }
        }
    }

    // tarjetas sin usar
    Group {
        shown: page.unused.length > 0
        title: I18n.t("Agregar")
        Repeater {
            model: page.unused
            OptionRow {
                id: addRow
                required property string modelData
                readonly property var it: page.info[modelData]
                title: it.t
                help: it.h
                icon: it.i
                iconColor: it.k
                RowLayout {
                    spacing: 8
                    PillButton { text: I18n.t("Lado izquierdo"); implicitHeight: 28; onClicked: page.add(addRow.modelData, "left") }
                    PillButton { text: I18n.t("Lado derecho"); implicitHeight: 28; onClicked: page.add(addRow.modelData, "right") }
                }
            }
        }
    }

    Group {
        title: I18n.t("Clima")
        OptionRow {
            title: I18n.t("Ciudad del clima")
            icon: "partly_cloudy_day"
            iconColor: "#32ADE6"
            help: I18n.t("Déjala vacía para usar tu ubicación aproximada (por tu conexión).")
            Rectangle {
                implicitWidth: 240; implicitHeight: 40; radius: 20
                color: Theme.surfaceHigh
                border.width: cityIn.activeFocus ? 2 : 1
                border.color: cityIn.activeFocus ? Theme.primary : Theme.alpha(Theme.fg, 0.1)
                TextInput {
                    id: cityIn
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font; font.pixelSize: Theme.textNormal
                    color: Theme.fg
                    clip: true
                    text: Settings.lock.city
                    onEditingFinished: if (text !== Settings.lock.city) Settings.setPath("lock.city", text.trim())
                    Txt { anchors.verticalCenter: parent.verticalCenter; visible: !cityIn.text && !cityIn.activeFocus; text: I18n.t("Automática"); color: Theme.fgMuted }
                }
            }
        }
    }
}
