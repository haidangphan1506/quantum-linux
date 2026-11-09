import QtQuick
import Quickshell
import qs.services

// Dock con posicion (Personalizar). Al cambiar de borde en caliente, el layout del dock no se
// recalcula bien (quedaba como barra vertical en el borde de abajo), asi que se recrea el dock.
Scope {
    id: host

    property bool live: true
    // cualquier cambio de borde recrea el dock
    readonly property string pos: Settings.dock.position
    onPosChanged: { host.live = false; recreate.restart(); }

    Timer {
        id: recreate
        interval: 30
        onTriggered: host.live = true
    }

    LazyLoader {
        active: host.live
        Dock {}
    }
}
