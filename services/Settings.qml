pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Ajustes del usuario (~/.config/quantum/settings.json), compartidos con el
// Centro Quantum, Personalizar y quantum-theme.
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quantum/settings.json"

    property alias appearance: adapter.appearance
    property alias windows: adapter.windows
    property alias keyboard: adapter.keyboard
    property alias notifications: adapter.notifications
    property alias dock: adapter.dock
    property alias layout: adapter.layout
    property alias clock: adapter.clock
    property alias ui: adapter.ui
    property alias lock: adapter.lock
    property alias sounds: adapter.sounds
    property alias display: adapter.display
    property alias mouse: adapter.mouse
    property alias touchpad: adapter.touchpad
    property alias apps: adapter.apps
    property alias screensaver: adapter.screensaver
    property alias power: adapter.power

    // Valores de fábrica de todo lo visual (= estilo «Quantum»). Los estilos se
    // aplican encima de esto, así un estilo siempre se ve igual.
    readonly property var defaults: ({
        appearance: { mode: "light", dynamicColors: false, accent: "#6A5CFF", panelOpacity: 0.86, blur: true, textScale: 1.0,
                      glass: { bar: true, dock: true, panels: true, windows: false }, windowOpacity: 0.9 },
        layout: { topBar: { floating: true, showApp: true, showSysMon: true, showNetSpeed: true, showClaude: true } },
        dock: { floating: true, align: "center", size: "medium", autohide: false, showSearch: true, showStart: true, showTray: true, showUpdates: true, showDownloads: true },
        clock: { format24h: true, showDate: true, showSeconds: false },
        lock: { left: ["weather", "fetch", "media"], right: ["stats", "notifs"], showNotifContent: false, city: "" },
        windows: { tiling: false, corners: "soft", animations: "normal", openAnimation: "zoom", minimizeAnimation: "zoom", buttonsLeft: false,
                   wobbly: false, titleHeight: 34, borderSize: 1 }
    })
    readonly property var visualSections: ["appearance", "layout", "dock", "clock", "windows", "lock"]

    // Solo se escribe el archivo cuando ya se leyó: si algo cambia un ajuste justo al
    // arrancar o recargar el shell (antes de leerlo), se escribirían los valores de fábrica
    // encima de los del usuario.
    property bool loaded: false
    function save(): void {
        if (loaded)
            file.writeAdapter();
    }

    // ---------------------------------------------------- deshacer (Personalizar)
    property var _snapshot: null
    property bool changed: false

    // Guarda cómo estaba todo al abrir Personalizar.
    function snapshot(): void {
        _snapshot = visualState();
        changed = false;
    }

    function undo(): void {
        if (!_snapshot)
            return;
        setMany(_snapshot);
        changed = false;
    }

    // Copia de las secciones visuales (sin las apps fijadas).
    function visualState(): var {
        const out = {};
        for (const sec of visualSections)
            out[sec] = _read(adapter[sec], defaults[sec]);
        out.appearance.wallpaper = adapter.appearance.wallpaper;
        out.ui = { style: adapter.ui.style };
        return out;
    }

    // Lee de un JsonObject las mismas claves que tiene `template`.
    function _read(node: var, template: var): var {
        const out = {};
        for (const k of Object.keys(template))
            out[k] = Array.isArray(template[k]) ? Array.from(node[k] ?? [])
                   : template[k] !== null && typeof template[k] === "object" ? _read(node[k], template[k]) : node[k];
        return out;
    }

    // ------------------------------------------------------------- escritura
    function _merge(target: var, src: var): void {
        for (const k of Object.keys(src)) {
            const v = src[k];
            if (v !== null && typeof v === "object" && !Array.isArray(v) && target[k] !== undefined && typeof target[k] === "object")
                _merge(target[k], v);
            else if (target[k] !== undefined)
                target[k] = v;
        }
    }

    function _deepMerge(a: var, b: var): var {
        const out = JSON.parse(JSON.stringify(a));
        for (const k of Object.keys(b || {})) {
            const v = b[k];
            out[k] = v !== null && typeof v === "object" && !Array.isArray(v) && typeof out[k] === "object"
                ? _deepMerge(out[k], v) : v;
        }
        return out;
    }

    // Pide a quantum-theme que regenere colores y configuraciones.
    function applyTheme(): void {
        applyTimer.restart();
    }

    function set(section: string, key: string, value: var): void {
        if (adapter[section] === undefined)
            return;
        adapter[section][key] = value;
        if (key !== "wallpaper" && key !== "iconTheme" && !["display", "mouse", "touchpad", "sounds", "apps", "notifications", "screensaver", "keyboard", "power"].includes(section))   // no son parte de los estilos
            adapter.ui.style = "custom";
        changed = true;
        root.save();
        applyTheme();
    }

    // Cambia una clave anidada: setPath("layout.topBar.floating", false)
    function setPath(dotted: string, value: var): void {
        const parts = dotted.split(".");
        let node = adapter;
        for (let i = 0; i < parts.length - 1; i++)
            node = node[parts[i]];
        node[parts[parts.length - 1]] = value;
        adapter.ui.style = "custom";
        changed = true;
        root.save();
        applyTheme();
    }

    // Mezcla varios ajustes de una vez (una sola escritura y un solo quantum-theme).
    function setMany(obj: var): void {
        if (!obj || typeof obj !== "object")
            return;
        for (const sec of Object.keys(obj))
            if (adapter[sec] !== undefined && typeof obj[sec] === "object")
                _merge(adapter[sec], obj[sec]);
        if (!obj.ui && Object.keys(obj).some(k => !["display", "mouse", "touchpad", "sounds", "notifications", "screensaver", "keyboard", "apps", "power"].includes(k)))
            adapter.ui.style = "custom";
        changed = true;
        root.save();
        applyTheme();
    }

    // Vuelve todo lo visual a como viene Quantum (incluido el fondo).
    function resetAll(): void {
        const v = _deepMerge(defaults, { appearance: { wallpaper: "quantum:live" } });
        v.ui = { style: "quantum" };
        setMany(v);
    }

    // Estado de la ventana Personalizar (no cambia el aspecto del escritorio).
    function setUi(key: string, value: var): void {
        adapter.ui[key] = value;
        root.save();
    }

    function setPinned(list: var): void {
        adapter.dock.pinned = list;
        root.save();
    }

    // Archivos y carpetas fijados al lado de la papelera (no son parte de los estilos)
    function setStacks(list: var): void {
        adapter.dock.stacks = list;
        root.save();
    }

    // Uso de apps (no cambia el estilo ni vuelve a aplicar el tema)
    function setUsage(usage: var): void {
        adapter.apps.usage = usage;
        root.save();
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.appearance.mode === "auto"
        onTriggered: themeProc.running = true
    }

    Timer {
        id: applyTimer
        interval: 250
        onTriggered: themeProc.running = true
    }

    Process {
        id: themeProc
        command: ["sh", "-c", "command -v quantum-theme >/dev/null && exec quantum-theme apply; exit 0"]
    }

    // Quien prefiere editar archivos: ~/.config/quantum/wayfire-user.ini se aplica al guardarlo
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quantum/wayfire-user.ini"
        watchChanges: true
        printErrors: false
        onFileChanged: root.applyTheme()
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // En un sistema nuevo el archivo aún no existe y no se puede vigilar: se crea
        // con los valores de fábrica para que los cambios de otros programas
        // (quantum-theme, Centro Quantum) lleguen al shell.
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) { root.loaded = true; writeAdapter(); } }
        // Barra de tareas de fábrica de la 1.0 (con Fotón y la Store): si nadie la
        // cambió, pasa a la nueva, más limpia. Si la personalizaste, no se toca.
        onLoaded: {
            root.loaded = true;
            let pins = adapter.dock.pinned ?? [];
            if (pins.join(",") === "org.gnome.Nautilus,firefox,foton,quantum-store,kitty,quantum-center")
                pins = ["org.gnome.Nautilus", "firefox", "kitty", "quantum-center"];
            // Personalizar se fija por su .desktop (quantum-personalize); antes se fijaba por la
            // ventana (org.quickshell), que no tiene .desktop y nunca aparecía en la barra.
            if (pins.includes("org.quickshell") && !pins.includes("quantum-personalize"))
                pins = pins.map(p => p === "org.quickshell" ? "quantum-personalize" : p);
            // Archivos (quantum-files) reemplaza a Nautilus en la barra, una sola vez
            if (!adapter.ui.filesPinned && pins.includes("org.gnome.Nautilus") && !pins.includes("quantum-files"))
                pins = pins.map(p => p === "org.gnome.Nautilus" ? "quantum-files" : p);
            if (pins.join(",") !== (adapter.dock.pinned ?? []).join(","))
                root.setPinned(pins);
            if (!adapter.ui.filesPinned) root.setUi("filesPinned", true);
        }

        JsonAdapter {
            id: adapter

            property JsonObject appearance: JsonObject {
                property string mode: "light"            // dark | light | auto (por horario)
                property string lightFrom: "07:00"       // modo auto: claro desde…
                property string lightTo: "18:00"         // …hasta
                property bool dynamicColors: false
                property string accent: "#6A5CFF"
                property string wallpaper: "quantum:live"
                property string iconTheme: "papirus"     // papirus | tela | fluent | whitesur | colloid | candy
                property real panelOpacity: 0.86
                property bool blur: true
                property real textScale: 1.0
                property bool darkerBars: false          // colores más oscuros en barra y Dock
                property bool wallpaperTint: true        // el fondo tiñe las ventanas
                property string scrollBars: "auto"       // auto | always | scrolling
                property bool scrollJump: false          // clic en la barra: saltar a la página siguiente
                // Efecto vidrio (Personalizar): qué partes son translúcidas con desenfoque
                property JsonObject glass: JsonObject {
                    property bool bar: true
                    property bool dock: true
                    property bool panels: true
                    property bool windows: false
                }
                property real windowOpacity: 0.9
            }
            property JsonObject windows: JsonObject {
                property bool tiling: false
                property string corners: "soft"          // sharp | soft | round
                property string animations: "normal"     // none | fast | normal | smooth
                property string openAnimation: "zoom"    // zoom | fade | fire | spin
                property string minimizeAnimation: "zoom" // zoom | squeezimize | none
                property bool buttonsLeft: false
                property bool wobbly: false
                property int titleHeight: 34
                property int borderSize: 1
                property string doubleClick: "fill"      // doble clic en la barra de título: fill | minimize | none (hyprbars)
            }
            property JsonObject keyboard: JsonObject {
                property string layout: ""
                property string variant: ""
                property string options: "grp:alt_shift_toggle"
                property int repeatRate: 25              // teclas por segundo al mantener pulsado (Hyprland input:repeat_rate)
                property int repeatDelay: 600            // ms antes de repetir (input:repeat_delay)
            }
            // Pantalla: luz nocturna y ajustes de imagen (los aplica quantum-display)
            property JsonObject display: JsonObject {
                property bool nightLight: false
                property string nightMode: "manual"      // manual | sunset | schedule
                property string nightFrom: "21:00"
                property string nightTo: "07:00"
                property int temperature: 4000           // kelvin (6500 = neutro)
                property real brightness: 1.0            // brillo por software (0.3..1)
                property real contrast: 1.0              // 0.5..1.5
                property real gamma: 1.0                 // 0.5..2
                property real saturation: 1.0            // 0..2 (filtro de Wayfire si no es 1)
                property var scales: ({})                // escala elegida por pantalla { "eDP-1": 1.25 } (HyprApply)
            }
            // Mouse y touchpad (van a la sección [input] de wayfire.ini)
            property JsonObject mouse: JsonObject {
                property real speed: 0                   // -1..1
                property bool accel: true                // false = perfil plano (sin aceleración)
                property bool natural: false
                property real scrollSpeed: 1.0
                property bool leftHanded: false
                property int cursorSize: 24
            }
            property JsonObject touchpad: JsonObject {
                property real speed: 0
                property bool tapToClick: true
                property bool natural: true
                property bool disableWhileTyping: true
                property real scrollSpeed: 1.0
                property string clickMethod: "clickfinger"   // clickfinger (dos dedos) | button-areas (esquina)
            }
            // Menu de apps: ids ocultos a mano y ids mostrados aunque el .desktop diga NoDisplay=true.
            // No toca los archivos .desktop del sistema.
            property JsonObject apps: JsonObject {
                property var hidden: []
                property var shown: []
                // veces que se abrió cada app: { "<id>": { n: veces, t: última vez (ms) } } → «Más usadas»
                property var usage: ({})
                property var login: []                   // apps que se abren al iniciar sesión (General → Elementos de inicio)
            }
            property JsonObject notifications: JsonObject {
                property bool dnd: false
                property var apps: []                    // apps que alguna vez avisaron (para la lista de Notificaciones)
                property var muted: []                   // apps sin avisos emergentes ni sonido
            }
            property JsonObject dock: JsonObject {
                // apps fijadas en la barra de tareas (ids de .desktop)
                property var pinned: ["quantum-files", "firefox", "kitty", "quantum-center", "quantum-personalize"]
                property string position: "bottom"       // bottom | top | left | right
                property string minimizeEffect: "genie"  // genie | scale: cómo se minimiza y restaura una ventana (minimize.lua + GenieFx)
                property bool floating: true
                property string align: "center"          // center | left
                property string size: "medium"           // small | medium | large
                property bool autohide: false
                property bool showSearch: true
                property bool showStart: true
                property bool showTray: true
                property bool showUpdates: true
                property bool showDownloads: true        // carpeta Descargas junto a la papelera
                property var stacks: []                  // archivos y carpetas fijados junto a la papelera (rutas; se sueltan desde el gestor de archivos)
                property bool magnify: true              // ampliación al pasar el mouse (como macOS)
                property real magnifyAmount: 0.55        // cuánto crece el ícono (0.1..1)
                property bool showIndicators: true       // punto bajo las apps abiertas
                property bool animateOpen: true          // el ícono rebota al abrir una app
            }
            property JsonObject layout: JsonObject {
                property JsonObject topBar: JsonObject {
                    property bool floating: true
                    property bool showApp: true
                    property bool showSysMon: true   // temperatura, CPU y RAM en la barra
                    property bool showNetSpeed: true // velocidad de subida/bajada de la red
                    property bool showClaude: true   // uso de Claude Code (5 h y 7 días)
                    property bool showSpotlight: true // botón de búsqueda (Spotlight)
                }
            }
            property JsonObject clock: JsonObject {
                property bool format24h: true
                property bool showDate: true
                property bool showSeconds: false
                property bool showWeekday: true          // «T7 31 thg 10» o «31 thg 10»
            }
            // Pantalla de bloqueo: tarjetas de cada lado (en orden) y privacidad
            property JsonObject lock: JsonObject {
                property var left: ["weather", "fetch", "media"]
                property var right: ["stats", "notifs"]
                property bool showNotifContent: false
                property string city: ""
            }
            // Màn hình chờ: mưa ký tự kiểu Matrix sau «timeout» giây không dùng máy
            property JsonObject screensaver: JsonObject {
                property bool enabled: true
                property int timeout: 600
            }
            // Batería: «Modo de bajo consumo» como en macOS (lo aplica HyprApply con power-profiles-daemon)
            property JsonObject power: JsonObject {
                property string lowPower: "never"        // never | always | battery | adapter
            }
            // Sonidos del sistema
            property JsonObject sounds: JsonObject {
                property string pack: "quantum"          // quantum | cristal | zen | espacial | minimo | burbujas | piano | synthwave
                property bool enabled: true
                property bool startup: true
                property real volume: 0.6
                property bool volumeFeedback: true       // sonar al cambiar el volumen
            }
            property JsonObject ui: JsonObject {
                property bool filesPinned: false         // ya se cambió Nautilus por Archivos en la barra
                property bool advanced: false
                property string style: "quantum"
                property string page: "general"
                property string lang: "vi"               // idioma de la interfaz: vi | en (I18n)
            }
        }
    }
}
