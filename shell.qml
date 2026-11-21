//@ pragma UseQApplication
// Íconos: QS_ICON_THEME (quantum-shell-start) si existe; si no, el pragma IconTheme (MacTahoe, igual que GTK).
//@ pragma IconTheme MacTahoe
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

import QtQuick
import Quickshell
import qs.services
import "modules"
import "modules/bar"
import "modules/launcher"
import "modules/activitymonitor"
import "modules/controlcenter"
import "modules/wallpapers"
import "modules/notifications"
import "modules/personalize"
import "modules/osd"
import "modules/screenshot"
import "modules/session"
import "modules/lock"
import "modules/updates"
import "modules/screensaver"
import "modules/overview"
import "modules/switcher"
import "modules/launchpad"
import "modules/about"
import "modules/effects"
import "modules/preview"

// Quantum Shell: el escritorio de Quantum Linux.
// Primero aparece la pantalla de carga (liviana) y el resto se carga de fondo, sin
// bloquear; cuando está todo listo, la pantalla se desvanece y aparece el escritorio.
ShellRoot {
    // Ajustes del Sistema → Hyprland (mouse, trackpad, teclado, Night Shift, escala…)
    readonly property bool hyprApply: HyprApply.inputLua !== ""

    Splash {
        desktopReady: desktop.item !== null
        onSessionStarted: {
            Sounds.play("startup");
            // Ajustes → General → Elementos de inicio («Abrir al iniciar sesión» de macOS)
            for (const id of Settings.apps.login ?? [])
                Apps.entry(id)?.execute();
        }
    }

    LazyLoader {
        id: desktop
        activeAsync: true
        Scope {
            Background {}
            // efecto genie curvo al ocultar/mostrar ventanas por el dock (minimize.lua)
            GenieFx {}
            // Barra de menús (estilo macOS) + dock
            Bar {}
            DockHost {}
            Lock {}
            Popups {}
            Osd {}
            Screenshot {}
            Preview {}
            ClipboardHistory {}
            Spotlight {}
            ControlCenter {}
            WallpaperPicker {}
            Personalize {}
            ActivityMonitor {}
            About {}
            SessionMenu {}
            RebootPrompt {}
            Screensaver {}
            Overview {}
            Switcher {}
            Launchpad {}
        }
    }
}
