pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Brillo de la pantalla del portátil (brightnessctl). En PCs de escritorio
// no hay dispositivo y `available` queda en false.
Singleton {
    id: root

    property bool available: false
    property real value: 0
    signal changed

    function set(v: real): void {
        if (!available)
            return;
        value = Math.max(0.01, Math.min(1, v));
        setProc.command = ["brightnessctl", "-c", "backlight", "set", Math.round(value * 100) + "%"];
        setProc.running = true;
        changed();
    }

    function step(delta: real): void {
        set(value + delta);
    }

    Process {
        id: readProc
        running: true
        command: ["brightnessctl", "-c", "backlight", "-m", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                // formato: dispositivo,clase,actual,porcentaje%,máximo
                const parts = text.trim().split(",");
                if (parts.length >= 5) {
                    root.available = true;
                    root.value = parseInt(parts[2]) / parseInt(parts[4]);
                }
            }
        }
    }

    Process {
        id: setProc
    }
}
