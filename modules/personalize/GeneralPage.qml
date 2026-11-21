import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// «General»: apariencia (tema, color de acento) y barras de desplazamiento.
ColumnLayout {
    id: page

    required property var host
    spacing: 14

    readonly property var accents: ["#007AFF", "#5856D6", "#F74F9E", "#E0383E", "#F7821B", "#FFC600", "#62BA46", "#989898"]
    readonly property string accentNow: Settings.appearance.dynamicColors ? "" : String(Settings.appearance.accent).toUpperCase()

    // ---- tema: Automático / Claro / Oscuro + color de acento
    Group {
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 14
            spacing: 28
            Repeater {
                model: [{ m: "auto", t: I18n.t("Auto") }, { m: "light", t: I18n.t("Light") }, { m: "dark", t: I18n.t("Dark") }]
                ColumnLayout {
                    id: mc
                    required property var modelData
                    readonly property bool on: Settings.appearance.mode === modelData.m
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 112; implicitHeight: 72
                        radius: 8
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
                        Layout.alignment: Qt.AlignHCenter
                        text: mc.modelData.t
                        font.pixelSize: Theme.textSmall + 1
                        font.weight: mc.on ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
        // Accent color: centrado, con la etiqueta a la izquierda de los puntos
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 14
            Layout.bottomMargin: 14
            spacing: 14
            Txt { text: I18n.t("Accent color:") }
            Row {
                spacing: 12
                Repeater {
                    model: page.accents
                    Rectangle {
                        id: dot
                        required property string modelData
                        readonly property bool on: page.accentNow === modelData.toUpperCase()
                        width: 22; height: 22; radius: 11
                        color: modelData
                        border.width: dot.on ? 2 : 0
                        border.color: Theme.alpha(Theme.fg, 0.7)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.setMany({ appearance: { dynamicColors: false, accent: dot.modelData } })
                        }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 14; Layout.rightMargin: 14; implicitHeight: 1; color: Theme.alpha(Theme.fg, 0.08) }
        // Appearance: etiqueta + campo
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            Layout.bottomMargin: 12
            spacing: 14
            Txt { text: I18n.t("Appearance") }
            Choice {
                options: [{ v: false, t: I18n.t("Accent Color") }, { v: true, t: I18n.t("Multicolor (wallpaper)") }]
                value: Settings.appearance.dynamicColors
                onPicked: v => Settings.set("appearance", "dynamicColors", v)
            }
        }
    }

    // ---- opciones: sin recuadro, casilla redonda a la izquierda e interruptor a la derecha
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        CheckRow {
            label: I18n.t("Automatically switch appearance")
            on: Settings.appearance.mode === "auto"
            onChanged: v => Settings.set("appearance", "mode", v ? "auto" : "light")
        }
        CheckRow {
            label: I18n.t("Use darker colors for menu bar and Dock")
            on: Settings.appearance.darkerBars
            onChanged: v => Settings.set("appearance", "darkerBars", v)
        }
        CheckRow {
            label: I18n.t("Allow wallpaper tinting in windows")
            withSwitch: false
            on: Settings.appearance.wallpaperTint
            onChanged: v => Settings.set("appearance", "wallpaperTint", v)
        }
    }

    // ---- barras de desplazamiento (radios como macOS)
    Group {
        OptionRow {
            title: I18n.t("Show scroll bars")
            Radios {
                options: [{ v: "always", t: I18n.t("Always") }, { v: "scrolling", t: I18n.t("When scrolling") }]
                value: Settings.appearance.scrollBars
                onPicked: v => Settings.set("appearance", "scrollBars", v)
            }
        }
        OptionRow {
            title: I18n.t("Click in the scroll bar to")
            Radios {
                options: [{ v: false, t: I18n.t("Jump to the next page") }, { v: true, t: I18n.t("Jump to the spot that's clicked") }]
                value: Settings.appearance.scrollJump
                onPicked: v => Settings.set("appearance", "scrollJump", v)
            }
        }
    }
}
