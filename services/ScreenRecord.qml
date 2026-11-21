pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Trạng thái quay màn hình (scripts/screen-record.sh, gpu-screen-recorder): hiện chấm đỏ + thời gian
// trên thanh menu. Mỗi giây kiểm tra tiến trình; thời điểm bắt đầu lấy từ mtime của file trạng thái.
Singleton {
    id: root

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/screen-record.file"
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/screen-record.sh"

    property bool active: false
    property real startedAt: 0          // ms epoch
    property int seconds: 0
    readonly property string label: {
        const m = Math.floor(seconds / 60), s = seconds % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    // bấm lại để dừng và lưu (cùng nút bật/tắt với phím tắt)
    function stop(): void { Quickshell.execDetached([root.script]); }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (!probe.running) probe.running = true;
            if (root.active)
                root.seconds = Math.max(0, Math.floor((Date.now() - root.startedAt) / 1000));
        }
    }

    Process {
        id: probe
        command: ["sh", "-c", `pgrep -f '^gpu-screen-recorder' >/dev/null && { stat -c %Y '${root.stateFile}' 2>/dev/null || echo 1; } || echo 0`]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = parseInt(text.trim()) || 0;
                if (t <= 0) {
                    root.active = false;
                    root.seconds = 0;
                } else {
                    // t === 1: đang quay nhưng chưa có file trạng thái → tính từ lúc thấy đầu tiên
                    if (!root.active) root.startedAt = t > 1 ? t * 1000 : Date.now();
                    root.active = true;
                }
            }
        }
    }
}
