import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

// Quick Look: Space trong Thunar -> `qs -c caelestia ipc call preview open <ruta>`
// Anh/video hien trong cua so rieng; Space / Esc dong lai.
Scope {
    id: root

    property string path: ""
    property bool isVideo: false
    property bool isText: false
    property string pending: ""
    readonly property int maxChars: 200000

    readonly property var videoExt: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ogv", "flv", "wmv", "mpg", "mpeg"]
    readonly property var imageExt: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "tiff", "tif", "ico"]

    function open(p: string): void {
        const ext = p.split(".").pop().toLowerCase();
        const vid = videoExt.indexOf(ext) >= 0;
        if (!vid && imageExt.indexOf(ext) < 0) {
            // texto / config: por extension conocida, si no, preguntar a `file`
            const base = p.split("/").pop().toLowerCase();
            if (textExt.indexOf(ext) >= 0 || textNames.indexOf(base) >= 0) { show(p, false, true); return; }
            pending = p;
            probe.command = ["file", "-b", "--mime-type", "-L", p];
            probe.running = true;
            return;
        }
        show(p, vid, false);
    }

    function show(p: string, vid: bool, txt: bool): void {
        isVideo = vid;
        isText = txt;
        path = p;
    }

    // archivos de texto/config comunes (sin extension: textNames)
    readonly property var textExt: ["txt", "md", "markdown", "rst", "log", "conf", "cfg", "ini", "toml", "yaml", "yml", "json", "jsonc",
        "xml", "html", "htm", "css", "scss", "js", "mjs", "ts", "tsx", "jsx", "qml", "lua", "py", "sh", "bash", "zsh", "fish",
        "c", "h", "cpp", "hpp", "cc", "rs", "go", "java", "kt", "rb", "php", "pl", "sql", "csv", "tsv", "service", "timer",
        "desktop", "rules", "env", "properties", "diff", "patch", "tex", "vim", "nix", "cmake", "mk", "gradle", "lock", "list",
        "repo", "theme", "kdl", "rasi", "ron", "zig", "vue", "svelte", "pkgbuild", "srcinfo", "install", "mount", "socket", "target"]
    readonly property var textNames: ["makefile", "dockerfile", "pkgbuild", ".bashrc", ".zshrc", ".profile", ".bash_profile", ".gitignore",
        ".gitconfig", ".gitattributes", ".env", ".editorconfig", ".prettierignore", "readme", "license", "changelog", "authors",
        "fstab", "hosts", "crontab", "config", "mimeapps.list", "cmakelists.txt"]

    Process {
        id: probe
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim();
                if (m.startsWith("text/") || m === "application/json" || m === "application/xml" || m === "application/x-shellscript"
                    || m === "application/javascript" || m === "inode/x-empty")
                    root.show(root.pending, false, true);
            }
        }
    }

    IpcHandler {
        target: "preview"
        function open(file: string): void { root.open(file); }
        function close(): void { root.path = ""; }
    }

    LazyLoader {
        active: root.path !== ""

        FloatingWindow {
            id: win
            title: "Quick Look - " + root.path.split("/").pop()
            color: Theme.surface
            visible: true
            minimumSize: Qt.size(320, 240)
            onVisibleChanged: if (!visible) root.path = ""

            Shortcut { sequence: "Space"; onActivated: root.path = "" }
            Shortcut { sequence: "Escape"; onActivated: root.path = "" }

            Image {
                anchors.fill: parent
                visible: !root.isVideo && !root.isText
                source: root.isVideo || root.isText ? "" : "file://" + root.path
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true
            }

            Loader {
                anchors.fill: parent
                active: root.isText
                sourceComponent: Flickable {
                    id: fl
                    clip: true
                    contentWidth: Math.max(width, body.implicitWidth + 32)
                    contentHeight: body.implicitHeight + 32
                    boundsBehavior: Flickable.StopAtBounds

                    FileView {
                        id: fv
                        path: root.path
                        blockLoading: true
                    }
                    readonly property string raw: fv.text()
                    readonly property bool binary: raw.indexOf("\u0000") >= 0

                    TextEdit {
                        id: body
                        x: 16; y: 16
                        readOnly: true
                        selectByMouse: true
                        color: Theme.fg
                        font.family: "monospace"
                        font.pixelSize: 13
                        wrapMode: TextEdit.NoWrap
                        text: fl.binary ? "(binary)" : fl.raw.length > root.maxChars
                            ? fl.raw.slice(0, root.maxChars) + "\n\n... (truncated)" : fl.raw
                    }
                }
            }

            Loader {
                anchors.fill: parent
                active: root.isVideo
                sourceComponent: Item {
                    MediaPlayer {
                        id: player
                        source: "file://" + root.path
                        videoOutput: out
                        audioOutput: AudioOutput {}
                        Component.onCompleted: play()
                    }
                    VideoOutput { id: out; anchors.fill: parent }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                    }
                }
            }
        }
    }
}
