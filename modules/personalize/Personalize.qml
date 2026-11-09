import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.components

// Personalizar (Super + P): cambia cómo se ve y se comporta el escritorio.
// Es una ventana normal (se mueve, se minimiza y aparece en la barra). Los cambios
// se aplican al instante; «Deshacer cambios» vuelve a como estaba al abrirla.
// Solo existe mientras está abierta, para no gastar memoria.
Scope {
    LazyLoader {
        active: Shell.personalizeOpen

        FloatingWindow {
            id: win

            title: I18n.t("Personalizar")
            // 3/4 de la pantalla por defecto (la del monitor enfocado), como las demás ventanas
            readonly property var scr: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            implicitWidth: Math.round((scr?.width ?? 1920) * 0.75)
            implicitHeight: Math.round((scr?.height ?? 1080) * 0.75)
            width: implicitWidth
            height: implicitHeight
            minimumSize: Qt.size(860, 480)
            color: Theme.surface
            visible: true
            onVisibleChanged: if (!visible) Shell.personalizeOpen = false

            // Orden y grupos como la barra lateral de Ajustes del Sistema de macOS.
            // g: grupo (se separan con espacio); k: color del ícono (estilo macOS).
            readonly property var pages: [
                { id: "bluetooth", g: 0, t: "Bluetooth", h: I18n.t("Empareja auriculares, teclados y otros dispositivos."), i: "bluetooth", k: "#0089FF", c: bluetoothPage },
                { id: "input", g: 0, t: I18n.t("Mouse y touchpad"), h: I18n.t("Velocidad, aceleración, desplazamiento y clics."), i: "mouse", k: "#8E8E93", c: inputPage },
                { id: "sounds", g: 0, t: I18n.t("Sonidos"), h: I18n.t("Los sonidos del sistema y su volumen."), i: "music_note", k: "#FF2D55", c: soundsPage },
                { id: "display", g: 0, t: I18n.t("Pantalla"), h: I18n.t("Luz nocturna, brillo, contraste, gamma y saturación."), i: "desktop_windows", k: "#0089FF", c: displayPage },
                { id: "language", g: 1, t: I18n.t("Idioma"), h: I18n.t("El idioma de la barra, los menús, los paneles y esta ventana."), i: "translate", k: "#8E8E93", c: languagePage },
                { id: "apps", g: 1, t: I18n.t("Aplicaciones"), h: I18n.t("Muestra u oculta apps del menú y mira de qué paquete vienen."), i: "apps", k: "#FF9500", c: appsPage },
                { id: "lock", g: 1, t: I18n.t("Bloqueo"), h: I18n.t("Qué tarjetas se ven en la pantalla de bloqueo y en qué orden."), i: "lock", k: "#000000", c: lockPage },
                { id: "styles", g: 2, t: I18n.t("Estilos"), h: I18n.t("Cambia todo el escritorio con un clic."), i: "auto_awesome", k: "#000000", c: stylesPage },
                { id: "colors", g: 2, t: I18n.t("Colores y fondo"), h: I18n.t("Modo claro u oscuro, color de acento y fondo de pantalla."), i: "palette", k: "#32ADE6", c: colorsPage },
                { id: "windows", g: 2, t: I18n.t("Ventanas"), h: I18n.t("Esquinas, botones y animaciones de las ventanas."), i: "web_asset", k: "#5856D6", c: windowsPage },
                { id: "bar", g: 3, t: I18n.t("Barra y dock"), h: I18n.t("Dónde van tus apps, la hora y el estado del sistema."), i: "dock_to_bottom", k: "#000000", c: barPage },
            ]
            property string query: ""
            property string current: pages.some(p => p.id === Settings.ui.page) ? Settings.ui.page : "styles"
            readonly property var page: pages.find(p => p.id === current)
            property bool confirmReset: false

            Component.onCompleted: Settings.snapshot()

            Component { id: languagePage; LanguagePage {} }
            Component { id: appsPage; AppsPage {} }
            Component { id: stylesPage; StylesPage {} }
            Component { id: colorsPage; ColorsPage {} }
            Component { id: barPage; BarPage {} }
            Component { id: windowsPage; WindowsPage {} }
            Component { id: lockPage; LockPage {} }
            Component { id: soundsPage; SoundsPage {} }
            Component { id: displayPage; DisplayPage {} }
            Component { id: inputPage; InputPage {} }
            Component { id: bluetoothPage; BluetoothPage {} }

            Shortcut { sequence: "Escape"; onActivated: Shell.personalizeOpen = false }

            // Para probar sin mouse: qs ipc call personalize page colors
            IpcHandler {
                target: "personalize"
                function page(id: string): void { win.current = id; }
                function advanced(on: bool): void { Settings.setUi("advanced", on); }
                function scroll(y: real): void { flick.contentY = y; }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ---------------------------------------------- barra lateral
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 270
                    color: Theme.surfaceLow

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 6

                        // tarjeta de perfil (como el Apple Account de macOS)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10
                            implicitHeight: profRow.implicitHeight + 16
                            radius: 12
                            color: profArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
                            RowLayout {
                                id: profRow
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                spacing: 12
                                Image {
                                    Layout.preferredWidth: 46; Layout.preferredHeight: 46
                                    source: Quickshell.shellDir + "/assets/quantum-personalize.svg"
                                    sourceSize: Qt.size(92, 92)
                                    smooth: true
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Txt { text: I18n.t("Personalizar"); font.pixelSize: Theme.textLarge; font.weight: Font.Bold }
                                    Txt { text: I18n.t("Tu escritorio, a tu manera"); color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                                }
                            }
                            MouseArea { id: profArea; anchors.fill: parent; hoverEnabled: true }
                        }

                        // buscador (como «Buscar» en Ajustes del Sistema)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 8
                            implicitHeight: 34
                            radius: 17
                            color: Theme.alpha(Theme.fg, 0.07)
                            Icon { id: searchIcon; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "search"; size: 18; color: Theme.fgMuted }
                            TextInput {
                                id: searchIn
                                anchors.left: searchIcon.right; anchors.leftMargin: 8
                                anchors.right: parent.right; anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.font
                                font.pixelSize: Theme.textNormal
                                color: Theme.fg
                                clip: true
                                onTextChanged: win.query = text.trim()
                                Txt {
                                    visible: !searchIn.text && !searchIn.activeFocus
                                    text: I18n.t("Buscar")
                                    color: Theme.fgMuted
                                }
                            }
                        }

                        Repeater {
                            model: win.pages
                            Rectangle {
                                id: nav
                                required property var modelData
                                required property int index
                                readonly property bool on: win.current === modelData.id
                                readonly property bool matches: win.query === "" || modelData.t.toLowerCase().indexOf(win.query.toLowerCase()) >= 0
                                // espacio entre grupos
                                readonly property bool newGroup: index > 0 && win.pages[index - 1].g !== modelData.g
                                visible: matches
                                Layout.fillWidth: true
                                Layout.topMargin: newGroup ? 14 : 0
                                implicitHeight: 36
                                radius: 9
                                color: on ? Theme.primary : navArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    // ícono en cuadro de color redondeado, como en macOS
                                    Rectangle {
                                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                        radius: 7
                                        color: nav.modelData.k
                                        Icon { anchors.centerIn: parent; text: nav.modelData.i; size: 16; fill: 1; color: "white" }
                                    }
                                    Txt {
                                        Layout.fillWidth: true
                                        text: nav.modelData.t
                                        font.weight: nav.on ? Font.DemiBold : Font.Normal
                                        color: nav.on ? Theme.primaryFg : Theme.fg
                                    }
                                }
                                MouseArea {
                                    id: navArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { win.current = nav.modelData.id; Settings.setUi("page", nav.modelData.id); }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // vista previa en vivo de los ajustes actuales
                        Txt { text: I18n.t("Vista previa"); font.weight: Font.Bold; font.pixelSize: Theme.textSmall; color: Theme.fgMuted }
                        MiniDesktop {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 9 / 16
                            v: Settings.visualState()
                        }

                        PillButton {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            text: I18n.t("Deshacer cambios")
                            icon: "undo"
                            enabled_: Settings.changed
                            onClicked: Settings.undo()
                        }
                        PillButton {
                            Layout.fillWidth: true
                            text: win.confirmReset ? I18n.t("¿Seguro? Toca otra vez") : I18n.t("Restablecer todo")
                            icon: "restart_alt"
                            danger: true
                            onClicked: {
                                if (!win.confirmReset) { win.confirmReset = true; resetTimer.restart(); return; }
                                win.confirmReset = false;
                                Settings.resetAll();
                            }
                            Timer { id: resetTimer; interval: 3000; onTriggered: win.confirmReset = false }
                        }
                    }
                }

                // --------------------------------------------------- contenido
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // encabezado
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 28
                        Layout.bottomMargin: 14
                        spacing: 16
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Txt { text: win.page.t; font.pixelSize: Theme.textTitle + 6; font.weight: Font.Bold }
                            Txt { Layout.fillWidth: true; text: win.page.h; color: Theme.fgMuted }
                        }
                        // interruptor de opciones avanzadas
                        Rectangle {
                            implicitWidth: advRow.implicitWidth + 24
                            implicitHeight: 44
                            radius: 22
                            color: Settings.ui.advanced ? Theme.alpha(Theme.primary, 0.14) : Theme.surfaceContainer
                            border.width: 1
                            border.color: Theme.alpha(Theme.fg, 0.08)
                            RowLayout {
                                id: advRow
                                anchors.centerIn: parent
                                spacing: 10
                                Icon { text: "tune"; size: 19; color: Settings.ui.advanced ? Theme.primary : Theme.fg }
                                Txt { text: I18n.t("Opciones avanzadas"); font.weight: Font.DemiBold }
                                Toggle {
                                    implicitWidth: 44; implicitHeight: 26
                                    checked: Settings.ui.advanced
                                    onToggled: c => Settings.setUi("advanced", c)
                                }
                            }
                        }
                    }

                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: loader.height + 40
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Loader {
                            id: loader
                            x: 28
                            width: flick.width - 56
                            sourceComponent: win.page.c
                            // entrada suave al cambiar de sección
                            opacity: 0
                            onLoaded: { flick.contentY = 0; fade.restart(); }
                            NumberAnimation on opacity { id: fade; from: 0; to: 1; duration: Theme.anim; easing.type: Easing.OutCubic }
                            transform: Translate { y: (1 - loader.opacity) * 14 }
                        }

                        // barra de desplazamiento fina
                        Rectangle {
                            visible: flick.contentHeight > flick.height
                            x: flick.width - 8
                            y: flick.contentY + flick.visibleArea.yPosition * flick.height
                            width: 4
                            height: flick.visibleArea.heightRatio * flick.height
                            radius: 2
                            color: Theme.alpha(Theme.fg, 0.25)
                        }
                    }
                }
            }
        }
    }
}
