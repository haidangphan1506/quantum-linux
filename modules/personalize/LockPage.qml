import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components

// Pantalla de bloqueo: qué tarjetas se ven a cada lado y en qué orden.
ColumnLayout {
    id: page

    spacing: 16

    readonly property var info: ({
        weather: { t: "Clima", h: "Temperatura y pronóstico de hoy", i: "partly_cloudy_day" },
        fetch: { t: "Ficha del sistema", h: "Tu PC al estilo «fetch» y la paleta", i: "terminal" },
        media: { t: "Música", h: "Lo que suena, con controles", i: "music_note" },
        stats: { t: "Uso del sistema", h: "CPU, temperatura, RAM y disco", i: "monitoring" },
        notifs: { t: "Notificaciones", h: "Avisos agrupados por app", i: "notifications" },
        calendar: { t: "Calendario", h: "El mes con el día de hoy", i: "calendar_month" },
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

    // vista previa real
    Group {
        title: "Así se ve"
        help: "Abre la pantalla de bloqueo de verdad, sin bloquear la sesión. Sal con Esc."
        icon: "lock"
        RowLayout {
            spacing: 10
            PillButton { text: "Ver pantalla de bloqueo"; icon: "visibility"; primary: true; onClicked: Quickshell.execDetached(["qs", "-c", "quantum", "ipc", "call", "lock", "preview"]) }
            PillButton { text: "Bloquear ahora"; icon: "lock"; onClicked: Shell.lock() }
        }
    }

    // columnas
    Group {
        title: "Tarjetas"
        help: "Ordénalas con las flechas, pásalas al otro lado o quítalas. La última de cada lado ocupa el espacio que sobra."
        icon: "dashboard_customize"

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: [{ s: "left", t: "Lado izquierdo" }, { s: "right", t: "Lado derecho" }]
                ColumnLayout {
                    id: colSide
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8
                    Txt { text: colSide.modelData.t; font.weight: Font.Bold; color: Theme.fgMuted }
                    Repeater {
                        model: Settings.lock[colSide.modelData.s]
                        Rectangle {
                            id: row
                            required property string modelData
                            required property int index
                            readonly property var it: page.info[modelData] ?? { t: modelData, h: "", i: "widgets" }
                            Layout.fillWidth: true
                            implicitHeight: 62
                            radius: Theme.radius
                            color: Theme.surfaceHigh
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 6
                                spacing: 10
                                Rectangle {
                                    implicitWidth: 36; implicitHeight: 36; radius: 11
                                    color: Theme.alpha(Theme.primary, 0.14)
                                    Icon { anchors.centerIn: parent; text: row.it.i; size: 20; color: Theme.primary }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Txt { Layout.fillWidth: true; text: row.it.t; font.weight: Font.DemiBold }
                                    Txt { Layout.fillWidth: true; text: row.it.h; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                                }
                                IconButton { icon: "arrow_upward"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; opacity: row.index > 0 ? 1 : 0.3; onClicked: page.move(colSide.modelData.s, row.index, -1) }
                                IconButton { icon: "arrow_downward"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; opacity: row.index < Settings.lock[colSide.modelData.s].length - 1 ? 1 : 0.3; onClicked: page.move(colSide.modelData.s, row.index, 1) }
                                IconButton { icon: colSide.modelData.s === "left" ? "arrow_forward" : "arrow_back"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; onClicked: page.swapSide(colSide.modelData.s, row.index) }
                                IconButton { icon: "close"; iconSize: 18; implicitWidth: 32; implicitHeight: 32; onClicked: page.remove(colSide.modelData.s, row.index) }
                            }
                        }
                    }
                    Txt {
                        visible: Settings.lock[colSide.modelData.s].length === 0
                        text: "Sin tarjetas"
                        color: Theme.fgMuted
                    }
                }
            }
        }

        // tarjetas sin usar
        Txt { visible: page.unused.length > 0; text: "Agregar"; font.weight: Font.Bold; color: Theme.fgMuted }
        Flow {
            visible: page.unused.length > 0
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: page.unused
                Rectangle {
                    id: chip
                    required property string modelData
                    readonly property var it: page.info[modelData]
                    width: chipRow.implicitWidth + 20; height: 44; radius: 22
                    color: Theme.surfaceHigh
                    border.width: 1; border.color: Theme.alpha(Theme.fg, 0.1)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; text: chip.it.i; size: 18; color: Theme.primary }
                        Txt { anchors.verticalCenter: parent.verticalCenter; text: chip.it.t; font.weight: Font.DemiBold }
                        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "arrow_back"; iconSize: 16; implicitWidth: 30; implicitHeight: 30; onClicked: page.add(chip.modelData, "left") }
                        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "arrow_forward"; iconSize: 16; implicitWidth: 30; implicitHeight: 30; onClicked: page.add(chip.modelData, "right") }
                    }
                }
            }
        }
    }

    Group {
        title: "Privacidad y clima"
        icon: "shield_person"
        OptionRow {
            title: "Mostrar el contenido de las notificaciones"
            help: "Si está apagado, solo se ve qué app te avisó (nadie puede leer tus mensajes con la pantalla bloqueada)."
            Toggle { checked: Settings.lock.showNotifContent; onToggled: c => Settings.setPath("lock.showNotifContent", c) }
        }
        OptionRow {
            title: "Ciudad del clima"
            help: "Déjala vacía para usar tu ubicación aproximada (por tu conexión)."
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
                    Txt { anchors.verticalCenter: parent.verticalCenter; visible: !cityIn.text && !cityIn.activeFocus; text: "Automática"; color: Theme.fgMuted }
                }
            }
        }
    }
}
