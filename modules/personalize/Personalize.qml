import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

            title: "Personalizar"
            implicitWidth: 1100
            implicitHeight: 740
            minimumSize: Qt.size(860, 580)
            color: Theme.surface
            visible: true
            onVisibleChanged: if (!visible) Shell.personalizeOpen = false

            readonly property var pages: [
                { id: "styles", t: "Estilos", h: "Cambia todo el escritorio con un clic.", i: "auto_awesome", c: stylesPage },
                { id: "colors", t: "Colores y fondo", h: "Modo claro u oscuro, color de acento y fondo de pantalla.", i: "palette", c: colorsPage },
                { id: "bar", t: "Barra y dock", h: "Dónde van tus apps, la hora y el estado del sistema.", i: "dock_to_bottom", c: barPage },
                { id: "windows", t: "Ventanas", h: "Esquinas, botones y animaciones de las ventanas.", i: "web_asset", c: windowsPage },
                { id: "lock", t: "Bloqueo", h: "Qué tarjetas se ven en la pantalla de bloqueo y en qué orden.", i: "lock", c: lockPage },
                { id: "sounds", t: "Sonidos", h: "Los sonidos del sistema y su volumen.", i: "music_note", c: soundsPage },
                { id: "display", t: "Pantalla", h: "Luz nocturna, brillo, contraste, gamma y saturación.", i: "desktop_windows", c: displayPage },
                { id: "input", t: "Mouse y touchpad", h: "Velocidad, aceleración, desplazamiento y clics.", i: "mouse", c: inputPage },
            ]
            property string current: pages.some(p => p.id === Settings.ui.page) ? Settings.ui.page : "styles"
            readonly property var page: pages.find(p => p.id === current)
            property bool confirmReset: false

            Component.onCompleted: Settings.snapshot()

            Component { id: stylesPage; StylesPage {} }
            Component { id: colorsPage; ColorsPage {} }
            Component { id: barPage; BarPage {} }
            Component { id: windowsPage; WindowsPage {} }
            Component { id: lockPage; LockPage {} }
            Component { id: soundsPage; SoundsPage {} }
            Component { id: displayPage; DisplayPage {} }
            Component { id: inputPage; InputPage {} }

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

                        RowLayout {
                            Layout.bottomMargin: 14
                            spacing: 12
                            Image {
                                Layout.preferredWidth: 46; Layout.preferredHeight: 46
                                source: Quickshell.shellDir + "/assets/quantum-personalize.svg"
                                sourceSize: Qt.size(92, 92)
                                smooth: true
                            }
                            ColumnLayout {
                                spacing: 0
                                Txt { text: "Personalizar"; font.pixelSize: Theme.textLarge + 2; font.weight: Font.Bold }
                                Txt { text: "Tu escritorio, a tu manera"; color: Theme.fgMuted; font.pixelSize: Theme.textSmall }
                            }
                        }

                        Repeater {
                            model: win.pages
                            Rectangle {
                                id: nav
                                required property var modelData
                                readonly property bool on: win.current === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: 23
                                color: on ? Theme.primaryContainer : navArea.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    spacing: 12
                                    Icon {
                                        text: nav.modelData.i
                                        size: 21
                                        fill: nav.on ? 1 : 0
                                        color: nav.on ? Theme.primaryContainerFg : Theme.fg
                                    }
                                    Txt {
                                        Layout.fillWidth: true
                                        text: nav.modelData.t
                                        font.weight: nav.on ? Font.Bold : Font.Medium
                                        color: nav.on ? Theme.primaryContainerFg : Theme.fg
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
                        Txt { text: "Vista previa"; font.weight: Font.Bold; font.pixelSize: Theme.textSmall; color: Theme.fgMuted }
                        MiniDesktop {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 9 / 16
                            v: Settings.visualState()
                        }

                        PillButton {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            text: "Deshacer cambios"
                            icon: "undo"
                            enabled_: Settings.changed
                            onClicked: Settings.undo()
                        }
                        PillButton {
                            Layout.fillWidth: true
                            text: win.confirmReset ? "¿Seguro? Toca otra vez" : "Restablecer todo"
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
                                Txt { text: "Opciones avanzadas"; font.weight: Font.DemiBold }
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
