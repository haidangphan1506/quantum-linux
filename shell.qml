//@ pragma UseQApplication
// Los íconos los elige quantum-shell-start (QS_ICON_THEME) según Personalizar; sin eso, qt6ct.
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded

import QtQuick
import Quickshell
import qs.services
import "modules"
import "modules/bar"
import "modules/launcher"
import "modules/controlcenter"
import "modules/dashboard"
import "modules/wallpapers"
import "modules/notifications"
import "modules/personalize"
import "modules/assistant"
import "modules/osd"
import "modules/session"
import "modules/welcome"
import "modules/lock"
import "modules/serpantium"
import "modules/updates"

// Quantum Shell: el escritorio de Quantum Linux.
// Primero aparece la pantalla de carga (liviana) y el resto se carga de fondo, sin
// bloquear; cuando está todo listo, la pantalla se desvanece y aparece el escritorio.
ShellRoot {
    Splash {
        desktopReady: desktop.item !== null
        onSessionStarted: {
            Sounds.play("startup");
            // apps de inicio que no deben competir con la carga del escritorio
            Quickshell.execDetached(["quantum-center", "--autostart"]);
        }
    }

    LazyLoader {
        id: desktop
        activeAsync: true
        Scope {
            Background {}
            // La forma del shell: Caelestial (barra + dock) o Serpantium (píldoras arriba)
            LazyLoader {
                active: !Serp.on
                Scope { Bar {} Dock {} DashboardZone {} }
            }
            LazyLoader {
                active: Serp.on
                Scope {
                    SerpBar {} SerpPanels {} SerpLauncher {}
                    // «Dock abajo»: el mismo dock de Caelestial, con los colores de Serpantium
                    LazyLoader { active: Settings.ui.serpApps === "dock"; Dock {} }
                }
            }
            Lock {}
            Popups {}
            Osd {}
            Launcher {}
            ControlCenter {}
            Dashboard {}
            WallpaperPicker {}
            Personalize {}
            Assistant {}
            SessionMenu {}
            Welcome {}
            RebootPrompt {}
        }
    }
}
