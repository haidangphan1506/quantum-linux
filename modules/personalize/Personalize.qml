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
                PersonalizeSidebar { host: win }

                // --------------------------------------------------- contenido
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    PersonalizeHeader { host: win }


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
