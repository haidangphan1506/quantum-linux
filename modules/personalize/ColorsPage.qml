import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Colores y fondo: claro/oscuro, color de acento, fondo de pantalla y efectos.
ColumnLayout {
    id: page

    spacing: 16
    property var walls: []
    readonly property var accents: ["#6A5CFF", "#4FD8FF", "#3B82F6", "#22C58B", "#8BC34A", "#FFB547", "#FF8A3D", "#FF4F7B", "#E040FB", "#9AA0A6"]
    readonly property string accentNow: Settings.appearance.dynamicColors ? "" : String(Settings.appearance.accent).toUpperCase()
    readonly property bool customAccent: accentNow !== "" && accents.map(a => a.toUpperCase()).indexOf(accentNow) < 0

    Component.onCompleted: lister.running = true
    Process {
        id: lister
        command: ["sh", "-c", "for d in /usr/share/backgrounds/quantum \"$HOME/Imágenes/Fondos\" \"$HOME/Pictures/Wallpapers\" \"$(dirname \"$1\")\"; do " +
                  "[ -d \"$d\" ] && find \"$d\" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\); done | sort -u",
                  "sh", Settings.appearance.wallpaper]
        stdout: StdioCollector { onStreamFinished: page.walls = text.trim().split("\n").filter(s => s.length) }
    }

    function thumb(path: string): string {
        const dir = path.substring(0, path.lastIndexOf("/"));
        const name = path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
        return "file://" + dir + "/thumbs/" + name + ".jpg";
    }
    // Se guarda desde el shell (al instante) y quantum-theme recalcula los colores.
    function setWallpaper(path: string): void {
        Settings.set("appearance", "wallpaper", path);
    }

    // ------------------------------------------------------------- modo
    Group {
        title: "Modo"
        help: "El color general de las ventanas, menús y paneles."
        icon: "contrast"
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Repeater {
                model: [{ m: "dark", t: "Oscuro", h: "Descansa la vista de noche" }, { m: "light", t: "Claro", h: "Ideal con mucha luz" }]
                ChoiceCard {
                    id: mc
                    required property var modelData
                    title: modelData.t
                    help: modelData.h
                    selected: Settings.appearance.mode === modelData.m
                    previewHeight: 100
                    onClicked: Settings.set("appearance", "mode", modelData.m)
                    MiniDesktop {
                        anchors.fill: parent
                        v: { const s = Settings.visualState(); s.appearance.mode = mc.modelData.m; return s; }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------- acento
    Group {
        title: "Color de acento"
        help: "Se usa en botones, selecciones e indicadores de todo el sistema."
        icon: "palette"

        Flow {
            Layout.fillWidth: true
            spacing: 12

            // colores del fondo de pantalla
            Rectangle {
                id: dyn
                readonly property bool on: Settings.appearance.dynamicColors
                width: dynRow.implicitWidth + 28
                height: 44
                radius: 22
                color: on ? Theme.primaryContainer : dynArea.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
                border.width: on ? 0 : 1
                border.color: Theme.alpha(Theme.fg, 0.1)
                Row {
                    id: dynRow
                    anchors.centerIn: parent
                    spacing: 8
                    Icon { anchors.verticalCenter: parent.verticalCenter; text: "wallpaper"; size: 18; fill: 1; color: dyn.on ? Theme.primaryContainerFg : Theme.primary }
                    Txt { anchors.verticalCenter: parent.verticalCenter; text: "Del fondo de pantalla"; font.weight: Font.DemiBold; color: dyn.on ? Theme.primaryContainerFg : Theme.fg }
                }
                MouseArea {
                    id: dynArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Settings.set("appearance", "dynamicColors", true)
                }
            }

            Repeater {
                model: page.accents
                Rectangle {
                    id: dot
                    required property string modelData
                    readonly property bool on: page.accentNow === modelData.toUpperCase()
                    width: 44; height: 44; radius: 22
                    color: "transparent"
                    border.width: on ? 3 : 0
                    border.color: Theme.fg
                    Rectangle {
                        anchors.centerIn: parent
                        width: dot.on ? 32 : dotArea.containsMouse ? 38 : 36
                        height: width
                        radius: width / 2
                        color: dot.modelData
                        Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
                        Icon { anchors.centerIn: parent; visible: dot.on; text: "check"; size: 18; color: "white" }
                    }
                    MouseArea {
                        id: dotArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.setMany({ appearance: { dynamicColors: false, accent: dot.modelData } })
                    }
                }
            }

            // color a mano (hex)
            Rectangle {
                width: hexRow.implicitWidth + 24
                height: 44
                radius: 22
                color: Theme.surfaceHigh
                border.width: hexIn.activeFocus || page.customAccent ? 2 : 1
                border.color: hexIn.activeFocus || page.customAccent ? Theme.primary : Theme.alpha(Theme.fg, 0.1)
                Row {
                    id: hexRow
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11
                        color: /^#[0-9a-fA-F]{6}$/.test(hexIn.text) ? hexIn.text : Theme.surfaceHighest
                        border.width: 1; border.color: Theme.alpha(Theme.fg, 0.2)
                    }
                    TextInput {
                        id: hexIn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 90
                        text: page.customAccent ? page.accentNow : ""
                        font.family: Theme.font
                        font.pixelSize: Theme.textNormal
                        color: Theme.fg
                        maximumLength: 7
                        validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                        onAccepted: {
                            const t = text.startsWith("#") ? text : "#" + text;
                            if (/^#[0-9a-fA-F]{6}$/.test(t))
                                Settings.setMany({ appearance: { dynamicColors: false, accent: t.toUpperCase() } });
                        }
                        Txt { visible: !hexIn.text && !hexIn.activeFocus; text: "#Otro color"; color: Theme.fgMuted }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- fondos
    Group {
        title: "Fondo de pantalla"
        help: "Elige uno de Quantum o una imagen tuya."
        icon: "wallpaper"

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(2, Math.floor((page.width - 36) / 190))
            columnSpacing: 12
            rowSpacing: 12
            // Fondo vivo: el átomo de Quantum animado
            Rectangle {
                id: liveTile
                readonly property bool on: Settings.appearance.wallpaper === "quantum:live"
                Layout.fillWidth: true
                Layout.preferredHeight: width * 9 / 16
                radius: Theme.radius
                color: "#0B0820"
                border.width: on ? 3 : 0
                border.color: Theme.primary
                clip: true
                LiveWallpaper {
                    anchors.fill: parent
                    anchors.margins: liveTile.on ? 3 : 0
                    running: liveArea.containsMouse || liveTile.on
                }
                Rectangle {
                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
                    width: liveT.implicitWidth + 16; height: 24; radius: 12
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Txt { id: liveT; anchors.centerIn: parent; text: "Fondo vivo"; font.pixelSize: Theme.textSmall; font.weight: Font.Bold; color: "white" }
                }
                Rectangle {
                    visible: liveTile.on
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                    width: 26; height: 26; radius: 13; color: Theme.primary
                    Icon { anchors.centerIn: parent; text: "check"; size: 18; color: Theme.primaryFg }
                }
                MouseArea {
                    id: liveArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setWallpaper("quantum:live")
                }
            }
            Repeater {
                model: page.walls
                Rectangle {
                    id: tile
                    required property string modelData
                    readonly property bool on: modelData === Settings.appearance.wallpaper
                    Layout.fillWidth: true
                    Layout.preferredHeight: width * 9 / 16
                    radius: Theme.radius
                    color: Theme.surfaceHigh
                    border.width: on ? 3 : 0
                    border.color: Theme.primary
                    clip: true
                    scale: wArea.containsMouse ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    Image {
                        anchors.fill: parent
                        anchors.margins: tile.on ? 3 : 0
                        source: page.thumb(tile.modelData)
                        sourceSize: Qt.size(400, 225)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        onStatusChanged: if (status === Image.Error) source = "file://" + tile.modelData
                    }
                    Rectangle {
                        visible: tile.on
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                        width: 26; height: 26; radius: 13; color: Theme.primary
                        Icon { anchors.centerIn: parent; text: "check"; size: 18; color: Theme.primaryFg }
                    }
                    MouseArea {
                        id: wArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.setWallpaper(tile.modelData)
                    }
                }
            }
        }
        RowLayout {
            spacing: 10
            PillButton { text: "Elegir imagen…"; icon: "add_photo_alternate"; onClicked: wallDialog.open() }
            Txt { text: "También puedes usar Super + W"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
        }
    }
    FileDialog {
        id: wallDialog
        title: "Elegir fondo de pantalla"
        nameFilters: ["Imágenes (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            page.setWallpaper(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")));
            lister.running = true;
        }
    }

    // ------------------------------------------------------ íconos
    Group {
        title: "Íconos"
        help: Icons.installing ? "Descargando los íconos… el escritorio se recarga un segundo al terminar."
                               : "Las carpetas toman el color de tu escritorio. Al cambiarlos, el escritorio se recarga un segundo."
        icon: "interests"
        GridLayout {
            Layout.fillWidth: true
            columns: page.width > 760 ? 3 : 2
            columnSpacing: 14; rowSpacing: 14
            Repeater {
                model: Icons.packs
                ChoiceCard {
                    id: icc
                    required property var modelData
                    title: modelData.name
                    help: Icons.installing === modelData.id ? "Descargando…" : Icons.installed[modelData.id] ? modelData.desc : modelData.desc + " Se descarga (" + modelData.size + ")."
                    selected: Icons.current === modelData.id
                    previewHeight: 86
                    onClicked: Icons.choose(modelData.id)
                    Rectangle {
                        anchors.fill: parent; color: Theme.alpha(Theme.fg, 0.04)
                        Image { anchors.fill: parent; anchors.margins: 10; fillMode: Image.PreserveAspectFit; source: Icons.preview(icc.modelData.id); sourceSize: Qt.size(600, 150); asynchronous: true }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------ efecto vidrio
    Group {
        id: glassG
        title: "Efecto vidrio"
        help: "Partes translúcidas que dejan ver el fondo desenfocado detrás, como un cristal."
        icon: "blur_on"

        readonly property var parts: [
            { k: "bar", t: "Barra superior", i: "top_panel_open" },
            { k: "dock", t: "Barra de tareas", i: "dock_to_bottom" },
            { k: "panels", t: "Menús y paneles", i: "dashboard" },
            { k: "windows", t: "Ventanas de apps", i: "web_asset" },
        ]

        // vista previa: tarjeta de vidrio sobre tu fondo
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: Theme.radiusLarge
            clip: true
            color: Theme.surfaceHigh
            // El fondo vivo (átomo) no es una imagen: se dibuja el degradado de Quantum.
            readonly property bool live: Settings.appearance.wallpaper === "quantum:live"
            Gradient {
                id: liveGradient
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#140F2E" }
                GradientStop { position: 0.55; color: "#3B2C9A" }
                GradientStop { position: 1; color: "#6A5CFF" }
            }
            Rectangle {
                anchors.fill: parent
                visible: parent.live
                gradient: liveGradient
                opacity: 0.9
            }
            Image {
                anchors.fill: parent
                visible: !parent.live && Settings.appearance.wallpaper !== ""
                source: visible ? "file://" + Settings.appearance.wallpaper : ""
                sourceSize: Qt.size(800, 300)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.centerIn: parent
                width: 360; height: 90; radius: Theme.radiusLarge
                color: Theme.alpha(Theme.surface, Settings.appearance.panelOpacity)
                border.width: 1; border.color: Theme.alpha(Theme.fg, 0.14)
                Txt { anchors.centerIn: parent; text: "Así se ve el vidrio"; font.weight: Font.Bold; font.pixelSize: Theme.textLarge }
            }
        }

        Txt { text: "Dónde se aplica"; font.weight: Font.DemiBold }
        Flow {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: glassG.parts
                Rectangle {
                    id: gp
                    required property var modelData
                    readonly property bool on: Settings.appearance.glass[modelData.k]
                    width: gpRow.implicitWidth + 28; height: 42; radius: 21
                    color: on ? Theme.primaryContainer : gpArea.containsMouse ? Theme.surfaceHighest : Theme.surfaceHigh
                    border.width: on ? 0 : 1; border.color: Theme.alpha(Theme.fg, 0.1)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Row {
                        id: gpRow
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; text: gp.on ? "check_circle" : gp.modelData.i; size: 18; fill: gp.on ? 1 : 0; color: gp.on ? Theme.primaryContainerFg : Theme.fg }
                        Txt { anchors.verticalCenter: parent.verticalCenter; text: gp.modelData.t; font.weight: Font.DemiBold; color: gp.on ? Theme.primaryContainerFg : Theme.fg }
                    }
                    MouseArea {
                        id: gpArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.setPath("appearance.glass." + gp.modelData.k, !gp.on)
                    }
                }
            }
        }

        OptionRow {
            title: "Opacidad de barras y paneles"
            help: "Más bajo = más transparente."
            Slider {
                implicitWidth: 240
                from: 0.4; to: 1; step: 0.02
                value: Settings.appearance.panelOpacity
                text: Math.round(_shown * 100) + " %"
                live: true
                onMoved: v => Settings.set("appearance", "panelOpacity", v)
            }
        }
        OptionRow {
            visible: Settings.appearance.glass.windows
            title: "Opacidad de las ventanas de apps"
            help: "Las ventanas se vuelven translúcidas (sin desenfoque). Se aplica a las que abras desde ahora; muy bajo puede costar leer."
            Slider {
                implicitWidth: 240
                from: 0.6; to: 1; step: 0.02
                value: Settings.appearance.windowOpacity
                text: Math.round(_shown * 100) + " %"
                onMoved: v => Settings.set("appearance", "windowOpacity", v)
            }
        }
        OptionRow {
            title: "Desenfoque detrás"
            help: "Desenfoca lo que hay detrás del vidrio. Consume algo de gráfica (en máquinas virtuales se desactiva solo)."
            Toggle { checked: Settings.appearance.blur; onToggled: c => Settings.set("appearance", "blur", c) }
        }
    }

    // --------------------------------------------------------------- texto
    Group {
        title: "Texto"
        icon: "format_size"
        advanced: true
        OptionRow {
            title: "Tamaño del texto"
            help: "Afecta a la barra, menús y paneles de Quantum."
            Segmented {
                options: [{ v: 0.9, t: "Pequeño" }, { v: 1.0, t: "Normal" }, { v: 1.12, t: "Grande" }]
                value: Settings.appearance.textScale
                onPicked: v => Settings.set("appearance", "textScale", v)
            }
        }
    }
}
