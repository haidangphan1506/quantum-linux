import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.components

// Barra superior en modo «pegada» con el estilo de la barra de menús de macOS:
//  logo · App (negrita) · Archivo · Edición · Ver · Ventana · Ayuda    ...   estado · buscar · centro de control · fecha y hora
// Las apps de Wayland no exportan sus menús, así que Archivo/Edición/Ver envían el atajo de
// teclado estándar a la ventana activa (hl.dsp.send_shortcut); en terminales, con Ctrl+Shift.
// Las acciones de ventana usan las funciones de ~/.config/hypr/hyprlands/minimize.lua.
Item {
    id: root

    required property var window
    property bool compact: false

    readonly property var win: Wm.active && !Wm.isMinimized(Wm.active) ? Wm.active : null
    readonly property string appId: win ? (win.appId ?? "") : ""
    readonly property string appName: win ? Wm.nameFor(appId) : "Quantum"
    readonly property bool isTerminal: ["kitty", "foot", "Alacritty", "alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "ghostty", "konsole", "org.gnome.Console", "xterm"].includes(appId)

    // dirección Hyprland de la ventana activa (se guarda al abrir un menú)
    property string addr: ""
    property MacMenu openMenu: null

    function grabAddr(): void {
        const a = Hyprland.activeToplevel?.address ?? "";
        root.addr = a === "" ? "" : (a.startsWith("0x") ? a : "0x" + a);
    }
    function sel(): string { return root.addr ? `address:${root.addr}` : "activewindow"; }
    function hyprEval(code: string): void { Quickshell.execDetached(["hyprctl", "eval", code]); }
    function hyprDispatch(code: string): void { Quickshell.execDetached(["hyprctl", "dispatch", code]); }
    function closeMenus(): void { if (root.openMenu) root.openMenu.close(); }

    // Atajo de teclado → ventana activa. term: atajo distinto para terminales (o null = igual)
    function keys(mods: string, key: string): void {
        hyprDispatch(`hl.dsp.send_shortcut({ mods = "${mods}", key = "${key}", window = "${root.sel()}" })`);
    }
    function label(mods: string, key: string): string {
        const k = { equal: "+", minus: "−", comma: ",", Delete: "Del" }[key] ?? (key.length === 1 ? key.toUpperCase() : key);
        return (mods ? mods.split(" ").map(m => m === "CTRL" ? "Ctrl" : m === "SHIFT" ? "Shift" : m === "ALT" ? "Alt" : m).join("+") + "+" : "") + k;
    }
    // Entrada de menú que envía un atajo; en terminales se le añade Shift si termShift
    function shortcut(text: string, mods: string, key: string, termShift: bool): var {
        const m = termShift && root.isTerminal ? mods + " SHIFT" : mods;
        return { text: text, shortcut: root.label(m, key), enabled: !!root.win, action: () => root.keys(m, key) };
    }

    // Botón de la barra de menús: texto o logo, resaltado redondeado al pasar / abrir
    component MenuButton: MouseArea {
        id: btn
        property string text: ""
        property bool bold: false
        property bool logo: false
        property MacMenu menu: null
        implicitWidth: (logo ? 18 : label.implicitWidth) + 20
        implicitHeight: 24
        hoverEnabled: true
        onClicked: {
            root.grabAddr();
            if (root.openMenu && root.openMenu !== menu) root.openMenu.close();
            menu.toggle();
        }
        // como en macOS: con un menú abierto, pasar por encima de otro lo abre
        onContainsMouseChanged: {
            if (containsMouse && root.openMenu && root.openMenu.visible && root.openMenu !== menu) {
                root.openMenu.close();
                menu.open();
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 5
            color: btn.menu && btn.menu.visible ? Theme.alpha(Theme.fg, 0.22)
                 : btn.containsMouse ? Theme.alpha(Theme.fg, 0.12) : "transparent"
        }
        Image {
            visible: btn.logo
            anchors.centerIn: parent
            width: 17
            height: 17
            source: Quickshell.shellDir + "/assets/quantum-mark.svg"
            sourceSize: Qt.size(40, 40)
        }
        Txt {
            id: label
            visible: !btn.logo
            anchors.centerIn: parent
            text: btn.text
            font.pixelSize: 13
            font.weight: btn.bold ? Font.Bold : Font.Normal
        }
    }

    component BarMenu: MacMenu {
        id: bm
        barWindow: root.window
        onOpened: root.openMenu = bm
        onVisibleChanged: if (!visible && root.openMenu === bm) root.openMenu = null
    }

    // ---------- izquierda ----------
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        MenuButton { id: logoBtn; logo: true; menu: sysMenu }
        MenuButton { id: appBtn; text: root.appName; bold: true; menu: appMenu; Layout.maximumWidth: root.width * 0.25 }
        MenuButton { id: fileBtn; text: I18n.t("Archivo"); menu: fileMenu; visible: !!root.win && !root.compact }
        MenuButton { id: editBtn; text: I18n.t("Edición"); menu: editMenu; visible: !!root.win }
        MenuButton { id: viewBtn; text: I18n.t("Ver"); menu: viewMenu; visible: !!root.win && !root.compact }
        MenuButton { id: winBtn; text: I18n.t("Ventana"); menu: winMenu; visible: !!root.win }
        MenuButton { id: helpBtn; text: I18n.t("Ayuda"); menu: helpMenu }
    }

    // Menú del sistema (la «manzana»)
    BarMenu {
        id: sysMenu
        anchorItem: logoBtn
        items: [
            { text: I18n.t("Acerca de este equipo"), action: () => Shell.openAbout() },
            { separator: true },
            { text: I18n.t("Personalizar") + "…", action: () => Shell.personalize() },
            { text: I18n.t("Fondos de pantalla") + "…", action: () => Shell.toggleWallpapers() },
            { separator: true },
            { text: I18n.t("Forzar salida de ") + root.appName, enabled: !!root.win, action: () => root.hyprDispatch(`hl.dsp.window.kill({ window = "${root.sel()}" })`) },
            { separator: true },
            { text: I18n.t("Suspender"), action: () => Quickshell.execDetached(["systemctl", "suspend"]) },
            { text: I18n.t("Reiniciar") + "…", action: () => Shell.toggleSession() },
            { text: I18n.t("Apagar") + "…", action: () => Shell.toggleSession() },
            { separator: true },
            { text: I18n.t("Bloquear pantalla"), action: () => Shell.lock() },
            { text: I18n.t("Cerrar sesión") + "…", action: () => Shell.toggleSession() }
        ]
    }

    // Menú de la app activa
    BarMenu {
        id: appMenu
        anchorItem: appBtn
        items: [
            { text: I18n.t("Ocultar ") + root.appName, enabled: !!root.win, action: () => root.hyprEval(`cael_minimize('${root.addr}')`) },
            { text: I18n.t("Ocultar otras"), enabled: !!root.win, action: () => root.hyprEval(`cael_hide_others('${root.addr}')`) },
            { text: I18n.t("Mostrar todo"), action: () => root.hyprEval("cael_show_all()") },
            { separator: true },
            { text: I18n.t("Salir de ") + root.appName, enabled: !!root.win, shortcut: "Super+C", action: () => root.hyprEval(`cael_close('${root.addr}')`) }
        ]
    }

    BarMenu {
        id: fileMenu
        anchorItem: fileBtn
        items: [
            root.shortcut(I18n.t("Nueva ventana"), "CTRL", "n", true),
            root.shortcut(I18n.t("Nueva pestaña"), "CTRL", "t", true),
            root.shortcut(I18n.t("Abrir") + "…", "CTRL", "o", false),
            { separator: true },
            root.shortcut(I18n.t("Guardar"), "CTRL", "s", false),
            root.shortcut(I18n.t("Guardar como") + "…", "CTRL SHIFT", "s", false),
            root.shortcut(I18n.t("Imprimir") + "…", "CTRL", "p", false),
            { separator: true },
            root.shortcut(I18n.t("Cerrar pestaña"), "CTRL", "w", true)
        ]
    }

    BarMenu {
        id: editMenu
        anchorItem: editBtn
        items: [
            root.shortcut(I18n.t("Deshacer"), "CTRL", "z", false),
            root.shortcut(I18n.t("Rehacer"), "CTRL SHIFT", "z", false),
            { separator: true },
            root.shortcut(I18n.t("Cortar"), "CTRL", "x", false),
            root.shortcut(I18n.t("Copiar"), "CTRL", "c", true),
            root.shortcut(I18n.t("Pegar"), "CTRL", "v", true),
            root.shortcut(I18n.t("Seleccionar todo"), "CTRL", "a", false),
            { separator: true },
            root.shortcut(I18n.t("Buscar") + "…", "CTRL", "f", true),
            { separator: true },
            { text: I18n.t("Historial del portapapeles"), action: () => Shell.toggleLauncher(true) }
        ]
    }

    BarMenu {
        id: viewMenu
        anchorItem: viewBtn
        items: [
            root.shortcut(I18n.t("Acercar"), "CTRL", "equal", true),
            root.shortcut(I18n.t("Alejar"), "CTRL", "minus", true),
            root.shortcut(I18n.t("Tamaño real"), "CTRL", "0", false),
            { separator: true },
            root.shortcut(I18n.t("Recargar"), "CTRL", "r", false),
            { separator: true },
            { text: I18n.t("Pantalla completa"), enabled: !!root.win, action: () => root.hyprDispatch(`hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", window = "${root.sel()}" })`) }
        ]
    }

    BarMenu {
        id: winMenu
        anchorItem: winBtn
        items: [
            { text: I18n.t("Minimizar"), action: () => root.hyprEval(`cael_minimize('${root.addr}')`) },
            { text: I18n.t("Ajustar tamaño (3/4 ↔ completa)"), action: () => root.hyprEval(`cael_toggle_size('${root.addr}')`) },
            { text: I18n.t("Centrar"), action: () => root.hyprDispatch(`hl.dsp.window.center({ window = "${root.sel()}" })`) },
            { text: I18n.t("Fijar en todos los escritorios"), action: () => root.hyprDispatch(`hl.dsp.window.pin({ window = "${root.sel()}" })`) },
            { separator: true },
            { text: I18n.t("Mostrar todo"), action: () => root.hyprEval("cael_show_all()") },
            { separator: true },
            { text: I18n.t("Cerrar ventana"), shortcut: "Super+C", action: () => root.hyprEval(`cael_close('${root.addr}')`) }
        ]
    }

    BarMenu {
        id: helpMenu
        anchorItem: helpBtn
        items: [
            { text: I18n.t("Buscar apps") + "…", action: () => Shell.toggleLauncher(false) },
            { text: I18n.t("Asistente de Quantum"), action: () => Shell.toggleAi() },
            { separator: true },
            { text: I18n.t("Atajos de teclado"), action: () => Quickshell.execDetached(["kitty", "--title", I18n.t("Atajos de teclado"), "--hold", Quickshell.shellDir + "/scripts/keybinds.sh"]) }
        ]
    }

    // ---------- derecha ----------

    component BarIcon: MouseArea {
        id: ib
        property string icon: ""
        property bool active: false
        implicitWidth: 30
        implicitHeight: 24
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            radius: 5
            color: ib.containsMouse || ib.active ? Theme.alpha(Theme.fg, 0.12) : "transparent"
        }
        Icon { anchors.centerIn: parent; text: ib.icon; size: 17 }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Tray { window: root.window; visible: Settings.dock.showTray && items.length > 0 }
        // Uso de Claude Code: contexto del chat y lo que queda de 5 h y de la semana (clic: detalle)
        ClaudeMeter { window: root.window; visible: Settings.layout.topBar.showClaude }

        // Temperatura, CPU y RAM en tiempo real (clic: panel con el detalle)
        Loader {
            active: Settings.layout.topBar.showSysMon
            visible: active
            sourceComponent: SysMonitor { barWindow: root.window; compact: root.compact }
        }
        Status { implicitHeight: 24; radius: 5 }
        // Spotlight
        BarIcon { icon: "search"; onClicked: { root.closeMenus(); Shell.toggleLauncher(false); } }
        // Centro de control (interruptores) / notificaciones pendientes
        BarIcon {
            icon: Notifs.count > 0 ? "notifications_unread" : "toggle_on"
            active: Shell.controlCenterOpen
            onClicked: { root.closeMenus(); Shell.toggleControlCenter(); }
        }
        // Fecha y hora en una sola línea, peso normal: «T7 31 thg 10  16:15»
        MouseArea {
            id: clockBtn
            implicitWidth: clockTxt.implicitWidth + 16
            implicitHeight: 24
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.closeMenus(); Shell.toggleDashboard(); }
            SystemClock {
                id: clock
                precision: Settings.clock.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
            }
            Rectangle {
                anchors.fill: parent
                radius: 5
                color: clockBtn.containsMouse ? Theme.alpha(Theme.fg, 0.12) : "transparent"
            }
            Txt {
                id: clockTxt
                anchors.centerIn: parent
                font.pixelSize: 13
                text: (root.compact || !Settings.clock.showDate ? "" : clock.date.toLocaleDateString(I18n.locale, "ddd d MMM") + "   ")
                    + Qt.formatDateTime(clock.date, (Settings.clock.format24h ? "HH:mm" : "h:mm") + (Settings.clock.showSeconds ? ":ss" : "")
                        + (Settings.clock.format24h ? "" : " AP"))
            }
        }
    }
}
