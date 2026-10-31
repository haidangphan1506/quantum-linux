import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.services

// Màn hình chờ: sau Settings.screensaver.timeout giây không dùng máy, phủ mưa ký tự
// kiểu Matrix lên mọi màn hình. Chạm chuột/phím là tắt. Không bật khi có cửa sổ
// toàn màn hình hoặc trình duyệt/trình phát video đang phát. Thử: qs -c caelestia ipc call screensaver start
Scope {
    id: root

    property bool forced: false
    // Không tôn trọng idle-inhibit: Brave giữ nó cả khi chỉ mở một tab có âm thanh.
    // Thay vào đó: không bật khi có cửa sổ toàn màn hình (video, game).
    // Trình duyệt / trình phát video đang phát (MPRIS) cũng không bật; nhạc (Spotify…) thì vẫn bật.
    readonly property var videoApps: ["brave", "chrom", "firefox", "vivaldi", "opera", "edge", "zen", "librewolf",
                                      "mpv", "vlc", "celluloid", "totem", "showtime", "haruna", "smplayer", "kodi", "jellyfin"]
    readonly property bool videoPlaying: Mpris.players.values.some(p => {
        if (!p.isPlaying) return false;
        const id = ((p.desktopEntry || "") + " " + (p.identity || "") + " " + (p.dbusName || "")).toLowerCase();
        return videoApps.some(v => id.includes(v));
    })
    readonly property bool active: forced || (Settings.screensaver.enabled && root.isIdle
                                              && !(Wm.active?.fullscreen ?? false) && !videoPlaying)

    function stop(): void {
        forced = false;
    }

    // La inactividad la detecta un proceso aparte (tools/idle/shell.qml): IdleMonitor
    // revienta Quickshell al destruirse (cada recarga / al salir). Aquí solo se arranca.
    property bool isIdle: false
    Process {
        running: true
        command: ["qs", "-p", Quickshell.shellDir + "/tools/idle/shell.qml", "-n", "-d"]
    }

    IpcHandler {
        target: "screensaver"
        function start(): void { root.forced = true; }
        function stop(): void { root.stop(); }
        function toggle(): void { root.forced = !root.forced; }
        function idle(on: bool): void { root.isIdle = on; }
        function status(): string {
            return `timeout=${Settings.screensaver.timeout}s idle=${root.isIdle} video=${root.videoPlaying} fullscreen=${Wm.active?.fullscreen ?? false} active=${root.active} players=`
                + Mpris.players.values.map(p => `${p.identity}:${p.isPlaying ? "playing" : "stopped"}`).join(",");
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData

            screen: modelData
            visible: root.active || fade.opacity > 0.001
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quantum-screensaver"
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore

            Item {
                id: fade
                anchors.fill: parent
                opacity: root.active ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.active ? 1400 : 220
                        easing.type: root.active ? Easing.InOutQuad : Easing.OutQuad
                    }
                }

                // Bảng 64 ký tự (8x8) vẽ một lần rồi đưa vào shader
                Grid {
                    id: atlasItem
                    visible: false
                    columns: 8
                    Repeater {
                        model: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789$#@*"
                        Item {
                            required property string modelData
                            width: 72
                            height: 96
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: "white"
                                font.family: "Noto Serif"
                                font.pixelSize: 42
                            }
                        }
                    }
                }
                ShaderEffectSource {
                    id: atlas
                    sourceItem: atlasItem
                    hideSource: true
                    live: false
                    smooth: true
                    mipmap: true
                }

                ShaderEffect {
                    id: rain
                    anchors.fill: parent
                    property real time: 0
                    property size res: Qt.size(width, height)
                    property real cscale: Math.max(0.8, height / 1200)
                    property variant atlas: atlas
                    fragmentShader: Quickshell.shellDir + "/shaders/matrix.frag.qsb"
                }
                FrameAnimation {
                    running: win.visible
                    onTriggered: rain.time += frameTime
                }

                // ẩn con trỏ; di chuột/nhấn để tắt (khi bật bằng tay)
                MouseArea {
                    id: catcher
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.BlankCursor
                    property point last: Qt.point(-1, -1)
                    onPositionChanged: e => {
                        if (last.x >= 0 && (Math.abs(e.x - last.x) > 4 || Math.abs(e.y - last.y) > 4)) root.stop();
                        last = Qt.point(e.x, e.y);
                    }
                    onPressed: root.stop()
                }
                focus: true
                Keys.onPressed: root.stop()
            }

            onVisibleChanged: if (!visible) catcher.last = Qt.point(-1, -1)
        }
    }
}
