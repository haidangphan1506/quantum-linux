pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Uso del sistema en tiempo real: CPU, RAM, disco, temperaturas (CPU/GPU/SSD),
// red, carga y tiempo encendido. Solo mide mientras alguien lo usa:
//  - `active`: el panel de rendimiento / tarjeta de bloqueo
//  - `barUsers`: la barra superior (contador, cada monitor suma 1)
//  - `detail`: el panel desplegable de la barra (añade la lista de procesos)
Singleton {
    id: root

    property bool active: false
    property int barUsers: 0
    property bool detail: false
    readonly property bool running: active || barUsers > 0 || detail

    property real cpu: 0            // 0..1
    property real cpuMhz: 0
    property int cores: 0
    property real ram: 0            // 0..1
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    property real disk: 0           // 0..1
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property real temp: 0           // °C de la CPU (0 si no hay sensor)
    property real gpuTemp: 0
    property real ssdTemp: 0
    property real netDown: 0        // bytes/s
    property real netUp: 0
    property real uptime: 0         // segundos
    property string load: ""        // "0.52  0.61  0.70"
    property var cpuHistory: []     // últimos 30 valores (0..1)
    property var ramHistory: []
    property var tempHistory: []    // °C
    property var procs: []          // [{ name, cpu, mem }] (solo con `detail`)

    // GPU (AMD, sysfs: gpu_busy_percent); gpuOk = false si no hay datos
    property bool gpuOk: false
    property real gpuBusy: 0        // 0..1
    property real gpuMhz: 0
    property real gpuMaxMhz: 0
    property real gpuVramUsedGb: 0
    property real gpuVramTotalGb: 0
    property real gpuPower: 0       // W
    property string gpuPerf: ""     // auto / low / high / manual …
    property var gpuHistory: []

    property var _prev: null
    property var _prevNet: null

    // Rutas de los sensores (hwmon cambia de número en cada arranque: se buscan por nombre)
    property string cpuSensor: ""
    property string gpuSensor: ""
    property string ssdSensor: ""

    function fmtRate(b: real): string {
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s";
        if (b >= 1024) return Math.round(b / 1024) + " KB/s";
        return Math.round(b) + " B/s";
    }

    function fmtUptime(s: real): string {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d > 0 ? d + " " + I18n.t("d") + " " : "") + (d > 0 || h > 0 ? h + " " + I18n.t("h") + " " : "") + m + " " + I18n.t("min");
    }

    // Nivel según la temperatura: 0 normal, 1 caliente, 2 muy caliente
    function tempLevel(t: real): int {
        return t >= 85 ? 2 : t >= 70 ? 1 : 0;
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            mem.reload();
            net.reload();
            up.reload();
            loadavg.reload();
            cpuinfo.reload();
            if (root.cpuSensor) cpuT.reload(); else thermal.reload();
            if (root.gpuSensor) gpuT.reload();
            if (root.ssdSensor) ssdT.reload();
            if (!gpuProc.running) gpuProc.running = true;
        }
    }

    // El disco cambia despacio: cada 30 s
    Timer {
        interval: 30000
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: if (!df.running) df.running = true
    }

    // Procesos que más CPU usan (solo con el panel abierto)
    Timer {
        interval: 3000
        repeat: true
        running: root.detail
        triggeredOnStart: true
        onTriggered: if (!ps.running) ps.running = true
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const lines = text().split("\n");
            const f = lines[0].trim().split(/\s+/).slice(1).map(Number);
            root.cores = lines.filter(l => /^cpu\d/.test(l)).length;
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            if (root._prev) {
                const dt = total - root._prev.total, di = idle - root._prev.idle;
                if (dt > 0) {
                    root.cpu = Math.max(0, Math.min(1, 1 - di / dt));
                    root.cpuHistory = root.cpuHistory.concat([root.cpu]).slice(-30);
                }
            }
            root._prev = { total, idle };
        }
    }

    FileView {
        id: mem
        path: "/proc/meminfo"
        onLoaded: {
            const v = {};
            for (const l of text().split("\n")) {
                const m = l.match(/^(\w+):\s+(\d+)/);
                if (m) v[m[1]] = Number(m[2]);
            }
            const total = v.MemTotal || 1, avail = v.MemAvailable || 0;
            root.ram = 1 - avail / total;
            root.ramTotalGb = total / 1048576;
            root.ramUsedGb = (total - avail) / 1048576;
            root.swapTotalGb = (v.SwapTotal || 0) / 1048576;
            root.swapUsedGb = ((v.SwapTotal || 0) - (v.SwapFree || 0)) / 1048576;
            root.ramHistory = root.ramHistory.concat([root.ram]).slice(-30);
        }
    }

    // Red: suma de las interfaces reales (sin lo/veth/docker), bytes/s desde la última lectura
    FileView {
        id: net
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const l of text().split("\n").slice(2)) {
                const m = l.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m || m[1] === "lo" || m[1].startsWith("veth") || m[1].startsWith("docker")) continue;
                const n = m[2].split(/\s+/).map(Number);
                rx += n[0]; tx += n[8];
            }
            const now = Date.now();
            if (root._prevNet) {
                const dt = (now - root._prevNet.t) / 1000;
                if (dt > 0) {
                    root.netDown = Math.max(0, (rx - root._prevNet.rx) / dt);
                    root.netUp = Math.max(0, (tx - root._prevNet.tx) / dt);
                }
            }
            root._prevNet = { rx, tx, t: now };
        }
    }

    FileView {
        id: up
        path: "/proc/uptime"
        onLoaded: root.uptime = Number(text().split(" ")[0])
    }

    FileView {
        id: loadavg
        path: "/proc/loadavg"
        onLoaded: root.load = text().split(" ").slice(0, 3).join("  ")
    }

    // Frecuencia media de los núcleos
    FileView {
        id: cpuinfo
        path: "/proc/cpuinfo"
        onLoaded: {
            const mhz = text().split("\n").filter(l => l.startsWith("cpu MHz")).map(l => Number(l.split(":")[1]));
            if (mhz.length) root.cpuMhz = mhz.reduce((a, b) => a + b, 0) / mhz.length;
        }
    }

    function setTemp(v: real): void {
        root.temp = v;
        root.tempHistory = root.tempHistory.concat([v]).slice(-30);
    }

    FileView {
        id: cpuT
        path: root.cpuSensor
        printErrors: false
        onLoaded: root.setTemp(Number(text().trim()) / 1000)
    }
    FileView {
        id: gpuT
        path: root.gpuSensor
        printErrors: false
        onLoaded: root.gpuTemp = Number(text().trim()) / 1000
    }
    FileView {
        id: ssdT
        path: root.ssdSensor
        printErrors: false
        onLoaded: root.ssdTemp = Number(text().trim()) / 1000
    }
    // Respaldo si no hay sensor de CPU conocido: la primera zona térmica
    FileView {
        id: thermal
        path: "/sys/class/thermal/thermal_zone0/temp"
        printErrors: false
        onLoaded: root.setTemp(Number(text().trim()) / 1000)
    }

    // Busca los sensores: «nombre|etiqueta|ruta» por cada temp*_input de hwmon
    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); for i in $h/temp*_input; do [ -f \"$i\" ] || continue; l=\"${i%_input}_label\"; echo \"$n|$(cat $l 2>/dev/null)|$i\"; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim().split("\n").filter(x => x).map(x => { const p = x.split("|"); return { n: p[0], l: p[1], p: p[2] }; });
                const find = (names, labels) => {
                    for (const n of names) {
                        const c = s.filter(x => x.n === n);
                        for (const l of labels) {
                            const hit = c.find(x => x.l === l);
                            if (hit) return hit.p;
                        }
                        if (c.length) return c[0].p;
                    }
                    return "";
                };
                root.cpuSensor = find(["k10temp", "coretemp", "zenpower", "cpu_thermal", "acpitz"], ["Tctl", "Tdie", "Package id 0"]);
                root.gpuSensor = find(["amdgpu", "nouveau", "radeon", "i915", "xe"], ["edge", "junction"]);
                root.ssdSensor = find(["nvme", "drivetemp"], ["Composite"]);
            }
        }
    }

    Process {
        id: df
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (n.length === 2 && n[0] > 0) {
                    root.diskTotalGb = n[0] / 1e9;
                    root.diskUsedGb = n[1] / 1e9;
                    root.disk = n[1] / n[0];
                }
            }
        }
    }

    Process {
        id: ps
        // top con dos muestras: la segunda es el uso actual (ps da el promedio desde que arrancó)
        command: ["sh", "-c", "top -bn2 -d0.6 -o %CPU -w 300 | awk '/^top -/{f++} f==2 && $1 ~ /^[0-9]+$/ {print $12\"|\"$9\"|\"$10; if(++n==5) exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                // %CPU de top es por núcleo: se divide para que sume como el total
                const n = Math.max(1, root.cores);
                root.procs = text.trim().split("\n").filter(x => x).map(l => {
                    const p = l.split("|");
                    return { name: p[0], cpu: Number(p[1].replace(",", ".")) / n, mem: Number(p[2].replace(",", ".")) };
                });
            }
        }
    }

    // Estado de la GPU: busy%|MHz actual|MHz máx|VRAM usada|VRAM total|potencia µW|nivel
    Process {
        id: gpuProc
        command: ["sh", "-c", "for d in /sys/class/drm/card*/device; do [ -f $d/gpu_busy_percent ] || continue; "
            + "m=$(grep -o '[0-9]*Mhz' $d/pp_dpm_sclk 2>/dev/null | tr -d 'Mhz'); "
            + "cur=$(grep '\\*' $d/pp_dpm_sclk 2>/dev/null | grep -o '[0-9]*Mhz' | tr -d 'Mhz'); "
            + "max=$(echo \"$m\" | sort -n | tail -1); "
            + "pw=$(cat $d/hwmon/hwmon*/power1_average 2>/dev/null | head -1); "
            + "echo \"$(cat $d/gpu_busy_percent)|$cur|$max|$(cat $d/mem_info_vram_used 2>/dev/null)|$(cat $d/mem_info_vram_total 2>/dev/null)|$pw|$(cat $d/power_dpm_force_performance_level 2>/dev/null)\"; exit; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("|");
                if (p.length < 7 || p[0] === "") { root.gpuOk = false; return; }
                root.gpuOk = true;
                root.gpuBusy = Math.max(0, Math.min(1, Number(p[0]) / 100));
                root.gpuMhz = Number(p[1]) || 0;
                root.gpuMaxMhz = Number(p[2]) || 0;
                root.gpuVramUsedGb = (Number(p[3]) || 0) / 1073741824;
                root.gpuVramTotalGb = (Number(p[4]) || 0) / 1073741824;
                root.gpuPower = (Number(p[5]) || 0) / 1e6;
                root.gpuPerf = p[6];
                root.gpuHistory = root.gpuHistory.concat([root.gpuBusy]).slice(-30);
            }
        }
    }
}
