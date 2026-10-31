import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Menú de apagado: bloquear, cerrar sesión, suspender, reiniciar y apagar.
// Pantalla completa oscurecida con el reloj arriba; los botones suben uno tras otro.
PanelWindow {
    id: win

    readonly property bool open: Shell.sessionOpen
    property real progress: 0

    visible: open || progress > 0.001
    screen: Wm.screen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-session"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.alpha(Theme.scrim, 0.62 * Math.min(1, progress))

    readonly property var actions: [
        { icon: "lock", label: "Bloquear", hint: "Super + L", run: () => Shell.lock() },
        { icon: "logout", label: "Cerrar sesión", hint: "", run: () => Wm.logout() },
        { icon: "bedtime", label: "Suspender", hint: "", run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
        { icon: "restart_alt", label: "Reiniciar", hint: "", run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { icon: "power_settings_new", label: "Apagar", hint: "", run: () => Quickshell.execDetached(["systemctl", "poweroff"]) },
    ]
    property int current: 0
    // Los botones se achican en pantallas angostas
    readonly property int buttonSize: Math.max(72, Math.min(124, Math.floor((width - 80) / actions.length) - 30))
    readonly property string user: Quickshell.env("USER") ?? ""

    // abrir con rebote; cerrar rápido
    onOpenChanged: {
        anim.to = open ? 1 : 0;
        anim.duration = open ? 620 : 200;
        anim.easing.type = open ? Easing.OutCubic : Easing.InCubic;
        anim.restart();
        if (open) { current = 0; row.forceActiveFocus(); }
    }
    NumberAnimation { id: anim; target: win; property: "progress" }
    // 0 → 1 para el elemento i (el reloj es -1, los botones 0..4)
    function stage(i: int): real { return Math.max(0, Math.min(1, (progress - 0.1 - (i + 1) * 0.08) / 0.4)); }

    function run(i: int): void {
        Shell.sessionOpen = false;
        actions[i].run();
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    MouseArea {
        anchors.fill: parent
        onClicked: Shell.sessionOpen = false
    }

    // reloj y saludo
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: row.top
        anchors.bottomMargin: Math.round(win.height * 0.09)
        spacing: 2
        opacity: win.stage(-1)
        transform: Translate { y: (1 - win.stage(-1)) * -24 }

        Txt {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: 96
            font.weight: Font.Black
            color: "white"
        }
        Txt {
            Layout.alignment: Qt.AlignHCenter
            readonly property int h: clock.date.getHours()
            text: (h < 20 && h >= 6 ? "Hasta luego" : "Buenas noches") + (win.user ? ", " + win.user : "")
            font.pixelSize: Theme.textTitle
            font.weight: Font.DemiBold
            color: Theme.alpha("white", 0.75)
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 26
        focus: true

        Keys.onEscapePressed: Shell.sessionOpen = false
        Keys.onLeftPressed: win.current = (win.current + win.actions.length - 1) % win.actions.length
        Keys.onRightPressed: win.current = (win.current + 1) % win.actions.length
        Keys.onReturnPressed: win.run(win.current)
        Keys.onEnterPressed: win.run(win.current)

        Repeater {
            model: win.actions

            ColumnLayout {
                id: item
                required property var modelData
                required property int index
                readonly property bool selected: win.current === index
                readonly property real k: win.stage(index)
                spacing: 14
                opacity: k
                transform: Translate { y: (1 - item.k) * 60 }

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: win.buttonSize
                    implicitHeight: win.buttonSize
                    scale: (item.selected ? 1.08 : 1) * (0.7 + 0.3 * item.k)
                    Behavior on scale { NumberAnimation { duration: Theme.animSlow; easing.type: Easing.OutBack } }

                    // brillo detrás del botón elegido
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 26
                        height: width
                        radius: width / 2
                        opacity: item.selected ? 0.35 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.alpha(Theme.brandCyan, 0.5) }
                            GradientStop { position: 1; color: Theme.alpha(Theme.brandViolet, 0.5) }
                        }
                        layer.enabled: true
                        layer.smooth: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width * 0.32
                        color: Theme.alpha(Theme.surface, 0.88)
                        border.width: 1
                        border.color: Theme.alpha("white", item.selected ? 0.3 : 0.1)

                        // degradado de Quantum en el elegido
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            opacity: item.selected ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.anim } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.brandCyan }
                                GradientStop { position: 0.5; color: Theme.brandIndigo }
                                GradientStop { position: 1; color: Theme.brandViolet }
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            text: item.modelData.icon
                            size: Math.round(win.buttonSize * 0.4)
                            fill: item.selected ? 1 : 0
                            color: "white"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.current = item.index
                        onClicked: win.run(item.index)
                    }
                }
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    text: item.modelData.label
                    color: "white"
                    font.pixelSize: Theme.textLarge
                    font.weight: item.selected ? Font.Bold : Font.Medium
                }
                Txt {
                    Layout.alignment: Qt.AlignHCenter
                    text: item.modelData.hint || " "
                    color: Theme.alpha("white", 0.5)
                    font.pixelSize: Theme.textSmall
                }
            }
        }
    }

    // ayuda abajo
    Txt {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        text: "← → para elegir · Enter para confirmar · Esc para volver"
        color: Theme.alpha("white", 0.45)
        opacity: win.stage(5)
    }
}
