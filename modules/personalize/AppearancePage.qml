import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Apariencia como en Ajustes del Sistema de macOS (Tahoe): Automático / Claro / Oscuro,
// vidrio (Liquid Glass), color de acento, estilo de íconos, tamaño del texto y esquinas.
ColumnLayout {
    id: page
    spacing: 28

    // los colores de acento de macOS (Multicolor = colores del fondo de pantalla)
    readonly property var accents: [
        { c: "#007AFF", t: I18n.t("Azul") }, { c: "#953D96", t: I18n.t("Morado") }, { c: "#F74F9E", t: I18n.t("Rosa") },
        { c: "#E0383E", t: I18n.t("Rojo") }, { c: "#F7821B", t: I18n.t("Naranja") }, { c: "#FFC600", t: I18n.t("Amarillo") },
        { c: "#62BA46", t: I18n.t("Verde") }, { c: "#989898", t: I18n.t("Grafito") },
    ]
    readonly property string accentNow: Settings.appearance.dynamicColors ? "" : String(Settings.appearance.accent).toUpperCase()
    readonly property bool customAccent: accentNow !== "" && accents.every(a => a.c.toUpperCase() !== accentNow)

    // ---- recuadro principal, como Ajustes del Sistema de macOS
    Group {
        // Apariencia: etiqueta a la izquierda, tres tarjetas a la derecha
        OptionRow {
            title: I18n.t("Appearance")
            Row {
                spacing: 14
                Repeater {
                    model: [{ m: "light", t: I18n.t("Light") }, { m: "dark", t: I18n.t("Dark") }, { m: "auto", t: I18n.t("Auto") }]
                    Column {
                        id: mc
                        required property var modelData
                        readonly property bool on: Settings.appearance.mode === modelData.m
                        spacing: 4
                        topPadding: 8
                        bottomPadding: 4
                        Rectangle {
                            width: 76; height: 50
                            radius: 7
                            color: "transparent"
                            border.width: mc.on ? 3 : 1
                            border.color: mc.on ? Theme.primary : Theme.alpha(Theme.fg, 0.15)
                            Item {
                                anchors.fill: parent
                                anchors.margins: 3
                                clip: true
                                MiniDesktop {
                                    anchors.fill: parent
                                    v: { const s = Settings.visualState(); s.appearance.mode = mc.modelData.m === "auto" ? "light" : mc.modelData.m; return s; }
                                }
                                Item {
                                    visible: mc.modelData.m === "auto"
                                    x: parent.width / 2
                                    width: parent.width / 2
                                    height: parent.height
                                    clip: true
                                    MiniDesktop {
                                        x: -parent.x
                                        width: parent.parent.width
                                        height: parent.height
                                        v: { const s = Settings.visualState(); s.appearance.mode = "dark"; return s; }
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Settings.set("appearance", "mode", mc.modelData.m) }
                        }
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: mc.modelData.t
                            font.pixelSize: Theme.textSmall
                            font.weight: mc.on ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
        }
        OptionRow {
            visible: Settings.appearance.mode === "auto"
            title: I18n.t("Claro desde")
            Choice {
                options: ["05:00", "06:00", "07:00", "08:00", "09:00"].map(t => ({ v: t, t: t }))
                value: Settings.appearance.lightFrom
                onPicked: v => Settings.set("appearance", "lightFrom", v)
            }
        }
        OptionRow {
            visible: Settings.appearance.mode === "auto"
            title: I18n.t("Oscuro desde")
            Choice {
                options: ["16:00", "17:00", "18:00", "19:00", "20:00", "21:00"].map(t => ({ v: t, t: t }))
                value: Settings.appearance.lightTo
                onPicked: v => Settings.set("appearance", "lightTo", v)
            }
        }
        // Accent color: puntos, con «Multicolor» debajo del primero
        OptionRow {
            title: I18n.t("Accent color")
            Column {
                spacing: 3
                topPadding: 4
                bottomPadding: 2
                Row {
                    spacing: 10
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        border.width: Settings.appearance.dynamicColors ? 2 : 0
                        border.color: Theme.fg
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#FF3B30" }
                            GradientStop { position: 0.35; color: "#FFCC00" }
                            GradientStop { position: 0.65; color: "#34C759" }
                            GradientStop { position: 1; color: "#007AFF" }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Settings.set("appearance", "dynamicColors", true) }
                    }
                    Repeater {
                        model: page.accents
                        Rectangle {
                            id: dot
                            required property var modelData
                            readonly property bool on: page.accentNow === modelData.c.toUpperCase()
                            width: 18; height: 18; radius: 9
                            color: modelData.c
                            border.width: 1
                            border.color: Qt.rgba(0, 0, 0, 0.15)
                            Rectangle { anchors.centerIn: parent; visible: dot.on; width: 7; height: 7; radius: 3.5; color: "white" }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Settings.setMany({ appearance: { dynamicColors: false, accent: dot.modelData.c } })
                            }
                        }
                    }
                }
                Txt { text: I18n.t("Multicolor"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall - 1 }
            }
        }
        OptionRow {
            title: I18n.t("Allow wallpaper tinting in windows")
            Toggle { checked: Settings.appearance.wallpaperTint; onToggled: c => Settings.set("appearance", "wallpaperTint", c) }
        }
    }

    // ---- barras de desplazamiento: título arriba y radios apilados debajo (como macOS)
    Group {
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 14
            spacing: 8
            Txt { text: I18n.t("Show scroll bars") }
            Radios {
                vertical: true
                rowSpacing: 8
                options: [{ v: "auto", t: I18n.t("Automatically based on mouse or trackpad") }, { v: "scrolling", t: I18n.t("When scrolling") }, { v: "always", t: I18n.t("Always") }]
                value: Settings.appearance.scrollBars
                onPicked: v => Settings.set("appearance", "scrollBars", v)
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; Layout.bottomMargin: 12; implicitHeight: 1; color: Theme.alpha(Theme.fg, 0.08) }
            Txt { text: I18n.t("Click in the scroll bar to") }
            Radios {
                vertical: true
                rowSpacing: 8
                options: [{ v: false, t: I18n.t("Jump to the next page") }, { v: true, t: I18n.t("Jump to the spot that's clicked") }]
                value: Settings.appearance.scrollJump
                onPicked: v => Settings.set("appearance", "scrollJump", v)
            }
        }
    }

    // botón «?» abajo a la derecha
    Rectangle {
        Layout.alignment: Qt.AlignRight
        implicitWidth: 22; implicitHeight: 22; radius: 11
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : "white"
        border.width: 1; border.color: Theme.alpha(Theme.fg, 0.15)
        Txt { anchors.centerIn: parent; text: "?"; font.pixelSize: Theme.textSmall; font.weight: Font.DemiBold }
    }
}
