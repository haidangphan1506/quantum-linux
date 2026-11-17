pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

// Lleva los Ajustes del Sistema a Hyprland y a las apps (sin quantum-theme):
//  · Mouse, trackpad y teclado → hl.config({ input = … }) (al iniciar y al cambiar).
//  · Night Shift y ajustes de imagen → un screen shader de Hyprland.
//  · Escala de cada pantalla → hl.monitor (se recuerda en display.scales).
//  · Animaciones y borde de ventanas, botones de las apps GTK y modo claro/oscuro
//    (gsettings) → solo cuando el usuario los cambia, para no pisar la config a mano.
// Tras `hyprctl reload` (configreloaded) se vuelve a aplicar lo que es de Quantum.
Singleton {
    id: root

    readonly property var m: Settings.mouse
    readonly property var t: Settings.touchpad
    readonly property var k: Settings.keyboard
    readonly property var d: Settings.display

    // Los cambios «solo cuando el usuario los hace» se ignoran hasta un rato después de
    // leer settings.json (al cargarlo, los valores pasan de los de fábrica a los guardados).
    property bool ready: false
    Timer {
        running: Settings.loaded
        interval: 2500
        onTriggered: {
            root.ready = true;
            root.syncColorScheme();     // Herdr, apps GTK/libadwaita y portales siguen el tema del shell
            if (Settings.windows.doubleClick !== "fill") root.applyDblClick();
            root.applyScales();
        }
    }

    function hypr(code: string): void {
        Quickshell.execDetached(["hyprctl", "eval", code]);
    }
    function num(v: real): string { return Number(v).toFixed(3); }

    // ------------------------------------------------------------------ entrada
    property var touchpads: []
    Process {
        id: devProc
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.touchpads = JSON.parse(text).mice.map(x => x.name).filter(n => /touchpad|trackpad/i.test(n));
                } catch (e) {}
                root.applyInput();
            }
        }
    }

    readonly property string inputLua: {
        const tp = `touchpad = { natural_scroll = ${t.natural}, ["tap-to-click"] = ${t.tapToClick}, disable_while_typing = ${t.disableWhileTyping}, ` +
                   `scroll_factor = ${num(t.scrollSpeed)}, clickfinger_behavior = ${t.clickMethod === "clickfinger"} }`;
        let lua = `hl.config({ input = { sensitivity = ${num(m.speed)}, accel_profile = "${m.accel ? "adaptive" : "flat"}", ` +
                  `natural_scroll = ${m.natural}, scroll_factor = ${num(m.scrollSpeed)}, left_handed = ${m.leftHanded}, ` +
                  `repeat_rate = ${Math.round(k.repeatRate)}, repeat_delay = ${Math.round(k.repeatDelay)}, ` +
                  // distribución del teclado: solo si se eligió una (si no, manda la config de Hyprland)
                  (k.layout ? `kb_layout = "${k.layout}", kb_variant = "${k.variant}", kb_options = "${k.options}", ` : "") +
                  `${tp} } })`;
        // velocidad propia del trackpad (en Hyprland va por dispositivo)
        for (const n of touchpads)
            lua += `; hl.device({ name = "${n}", sensitivity = ${num(t.speed)} })`;
        return lua;
    }
    function applyInput(): void { hypr(inputLua); }
    onInputLuaChanged: inputTimer.restart()
    Timer { id: inputTimer; interval: 200; onTriggered: root.applyInput() }

    // Tamaño del puntero (Mouse → Tamaño del puntero)
    Connections {
        target: Settings.mouse
        function onCursorSizeChanged(): void {
            if (!root.ready) return;
            const s = String(Settings.mouse.cursorSize);
            Quickshell.execDetached(["sh", "-c", `t=$(gsettings get org.gnome.desktop.interface cursor-theme | tr -d "'"); ` +
                                     `hyprctl setcursor "$t" ${s}; gsettings set org.gnome.desktop.interface cursor-size ${s}`]);
        }
    }

    // ------------------------------------------------- Night Shift e imagen
    // Night Shift activo ahora: manual, o dentro del horario elegido
    property bool nightNow: false
    function inWindow(from: string, to: string): bool {
        const now = new Date();
        const cur = now.getHours() * 60 + now.getMinutes();
        const p = s => { const a = s.split(":"); return parseInt(a[0]) * 60 + parseInt(a[1] || 0); };
        const a = p(from), b = p(to);
        return a <= b ? cur >= a && cur < b : cur >= a || cur < b;
    }
    function updateNight(): void {
        nightNow = d.nightLight && (d.nightMode !== "schedule" || inWindow(d.nightFrom, d.nightTo));
    }
    Timer { interval: 30000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.updateNight() }
    Connections {
        target: Settings.display
        function onNightLightChanged(): void { root.updateNight(); }
        function onNightModeChanged(): void { root.updateNight(); }
        function onNightFromChanged(): void { root.updateNight(); }
        function onNightToChanged(): void { root.updateNight(); }
    }

    // Kelvin → multiplicadores RGB (aproximación de Tanner Helland)
    function kelvinRgb(kelvin: real): var {
        const tt = kelvin / 100;
        let r, g, b;
        if (tt <= 66) {
            r = 255;
            g = 99.4708025861 * Math.log(tt) - 161.1195681661;
            b = tt <= 19 ? 0 : 138.5177312231 * Math.log(tt - 10) - 305.0447927307;
        } else {
            r = 329.698727446 * Math.pow(tt - 60, -0.1332047592);
            g = 288.1221695283 * Math.pow(tt - 60, -0.0755148492);
            b = 255;
        }
        const c = x => Math.max(0, Math.min(255, x)) / 255;
        return [c(r), c(g), c(b)];
    }

    readonly property bool imageNeutral: d.brightness === 1 && d.contrast === 1 && d.gamma === 1 && d.saturation === 1
    readonly property string shaderSrc: {
        if (!nightNow && imageNeutral) return "";
        const w = nightNow ? kelvinRgb(d.temperature) : [1, 1, 1];
        return `#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 col = c.rgb * vec3(${num(w[0])}, ${num(w[1])}, ${num(w[2])});
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, ${num(d.saturation)});
    col = (col - 0.5) * ${num(d.contrast)} + 0.5;
    col = pow(max(col, 0.0), vec3(${num(1 / d.gamma)}));
    col *= ${num(d.brightness)};
    fragColor = vec4(clamp(col, 0.0, 1.0), c.a);
}
`;
    }
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quantum"
    property bool shaderSet: false     // el shader actual es nuestro (para no borrar uno ajeno)
    property int slot: 0               // dos archivos alternos: Hyprland recarga al cambiar la ruta
    onShaderSrcChanged: shaderTimer.restart()
    Timer { id: shaderTimer; interval: 120; onTriggered: root.applyShader() }
    function applyShader(): void {
        if (shaderSrc === "") {
            if (shaderSet) hypr(`hl.config({ decoration = { screen_shader = "" } })`);
            shaderSet = false;
            return;
        }
        slot = 1 - slot;
        shaderFile.path = cacheDir + "/screen-" + slot + ".frag";
        shaderFile.setText(shaderSrc);
    }
    FileView {
        id: shaderFile
        blockWrites: false
        atomicWrites: true
        printErrors: false
        onSaved: {
            root.hypr(`hl.config({ decoration = { screen_shader = "${path}" } })`);
            root.shaderSet = true;
        }
    }
    Process { running: true; command: ["mkdir", "-p", root.cacheDir] }

    // ------------------------------------------------------------- pantallas
    // Escala elegida en Pantallas: se aplica al iniciar y al reconectar el monitor
    function applyScale(name: string, scale: real): void {
        hypr(`hl.monitor({ output = "${name}", mode = "preferred", position = "auto", scale = ${num(scale)} })`);
    }
    function applyScales(): void {
        const sc = d.scales ?? {};
        for (const n of Object.keys(sc))
            if (sc[n] > 0) applyScale(n, sc[n]);
    }

    // ---------------------------------------- ventanas y apps (solo al cambiar)
    property bool lookTouched: false
    function applyLook(): void {
        const w = Settings.windows, ap = Settings.appearance;
        const op = ap.glass.windows ? num(ap.windowOpacity) : "1.0";
        hypr(`hl.config({ animations = { enabled = ${w.animations !== "none"} }, general = { border_size = ${Math.round(w.borderSize)} }, ` +
             `decoration = { active_opacity = ${op}, inactive_opacity = ${op}, blur = { enabled = ${ap.blur} } } })`);
    }
    function touchLook(): void { if (!ready) return; lookTouched = true; applyLook(); }
    // Doble clic en la barra de título (hyprbars): llenar (3/4 ↔ completa), minimizar o nada
    property bool dblTouched: false
    function applyDblClick(): void {
        const a = Settings.windows.doubleClick;
        const cmd = a === "minimize" ? "hyprctl eval 'cael_minimize()'" : a === "none" ? "true" : "hyprctl eval 'cael_toggle_size()'";
        hypr(`if hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { on_double_click = "${cmd}" } } }) end`);
    }
    Connections {
        target: Settings.windows
        function onDoubleClickChanged(): void { if (!root.ready) return; root.dblTouched = true; root.applyDblClick(); }
    }
    Connections {
        target: Settings.appearance
        function onWindowOpacityChanged(): void { root.touchLook(); }
        function onBlurChanged(): void { root.touchLook(); }
        // íconos de las apps (GTK / Qt con gsettings)
        function onIconThemeChanged(): void {
            if (!root.ready) return;
            const names = { papirus: Theme.dark ? "Papirus-Dark" : "Papirus", tela: "Tela", fluent: "Fluent", whitesur: "WhiteSur",
                            colloid: "Colloid", candy: "candy-icons", mactahoe: Theme.dark ? "MacTahoe-dark" : "MacTahoe" };
            const n = names[Settings.appearance.iconTheme];
            if (n) Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", n]);
        }
    }
    Connections {
        target: Settings.appearance.glass
        function onWindowsChanged(): void { root.touchLook(); }
    }
    Connections {
        target: Settings.windows
        function onAnimationsChanged(): void { root.touchLook(); }
        function onBorderSizeChanged(): void { root.touchLook(); }
        // botones de las apps con barra propia (GTK): a la izquierda como macOS o a la derecha
        function onButtonsLeftChanged(): void {
            if (!root.ready) return;
            Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.wm.preferences", "button-layout",
                                     Settings.windows.buttonsLeft ? "close,minimize,maximize:" : ":minimize,maximize,close"]);
        }
    }
    function syncColorScheme(): void {
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", Theme.dark ? "prefer-dark" : "prefer-light"]);
    }
    // Modo claro / oscuro también para apps GTK 4 / libadwaita y portales
    Connections {
        target: Theme
        function onDarkChanged(): void {
            if (root.ready)
                Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", Theme.dark ? "prefer-dark" : "prefer-light"]);
        }
    }

    // ------------------------------------- barra de título (hyprbars) según el tema
    // Los colores de titlebar.lua salen de un archivo de esquema fijo; aquí siguen al tema real
    // del shell (claro/oscuro, color de fondo) y cambian al instante.
    function hex(c: color, a: real): string {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return "rgba(" + h(c.r) + h(c.g) + h(c.b) + h(a) + ")";
    }
    readonly property string barLua: {
        const bar = hex(Theme.surfaceContainer, 0.94);
        const text = hex(Theme.fg, 1);
        const idle = hex(Theme.fg, Theme.dark ? 0.22 : 0.15);
        return `pcall(hl.config, { plugin = { hyprbars = { bar_color = "${bar}", ["col.text"] = "${text}", inactive_button_color = "${idle}" } } })`;
    }
    function applyBar(): void { hypr(barLua); }
    onBarLuaChanged: barTimer.restart()
    Timer { id: barTimer; interval: 150; onTriggered: root.applyBar() }

    // ------------------------------------------- Modo de bajo consumo (Batería)
    // Cuando toca, pasa a «ahorro de energía»; al dejar de tocar vuelve al modo de antes.
    readonly property string lowPower: Settings.power.lowPower
    readonly property bool lowActive: lowPower === "always" || (lowPower === "battery" && UPower.onBattery) || (lowPower === "adapter" && !UPower.onBattery)
    property int profileBefore: PowerProfile.Balanced
    onLowActiveChanged: {
        if (lowActive) {
            if (PowerProfiles.profile !== PowerProfile.PowerSaver) profileBefore = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        } else if (PowerProfiles.profile === PowerProfile.PowerSaver) {
            PowerProfiles.profile = profileBefore;
        }
    }

    // ------------------------------------------------------- tras recargar
    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded")
                reapply.restart();
            else if (event.name === "monitoradded" || event.name === "monitoraddedv2")
                scaleTimer.restart();
        }
    }
    Timer {
        id: reapply
        interval: 400
        onTriggered: {
            root.applyInput();
            root.applyBar();
            root.shaderSet = false;
            root.applyShader();
            root.applyScales();
            if (root.lookTouched) root.applyLook();
            if (root.dblTouched || Settings.windows.doubleClick !== "fill") root.applyDblClick();
        }
    }
    Timer { id: scaleTimer; interval: 800; onTriggered: root.applyScales() }

    Component.onCompleted: {
        applyScales();
        barTimer.restart();
        shaderTimer.restart();
        if (lowActive && PowerProfiles.profile !== PowerProfile.PowerSaver) {
            profileBefore = PowerProfiles.profile;
            PowerProfiles.profile = PowerProfile.PowerSaver;
        }
    }
}
