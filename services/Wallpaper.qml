pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Fondos de video (mp4/webm/mkv/mov): el fondo de escritorio los reproduce en bucle y sin
// sonido; el resto (bloqueo, Mission Control, vistas previas) usa una imagen fija:
//   <carpeta>/thumbs/<nombre>.jpg         miniatura 480 px (selectores)
//   <carpeta>/thumbs/<nombre>.poster.jpg  fotograma a tamaño real
// Si faltan, prepare() los crea con ffmpeg y avisa con thumbsReady().
Singleton {
    id: root

    readonly property var videoExts: ["mp4", "webm", "mkv", "mov", "m4v"]
    // para `find`: -iname '*.mp4' -o ...
    readonly property string findExpr: ["png", "jpg", "jpeg", "webp"].concat(videoExts).map(e => `-iname '*.${e}'`).join(" -o ")

    signal thumbsReady

    function isVideo(path: string): bool {
        const m = /\.([^./]+)$/.exec(path ?? "");
        return !!m && videoExts.indexOf(m[1].toLowerCase()) >= 0;
    }

    function _thumbBase(path: string): string {
        const dir = path.substring(0, path.lastIndexOf("/"));
        const name = path.substring(path.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "");
        return dir + "/thumbs/" + name;
    }
    function thumb(path: string): string { return "file://" + _thumbBase(path) + ".jpg"; }

    // Imagen fija para mostrar el fondo donde no se reproduce video ("" si no hay fondo de archivo)
    function still(path: string): string {
        if (!path || !path.startsWith("/")) return "";
        return "file://" + (isVideo(path) ? _thumbBase(path) + ".poster.jpg" : path);
    }

    // crea miniatura y póster de los videos que no los tengan
    function prepare(paths: var): void {
        const vids = (paths ?? []).filter(p => isVideo(p));
        if (vids.length === 0 || gen.running) return;
        gen.command = ["sh", "-c",
            'for v in "$@"; do d=$(dirname "$v")/thumbs; n=$(basename "${v%.*}"); mkdir -p "$d"; ' +
            '[ -f "$d/$n.jpg" ] || ffmpeg -v error -y -ss 3 -i "$v" -frames:v 1 -vf scale=480:-2 "$d/$n.jpg" </dev/null; ' +
            '[ -f "$d/$n.poster.jpg" ] || ffmpeg -v error -y -ss 3 -i "$v" -frames:v 1 -q:v 2 "$d/$n.poster.jpg" </dev/null; done',
            "sh"].concat(vids);
        gen.running = true;
    }
    Process {
        id: gen
        onExited: root.thumbsReady()
    }
}
