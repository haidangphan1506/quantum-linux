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
    property alias ai: adapter.ai
    property alias sounds: adapter.sounds
    property alias display: adapter.display
    property alias mouse: adapter.mouse
    property alias touchpad: adapter.touchpad

    // Valores de fábrica de todo lo visual (= estilo «Quantum»). Los estilos se
    // aplican encima de esto, así un estilo siempre se ve igual.
    readonly property var defaults: ({
        appearance: { mode: "dark", dynamicColors: false, accent: "#6A5CFF", panelOpacity: 0.86, blur: true, textScale: 1.0,
                      glass: { bar: true, dock: true, panels: true, windows: false }, windowOpacity: 0.9 },
        layout: { style: "split", topBar: { floating: true, showApp: true } },
        dock: { floating: true, align: "center", size: "medium", autohide: false, showSearch: true, showStart: true, showTray: true, showUpdates: true },
        clock: { format24h: true, showDate: true, showSeconds: false },
        lock: { left: ["weather", "fetch", "media"], right: ["stats", "notifs"], showNotifContent: false, city: "" },
        windows: { tiling: false, corners: "soft", animations: "normal", openAnimation: "zoom", minimizeAnimation: "zoom", buttonsLeft: false,
                   wobbly: false, titleHeight: 34, borderSize: 1 }
    })
    readonly property var visualSections: ["appearance", "layout", "dock", "clock", "windows", "lock"]

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
        if (key !== "wallpaper" && key !== "iconTheme" && !["display", "mouse", "touchpad", "sounds"].includes(section))   // no son parte de los estilos
            adapter.ui.style = "custom";
        changed = true;
        file.writeAdapter();
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
        file.writeAdapter();
        applyTheme();
    }

    // Mezcla varios ajustes de una vez (una sola escritura y un solo quantum-theme).
    function setMany(obj: var): void {
        if (!obj || typeof obj !== "object")
            return;
        for (const sec of Object.keys(obj))
            if (adapter[sec] !== undefined && typeof obj[sec] === "object")
                _merge(adapter[sec], obj[sec]);
        if (!obj.ui && Object.keys(obj).some(k => !["display", "mouse", "touchpad", "sounds"].includes(k)))
            adapter.ui.style = "custom";
        changed = true;
        file.writeAdapter();
        applyTheme();
    }

    // Aplica un estilo (valores parciales) sobre los de fábrica; el fondo se conserva
    // salvo que el estilo traiga uno.
    function applyStyle(id: string, values: var): void {
        const v = _deepMerge(defaults, values || {});
        v.ui = { style: id };
        setMany(v);
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
        file.writeAdapter();
    }

    function setPinned(list: var): void {
        adapter.dock.pinned = list;
        file.writeAdapter();
    }

    Timer {
        id: applyTimer
        interval: 250
        onTriggered: themeProc.running = true
    }

    Process {
        id: themeProc
        command: ["quantum-theme", "apply"]
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
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }
        // Barra de tareas de fábrica de la 1.0 (con Fotón y la Store): si nadie la
        // cambió, pasa a la nueva, más limpia. Si la personalizaste, no se toca.
        onLoaded: {
            let pins = adapter.dock.pinned ?? [];
            if (pins.join(",") === "org.gnome.Nautilus,firefox,foton,quantum-store,kitty,quantum-center")
                pins = ["org.gnome.Nautilus", "firefox", "kitty", "quantum-center"];
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
                property string mode: "dark"
                property bool dynamicColors: false
                property string accent: "#6A5CFF"
                property string wallpaper: "quantum:live"
                property string iconTheme: "papirus"     // papirus | tela | fluent | whitesur | colloid | candy
                property real panelOpacity: 0.86
                property bool blur: true
                property real textScale: 1.0
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
            }
            property JsonObject keyboard: JsonObject {
                property string layout: ""
                property string variant: ""
                property string options: "grp:alt_shift_toggle"
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
            property JsonObject notifications: JsonObject {
                property bool dnd: false
            }
            property JsonObject dock: JsonObject {
                // apps fijadas en la barra de tareas (ids de .desktop)
                property var pinned: ["quantum-files", "firefox", "kitty", "quantum-center"]
                property bool floating: true
                property string align: "center"          // center | left
                property string size: "medium"           // small | medium | large
                property bool autohide: false
                property bool showSearch: true
                property bool showStart: true
                property bool showTray: true
                property bool showUpdates: true
            }
            property JsonObject layout: JsonObject {
                property string style: "split"           // split (barra arriba + dock) | single (una barra abajo)
                property JsonObject topBar: JsonObject {
                    property bool floating: true
                    property bool showApp: true
                }
            }
            property JsonObject clock: JsonObject {
                property bool format24h: true
                property bool showDate: true
                property bool showSeconds: false
            }
            // Pantalla de bloqueo: tarjetas de cada lado (en orden) y privacidad
            property JsonObject lock: JsonObject {
                property var left: ["weather", "fetch", "media"]
                property var right: ["stats", "notifs"]
                property bool showNotifContent: false
                property string city: ""
            }
            // Asistente con IA local (Ollama): modelo elegido ("" = el primero instalado)
            property JsonObject ai: JsonObject {
                property string model: ""
            }
            // Sonidos del sistema
            property JsonObject sounds: JsonObject {
                property string pack: "quantum"          // quantum | cristal | zen | espacial | minimo | burbujas | piano | synthwave
                property bool enabled: true
                property bool startup: true
                property real volume: 0.6
            }
            property JsonObject ui: JsonObject {
                property bool welcomed: false            // ya pasó por la bienvenida del primer inicio
                property string shell: "caelestial"      // caelestial | serpantium (paso 3 de la bienvenida)
                property bool filesPinned: false         // ya se cambió Nautilus por Archivos en la barra
                property string serpApps: "bar"          // Serpantium: apps en la barra de arriba (bar) o en un dock abajo (dock)
                property var before: ({})                // fondo y colores de antes de Serpantium (para volver)
                property bool advanced: false
                property string style: "quantum"
                property string page: "styles"
            }
        }
    }
}
