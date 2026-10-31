import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Franja invisible en el borde de arriba, centrada donde aparece el panel de la hora:
// si el mouse se queda un momento, el panel baja solo. No molesta en juegos o videos
// a pantalla completa ni cuando hay otro panel abierto.
PanelWindow {
    id: zone

    screen: Wm.screen
    visible: !(Wm.active?.fullscreen ?? false)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quantum-dashboard-zone"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true }
    implicitWidth: Math.min(700, (screen?.width ?? 1920) - 40)
    implicitHeight: 4
    color: "transparent"

    HoverHandler {
        id: h
        onHoveredChanged: {
            Shell.dashboardZoneHovered = hovered;
            if (hovered) delay.restart(); else delay.stop();
        }
    }
    // un instante de espera: así no se abre al pasar el mouse de largo
    Timer {
        id: delay
        interval: 250
        onTriggered: Shell.hoverDashboard()
    }
}
