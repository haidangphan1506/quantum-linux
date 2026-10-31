pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Uso del sistema para el panel de rendimiento. Solo mide mientras `active` es true
// (el panel abierto), así no gasta CPU en segundo plano.
Singleton {
    id: root

    property bool active: false
    property real cpu: 0            // 0..1
    property real ram: 0            // 0..1
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real disk: 0           // 0..1
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property real temp: 0           // °C (0 si no hay sensor)
    property var cpuHistory: []     // últimos 30 valores

    property var _prev: null

    Timer {
        interval: 1500
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            mem.reload();
            thermal.reload();
            if (!df.running)
                df.running = true;
        }
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
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
        }
    }

    // Temperatura: la primera zona térmica (CPU en casi todos los equipos)
    FileView {
        id: thermal
        path: "/sys/class/thermal/thermal_zone0/temp"
        printErrors: false
        onLoaded: root.temp = Number(text().trim()) / 1000
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
}
