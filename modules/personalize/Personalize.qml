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

            title: I18n.t("Ajustes del Sistema")
            // Tamaño de Ajustes del Sistema de macOS: ventana mediana (no 3/4 de la pantalla)
            readonly property var scr: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            implicitWidth: Math.min(1060, Math.round((scr?.width ?? 1920) * 0.8))
            implicitHeight: Math.min(740, Math.round((scr?.height ?? 1080) * 0.8))
            width: implicitWidth
            height: implicitHeight
            minimumSize: Qt.size(820, 480)
            color: Theme.surface
            visible: true
            onVisibleChanged: if (!visible) Shell.personalizeOpen = false

            // Orden, nombres y grupos como la barra lateral de Ajustes del Sistema de macOS
            // (Tahoe): Wi-Fi/Bluetooth · General…Fondo de pantalla · Notificaciones/Sonido ·
            // Pantalla bloqueada · Mouse/Trackpad. «Estilos» es propio de Quantum y va al final.
            // g: grupo (se separan con una línea); k: color del ícono; p: página «padre»
            // (no sale en la barra lateral, se abre desde ella, p. ej. General → Acerca de).
            readonly property var pages: [
                { id: "wifi", g: 1, t: "Wi-Fi", h: I18n.t("Redes inalámbricas, contraseña y detalles de la conexión."), i: "wifi", k: "#007AFF", c: wifiPage },
                { id: "bluetooth", g: 1, t: "Bluetooth", h: I18n.t("Empareja auriculares, teclados y otros dispositivos."), i: "bluetooth", k: "#007AFF", c: bluetoothPage },
                { id: "bandwidth", g: 1, t: I18n.t("Ancho de banda"), h: I18n.t("Velocidad de la red, prioridad y límite de cada app."), i: "speed", k: "#34C759", c: bandwidthPage },
                { id: "notifications", g: 2, t: I18n.t("Notifications"), h: I18n.t("Vistas previas, No molestar y avisos de cada app."), i: "notifications", k: "#FF3B30", c: notificationsPage },
                { id: "sounds", g: 2, t: I18n.t("Sound"), h: I18n.t("Efectos de sonido, salida y entrada."), i: "volume_up", k: "#FF2D55", c: soundsPage },
                { id: "general", g: 3, t: I18n.t("General"), ht: I18n.t("Appearance"), h: I18n.t("Apariencia, color de acento y barras de desplazamiento."), i: "settings", k: "#8E8E93", c: generalPage },
                { id: "system", g: 3, t: I18n.t("System"), h: I18n.t("Acerca de, actualizaciones, almacenamiento, idioma, fecha y hora."), i: "computer", k: "#8E8E93", c: systemPage },
                { id: "appearance", g: 3, t: I18n.t("Appearance"), h: I18n.t("Modo claro u oscuro, color de acento, vidrio, íconos y texto."), i: "contrast", k: "#3A3A3C", c: appearancePage },
                { id: "desktop", g: 4, t: I18n.t("Desktop & Dock"), h: I18n.t("Dock, barra de tareas, navegador predeterminado y ventanas."), i: "dock_to_bottom", k: "#3A3A3C", c: desktopPage },
                { id: "display", g: 4, t: I18n.t("Displays"), h: I18n.t("Tamaño del texto, brillo, Night Shift y color."), i: "light_mode", k: "#007AFF", c: displayPage },
                { id: "wallpaper", g: 4, t: I18n.t("Wallpaper"), h: I18n.t("Fondos de Quantum, el fondo vivo y tus fotos."), i: "wallpaper", k: "#32ADE6", c: wallpaperPage },
                { id: "lock", g: 4, t: I18n.t("Lock Screen"), h: I18n.t("Salvapantallas, bloquear y tarjetas de la pantalla bloqueada."), i: "lock", k: "#3A3A3C", c: lockPage },
                { id: "battery", g: 4, t: I18n.t("Battery"), h: I18n.t("Nivel, modo de bajo consumo y salud de la batería."), i: "battery_full", k: "#34C759", c: batteryPage },
                { id: "keyboard", g: 5, t: I18n.t("Keyboard"), h: I18n.t("Repetición de teclas, luz del teclado, atajos y distribución."), i: "keyboard", k: "#8E8E93", c: keyboardPage },
                { id: "mouse", g: 5, t: I18n.t("Mouse"), h: I18n.t("Velocidad, desplazamiento, clic secundario y puntero."), i: "mouse", k: "#8E8E93", c: mousePage },
                { id: "trackpad", g: 5, t: I18n.t("Trackpad"), h: I18n.t("Tocar para hacer clic, clic secundario, desplazamiento y gestos."), i: "touchpad_mouse", k: "#8E8E93", c: trackpadPage },
                // dentro de General
                { id: "about", g: 9, p: "system", t: I18n.t("Acerca de"), h: I18n.t("Equipo, procesador, memoria, pantallas y almacenamiento."), i: "info", k: "#8E8E93", c: aboutPage },
                { id: "update", g: 9, p: "system", t: I18n.t("Actualización de software"), h: I18n.t("Buscar e instalar actualizaciones."), i: "system_update_alt", k: "#8E8E93", c: updatePage },
                { id: "storage", g: 9, p: "system", t: I18n.t("Almacenamiento"), h: I18n.t("Qué ocupa el disco y cómo liberar espacio."), i: "hard_drive", k: "#8E8E93", c: storagePage },
                { id: "login", g: 9, p: "system", t: I18n.t("Elementos de inicio"), h: I18n.t("Apps que se abren al iniciar sesión."), i: "list", k: "#8E8E93", c: loginPage },
                { id: "language", g: 9, p: "system", t: I18n.t("Idioma y región"), h: I18n.t("El idioma de Quantum y los formatos de fecha y hora."), i: "language", k: "#007AFF", c: languagePage },
                { id: "datetime", g: 9, p: "system", t: I18n.t("Fecha y hora"), h: I18n.t("Hora automática, zona horaria y formato de 24 horas."), i: "schedule", k: "#007AFF", c: dateTimePage },
                { id: "apps", g: 9, p: "system", t: I18n.t("Aplicaciones"), h: I18n.t("Muestra u oculta apps del menú y mira de qué paquete vienen."), i: "apps", k: "#FF9500", c: appsPage },
            ]
            // Ids de antes de reordenar como macOS (accesos directos y ajustes guardados)
            function resolve(id: string): string {
                return ({ colors: "appearance", bar: "desktop", windows: "desktop", input: "mouse" })[id] ?? id;
            }
            property string query: ""
            property string current: pages.some(p => p.id === resolve(Settings.ui.page)) ? resolve(Settings.ui.page) : "general"
            readonly property var page: pages.find(p => p.id === current)
            property bool confirmReset: false
            readonly property bool scrolled: flick.contentY > 4

            // Historial para las flechas atrás / adelante de la barra de herramientas (como macOS)
            property var history: [current]
            property int histPos: 0
            readonly property bool canBack: histPos > 0 || !!page.p
            function go(id: string): void {
                id = resolve(id);
                if (id === current || !pages.some(p => p.id === id)) return;
                history = history.slice(0, histPos + 1).concat([id]);
                histPos = history.length - 1;
                current = id;
                Settings.setUi("page", id);
            }
            // sin historial, «atrás» en una subpágina vuelve a su página (Acerca de → General)
            function back(): void {
                if (histPos > 0) { histPos--; current = history[histPos]; }
                else if (page.p) go(page.p);
            }
            function forward(): void { if (histPos < history.length - 1) { histPos++; current = history[histPos]; } }

            Component.onCompleted: Settings.snapshot()

            Component { id: generalPage; GeneralPage { host: win } }
            Component { id: systemPage; SystemPage { host: win } }
            Component { id: aboutPage; AboutPage {} }
            Component { id: updatePage; SoftwareUpdatePage {} }
            Component { id: storagePage; StoragePage {} }
            Component { id: loginPage; LoginItemsPage {} }
            Component { id: languagePage; LanguagePage {} }
            Component { id: dateTimePage; DateTimePage {} }
            Component { id: appsPage; AppsPage {} }
            Component { id: wifiPage; WifiPage {} }
            Component { id: bluetoothPage; BluetoothPage {} }
            Component { id: bandwidthPage; BandwidthPage {} }
            Component { id: batteryPage; BatteryPage {} }
            Component { id: appearancePage; AppearancePage {} }
            Component { id: desktopPage; DesktopDockPage {} }
            Component { id: displayPage; DisplayPage {} }
            Component { id: wallpaperPage; WallpaperPage {} }
            Component { id: notificationsPage; NotificationsPage {} }
            Component { id: soundsPage; SoundsPage {} }
            Component { id: lockPage; LockPage {} }
            Component { id: keyboardPage; KeyboardPage {} }
            Component { id: mousePage; MousePage {} }
            Component { id: trackpadPage; TrackpadPage {} }

            // las páginas se enlazan entre sí (p. ej. Acerca de → Almacenamiento)
            Connections {
                target: Shell
                function onSettingsGo(page: string): void { win.go(page); }
            }

            Shortcut { sequence: "Escape"; onActivated: Shell.personalizeOpen = false }

            // Para probar sin mouse: qs ipc call personalize page appearance
            IpcHandler {
                target: "personalize"
                function page(id: string): void { win.go(id); }
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

                        // contenido centrado con ancho máximo, como el panel derecho de macOS
                        Loader {
                            id: loader
                            width: Math.min(flick.width - 48, 1100)
                            x: (flick.width - width) / 2
                            y: 8
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
                            opacity: Settings.appearance.scrollBars === "always" || flick.moving ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                        }
                    }
                }
            }
        }
    }
}
