import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

// Apariencia como en Ajustes del Sistema de macOS (Tahoe): Automático / Claro / Oscuro,
// vidrio (Liquid Glass), color de acento, estilo de íconos, tamaño del texto y esquinas.
ColumnLayout {
    id: page
    spacing: 16

    // los colores de acento de macOS (Multicolor = colores del fondo de pantalla)
    readonly property var accents: [
        { c: "#007AFF", t: I18n.t("Azul") }, { c: "#953D96", t: I18n.t("Morado") }, { c: "#F74F9E", t: I18n.t("Rosa") },
        { c: "#E0383E", t: I18n.t("Rojo") }, { c: "#F7821B", t: I18n.t("Naranja") }, { c: "#FFC600", t: I18n.t("Amarillo") },
        { c: "#62BA46", t: I18n.t("Verde") }, { c: "#989898", t: I18n.t("Grafito") },
    ]
    readonly property string accentNow: Settings.appearance.dynamicColors ? "" : String(Settings.appearance.accent).toUpperCase()
    readonly property bool customAccent: accentNow !== "" && accents.every(a => a.c.toUpperCase() !== accentNow)

    // --------------------------------------------------------- apariencia
    Group {
        title: I18n.t("Apariencia")
        help: Settings.appearance.mode === "auto" ? I18n.t("Automático cambia entre claro y oscuro según la hora.") : ""
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 18
            Repeater {
                model: [{ m: "auto", t: I18n.t("Automático") }, { m: "light", t: I18n.t("Claro") }, { m: "dark", t: I18n.t("Oscuro") }]
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
                            // Automático: mitad derecha oscura
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
    }

    // --------------------------------------------------------- color de acento
    Group {
        help: Settings.appearance.dynamicColors ? I18n.t("Multicolor toma los colores de tu fondo de pantalla.") : ""
        OptionRow {
            title: I18n.t("Color de acento")
            Row {
                spacing: 10
                // Multicolor
                Rectangle {
                    readonly property bool on: Settings.appearance.dynamicColors
                    width: 22; height: 22; radius: 11
                    border.width: on ? 2 : 0
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
                        width: 22; height: 22; radius: 11
                        color: modelData.c
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.15)
                        Rectangle { anchors.centerIn: parent; visible: dot.on; width: 8; height: 8; radius: 4; color: "white" }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.setMany({ appearance: { dynamicColors: false, accent: dot.modelData.c } })
                        }
                    }
                }
            }
        }
        OptionRow {
            advanced: true
            title: I18n.t("Otro color")
            help: I18n.t("Escribe un color en hexadecimal y pulsa Enter.")
            Rectangle {
                implicitWidth: 130; implicitHeight: 28; radius: 7
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : "white"
                border.width: 1; border.color: page.customAccent ? Theme.primary : Theme.alpha(Theme.fg, 0.15)
                Rectangle {
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16; radius: 8
                    color: /^#[0-9a-fA-F]{6}$/.test(hexIn.text) ? hexIn.text : "transparent"
                    border.width: 1; border.color: Theme.alpha(Theme.fg, 0.2)
                }
                TextInput {
                    id: hexIn
                    anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font; font.pixelSize: Theme.textNormal
                    color: Theme.fg
                    maximumLength: 7
                    text: page.customAccent ? page.accentNow : ""
                    validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                    onAccepted: {
                        const t = text.startsWith("#") ? text : "#" + text;
                        if (/^#[0-9a-fA-F]{6}$/.test(t))
                            Settings.setMany({ appearance: { dynamicColors: false, accent: t.toUpperCase() } });
                    }
                    Txt { anchors.verticalCenter: parent.verticalCenter; visible: !hexIn.text && !hexIn.activeFocus; text: "#RRGGBB"; color: Theme.fgMuted }
                }
            }
        }
    }

    // ------------------------------------------------------- vidrio (Liquid Glass)
    Group {
        id: glassG
        title: I18n.t("Vidrio")
        help: I18n.t("Las partes de vidrio dejan ver el fondo desenfocado detrás, como Liquid Glass en macOS.")
        readonly property var parts: [
            { k: "bar", t: I18n.t("Barra de menús") }, { k: "dock", t: I18n.t("Dock") },
            { k: "panels", t: I18n.t("Menús y paneles") }, { k: "windows", t: I18n.t("Ventanas de apps") },
        ]
        Repeater {
            model: glassG.parts
            OptionRow {
                required property var modelData
                title: modelData.t
                Toggle { checked: Settings.appearance.glass[modelData.k]; onToggled: c => Settings.setPath("appearance.glass." + modelData.k, c) }
            }
        }
        OptionRow {
            title: I18n.t("Transparencia")
            Slider {
                implicitWidth: 240
                from: 0.4; to: 1; step: 0.02; live: true
                value: Settings.appearance.panelOpacity
                minText: I18n.t("Transparente"); maxText: I18n.t("Tintado")
                onMoved: v => Settings.set("appearance", "panelOpacity", v)
            }
        }
        OptionRow {
            visible: Settings.appearance.glass.windows
            title: I18n.t("Opacidad de las ventanas")
            Slider {
                implicitWidth: 240
                from: 0.6; to: 1; step: 0.02
                value: Settings.appearance.windowOpacity
                text: Math.round(_shown * 100) + "%"
                onMoved: v => Settings.set("appearance", "windowOpacity", v)
            }
        }
        OptionRow {
            title: I18n.t("Desenfoque detrás")
            help: I18n.t("Consume algo de gráfica.")
            Toggle { checked: Settings.appearance.blur; onToggled: c => Settings.set("appearance", "blur", c) }
        }
    }

    // ------------------------------------------------- estilo de íconos
    Group {
        title: I18n.t("Estilo de íconos")
        help: Icons.installing ? I18n.t("Descargando los íconos… el escritorio se recarga un segundo al terminar.")
                               : I18n.t("Los íconos de las apps y carpetas. Los que no están instalados se descargan (pide tu contraseña).")
        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            columns: page.width > 700 ? 4 : 3
            columnSpacing: 12; rowSpacing: 12
            Repeater {
                model: Icons.packs
                ColumnLayout {
                    id: ic
                    required property var modelData
                    readonly property bool on: Icons.current === modelData.id
                    Layout.fillWidth: true
                    spacing: 5
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 64
                        radius: 9
                        color: Theme.alpha(Theme.fg, 0.04)
                        border.width: ic.on ? 3 : 1
                        border.color: ic.on ? Theme.primary : Theme.alpha(Theme.fg, 0.1)
                        Image {
                            visible: ic.modelData.id !== "mactahoe"
                            anchors.fill: parent; anchors.margins: 8
                            fillMode: Image.PreserveAspectFit
                            source: visible ? Icons.preview(ic.modelData.id) : ""
                            sourceSize: Qt.size(400, 100)
                            asynchronous: true
                        }
                        Row {
                            visible: ic.modelData.id === "mactahoe"
                            anchors.centerIn: parent
                            spacing: 4
                            Repeater {
                                model: ["places/scalable/folder-blue", "apps/scalable/firefox", "apps/scalable/kitty", "apps/scalable/org.gnome.Settings"]
                                Image {
                                    required property string modelData
                                    width: 32; height: 32
                                    source: "file:///usr/share/icons/MacTahoe/" + modelData + ".svg"
                                    sourceSize: Qt.size(64, 64)
                                }
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Icons.choose(ic.modelData.id) }
                    }
                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: ic.modelData.name + (Icons.installing === ic.modelData.id ? " …" : !Icons.installed[ic.modelData.id] ? " ↓" : "")
                        font.pixelSize: Theme.textSmall
                        font.weight: ic.on ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }

    // ------------------------------------------------- texto y esquinas
    Group {
        OptionRow {
            title: I18n.t("Tamaño del texto")
            help: I18n.t("En la barra, los menús, los paneles y esta ventana.")
            Segmented {
                options: [{ v: 0.9, t: I18n.t("Pequeño") }, { v: 1.0, t: I18n.t("Mediano") }, { v: 1.15, t: I18n.t("Grande") }]
                value: Settings.appearance.textScale
                onPicked: v => Settings.set("appearance", "textScale", v)
            }
        }
        OptionRow {
            title: I18n.t("Esquinas")
            help: I18n.t("Qué tan redondeados se ven los paneles, menús y tarjetas.")
            Segmented {
                options: [{ v: "sharp", t: I18n.t("Rectas") }, { v: "soft", t: I18n.t("Suaves") }, { v: "round", t: I18n.t("Redondeadas") }]
                value: Settings.windows.corners
                onPicked: v => Settings.set("windows", "corners", v)
            }
        }
    }
}
