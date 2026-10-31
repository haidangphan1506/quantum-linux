pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Historial del portapapeles (cliphist), para Super + V.
Singleton {
    id: root

    property var entries: []

    function refresh(): void {
        listProc.running = true;
    }

    function copy(entry: var): void {
        Quickshell.execDetached(["sh", "-c", `cliphist decode ${entry.id} | wl-copy`]);
    }

    function clear(): void {
        Quickshell.execDetached(["cliphist", "wipe"]);
        entries = [];
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.includes("\t")).slice(0, 80).map(l => {
                    const tab = l.indexOf("\t");
                    const preview = l.slice(tab + 1);
                    return {
                        id: l.slice(0, tab),
                        text: preview,
                        isImage: preview.startsWith("[[ binary data")
                    };
                });
            }
        }
    }
}
