pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Estado de la interfaz (qué panel está abierto). Los atajos de teclado los
// define Wayfire (plugin command) y llaman a: qs -c quantum ipc call shell <función>
Singleton {
    id: root

    property bool clipboardOpen: false
    property bool spotlightOpen: false
    property bool controlCenterOpen: false
    property bool sessionOpen: false
    property bool wallpapersOpen: false
    property bool personalizeOpen: false
    property bool activityOpen: false
    property bool aboutOpen: false
    property bool gameMode: false

    // Cử chỉ vuốt 3 ngón dọc (Hyprland -> IPC `shell swipe up|down`):
    //  lên  = đóng Launchpad nếu đang mở, nếu không thì mở Mission Control
    //  xuống = đóng Mission Control nếu đang mở, nếu không thì mở Launchpad
    property bool overviewOpen: false     // lo actualiza Overview.qml
    property bool launchpadOpen: false    // lo actualiza Launchpad.qml
    signal overviewRequest(string fn)
    signal launchpadRequest(string fn)
    function swipe(dir: string): void {
        if (dir === "up") {
            if (launchpadOpen) launchpadRequest("close");
            else overviewRequest("open");
        } else if (dir === "down") {
            if (overviewOpen) overviewRequest("close");
            else launchpadRequest("open");
        }
    }
    // El centro de control mostrando la lista de redes Wi-Fi
    property bool wifiPage: false
    property bool btPage: false
    signal lockRequested

    function closeAll(): void {
        clipboardOpen = false;
        spotlightOpen = false;
        controlCenterOpen = false;
        sessionOpen = false;
        wallpapersOpen = false;
        wifiPage = false;
        btPage = false;
    }

    function toggleClipboard(): void {
        const opening = !clipboardOpen;
        closeAll();
        clipboardOpen = opening;
    }

    function toggleSpotlight(): void {
        const opening = !spotlightOpen;
        closeAll();
        spotlightOpen = opening;
    }

    function toggleControlCenter(): void {
        const opening = !controlCenterOpen;
        closeAll();
        controlCenterOpen = opening;
    }

    // Abre el centro de control en la página de redes Wi-Fi.
    function openWifi(): void {
        closeAll();
        wifiPage = true;
        controlCenterOpen = true;
    }

    // Abre el centro de control en la página de dispositivos Bluetooth.
    function openBluetooth(): void {
        closeAll();
        btPage = true;
        controlCenterOpen = true;
    }

    function toggleWallpapers(): void {
        const opening = !wallpapersOpen;
        closeAll();
        wallpapersOpen = opening;
    }

    function toggleSession(): void {
        const opening = !sessionOpen;
        closeAll();
        sessionOpen = opening;
    }

    function lock(): void {
        closeAll();
        lockRequested();
    }

    // Personalizar es una ventana normal: abrirla no cierra ni la cierran los paneles.
    // Ventana de Personalizar en Hyprland (por su título)
    function personalizeToplevel(): var {
        const t = I18n.t("Ajustes del Sistema");
        return Hyprland.toplevels.values.find(h => h.title === t && h.wayland?.appId === "org.quickshell") ?? null;
    }

    function personalize(): void {
        // Como en macOS: si ya está abierta pero tapada por otras ventanas, se trae al frente
        // (hyprlands/minimize.lua → cael_activate) en vez de cerrarla.
        const t = personalizeOpen ? personalizeToplevel() : null;
        if (t && Hyprland.activeToplevel !== t) {
            const a = t.address.startsWith("0x") ? t.address : "0x" + t.address;
            Quickshell.execDetached(["hyprctl", "eval", `cael_activate('${a}')`]);
            return;
        }
        closeAll();
        personalizeOpen = !personalizeOpen;
    }

    // Activity Monitor: ventana normal del shell; si ya está abierta pero tapada, se trae al frente.
    function activityToplevel(): var {
        return Hyprland.toplevels.values.find(h => h.title === "Activity Monitor" && h.wayland?.appId === "org.quickshell") ?? null;
    }
    function toggleActivity(): void {
        const t = activityOpen ? activityToplevel() : null;
        if (t && Hyprland.activeToplevel !== t) {
            const a = t.address.startsWith("0x") ? t.address : "0x" + t.address;
            Quickshell.execDetached(["hyprctl", "eval", `cael_activate('${a}')`]);
            return;
        }
        activityOpen = !activityOpen;
    }

    // Ajustes del Sistema ya abierto: ir a otra página (las páginas lo usan para enlazarse)
    signal settingsGo(string page)

    // Abre Personalizar directo en una página (ej. «display» desde la luz nocturna)
    function personalizePage(page: string): void {
        closeAll();
        Settings.setUi("page", page);
        personalizeOpen = true;
    }

    function openAbout(): void {
        closeAll();
        aboutOpen = true;
    }

    function toggleNightLight(): void {
        Settings.set("display", "nightLight", !Settings.display.nightLight);
    }

    // Modo juego: quita todas las animaciones (shell + Hyprland) y efectos para ganar FPS.
    function setGameMode(on: bool): void {
        gameMode = on;
        Quickshell.execDetached(["sh", "-c", "command -v quantum-theme >/dev/null && exec quantum-theme gamemode " + (on ? "on" : "off") + "; exit 0"]);
        // Hyprland: desactiva (o restaura) todas las animaciones, blur y sombras del compositor
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.config({ animations = { enabled = ${!on} }, decoration = { blur = { enabled = ${!on} }, shadow = { enabled = ${!on} } } })`]);
    }

    IpcHandler {
        target: "shell"

        function swipe(dir: string): void { root.swipe(dir); }
        function swipeState(): string { return `overview=${root.overviewOpen} launchpad=${root.launchpadOpen}`; }
        function spotlight(): void { root.toggleSpotlight(); }
        function clipboard(): void { root.toggleClipboard(); }
        function controlCenter(): void { root.toggleControlCenter(); }
        function wifi(): void { root.openWifi(); }
        function bluetooth(): void { root.openBluetooth(); }
        function session(): void { root.toggleSession(); }
        function wallpapers(): void { root.toggleWallpapers(); }
        function personalize(): void { root.personalize(); }
        function activityMonitor(): void { root.toggleActivity(); }
        function about(): void { root.openAbout(); }
        function nightLight(): void { root.toggleNightLight(); }
        function sound(name: string): void { Sounds.play(name); }
        function lock(): void { root.lock(); }
        function gameMode(): void { root.setGameMode(!root.gameMode); }
        function brightnessUp(): void { Brightness.step(0.05); }
        function brightnessDown(): void { Brightness.step(-0.05); }
    }
}
