pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Estado de la interfaz (qué panel está abierto). Los atajos de teclado los
// define Wayfire (plugin command) y llaman a: qs -c quantum ipc call shell <función>
Singleton {
    id: root

    property bool launcherOpen: false
    property bool clipboardMode: false
    property bool controlCenterOpen: false
    property bool sessionOpen: false
    property bool dashboardOpen: false
    // abierto al pasar el mouse por el borde de arriba: se cierra solo al salir
    property bool dashboardHover: false
    property bool dashboardZoneHovered: false
    property bool wallpapersOpen: false
    property bool personalizeOpen: false
    property bool aiOpen: false
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
        launcherOpen = false;
        controlCenterOpen = false;
        sessionOpen = false;
        dashboardOpen = false;
        wallpapersOpen = false;
        aiOpen = false;
        wifiPage = false;
        btPage = false;
        Serp.panel = "";
    }

    function toggleLauncher(clipboard: bool): void {
        const opening = !launcherOpen || clipboardMode !== clipboard;
        closeAll();
        clipboardMode = clipboard;
        launcherOpen = opening;
    }

    function toggleControlCenter(): void {
        if (Serp.on) { const p = Serp.panel; closeAll(); Serp.panel = p; Serp.toggle("control"); return; }
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

    function toggleDashboard(): void {
        if (Serp.on) { const p = Serp.panel; closeAll(); Serp.panel = p; Serp.toggle("clock"); return; }
        const opening = !dashboardOpen;
        closeAll();
        dashboardHover = false;
        dashboardOpen = opening;
    }

    function hoverDashboard(): void {
        if (dashboardOpen || launcherOpen || controlCenterOpen || sessionOpen || wallpapersOpen || aiOpen)
            return;
        dashboardHover = true;
        dashboardOpen = true;
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

    function toggleAi(): void {
        const opening = !aiOpen;
        closeAll();
        aiOpen = opening;
    }

    // Personalizar es una ventana normal: abrirla no cierra ni la cierran los paneles.
    // Ventana de Personalizar en Hyprland (por su título)
    function personalizeToplevel(): var {
        const t = I18n.t("Personalizar");
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

    // Modo juego: quita animaciones y desenfoque de Wayfire para ganar FPS.
    function setGameMode(on: bool): void {
        gameMode = on;
        Quickshell.execDetached(["quantum-theme", "gamemode", on ? "on" : "off"]);
    }

    IpcHandler {
        target: "shell"

        function launcher(): void { root.toggleLauncher(false); }
        function swipe(dir: string): void { root.swipe(dir); }
        function swipeState(): string { return `overview=${root.overviewOpen} launchpad=${root.launchpadOpen}`; }
        function clipboard(): void { root.toggleLauncher(true); }
        function controlCenter(): void { root.toggleControlCenter(); }
        function wifi(): void { root.openWifi(); }
        function bluetooth(): void { root.openBluetooth(); }
        function session(): void { root.toggleSession(); }
        function dashboard(): void { root.toggleDashboard(); }
        function wallpapers(): void { root.toggleWallpapers(); }
        function personalize(): void { root.personalize(); }
        function about(): void { root.openAbout(); }
        function nightLight(): void { root.toggleNightLight(); }
        function ai(): void { root.toggleAi(); }
        function sound(name: string): void { Sounds.play(name); }
        function lock(): void { root.lock(); }
        function gameMode(): void { root.setGameMode(!root.gameMode); }
        function brightnessUp(): void { Brightness.step(0.05); }
        function brightnessDown(): void { Brightness.step(-0.05); }
    }
}
