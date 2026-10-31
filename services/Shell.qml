pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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
    property bool gameMode: false
    // El centro de control mostrando la lista de redes Wi-Fi
    property bool wifiPage: false
    signal lockRequested

    function closeAll(): void {
        launcherOpen = false;
        controlCenterOpen = false;
        sessionOpen = false;
        dashboardOpen = false;
        wallpapersOpen = false;
        aiOpen = false;
        wifiPage = false;
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
    function personalize(): void {
        closeAll();
        personalizeOpen = !personalizeOpen;
    }

    // Abre Personalizar directo en una página (ej. «display» desde la luz nocturna)
    function personalizePage(page: string): void {
        closeAll();
        Settings.setUi("page", page);
        personalizeOpen = true;
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
        function clipboard(): void { root.toggleLauncher(true); }
        function controlCenter(): void { root.toggleControlCenter(); }
        function wifi(): void { root.openWifi(); }
        function session(): void { root.toggleSession(); }
        function dashboard(): void { root.toggleDashboard(); }
        function wallpapers(): void { root.toggleWallpapers(); }
        function personalize(): void { root.personalize(); }
        function nightLight(): void { root.toggleNightLight(); }
        function ai(): void { root.toggleAi(); }
        function sound(name: string): void { Sounds.play(name); }
        function lock(): void { root.lock(); }
        function gameMode(): void { root.setGameMode(!root.gameMode); }
        function brightnessUp(): void { Brightness.step(0.05); }
        function brightnessDown(): void { Brightness.step(-0.05); }
    }
}
