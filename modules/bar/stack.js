.pragma library
// Iconos para los "stacks" del dock (archivos y carpetas fijados junto a la papelera).

function baseName(path) {
    const p = String(path || "").replace(/\/+$/, "");
    return p.slice(p.lastIndexOf("/") + 1) || p;
}

function isImage(mime) {
    return /^image\/(png|jpeg|gif|webp|bmp|svg\+xml|x-portable|tiff|avif)/.test(mime || "");
}

// icono de carpeta según su nombre (Descargas, Documentos…), como las carpetas de macOS
function folderIcon(path, home) {
    if (path === home) return "user-home";
    const n = baseName(path).toLowerCase();
    const map = {
        "downloads": "folder-download", "descargas": "folder-download", "tải về": "folder-download",
        "documents": "folder-documents", "documentos": "folder-documents", "tài liệu": "folder-documents",
        "pictures": "folder-pictures", "imágenes": "folder-pictures", "images": "folder-pictures", "ảnh": "folder-pictures",
        "music": "folder-music", "música": "folder-music", "nhạc": "folder-music",
        "videos": "folder-videos", "vídeos": "folder-videos", "video": "folder-videos",
        "desktop": "user-desktop", "escritorio": "user-desktop",
        "templates": "folder-templates", "public": "folder-publicshare",
    };
    return map[n] || "folder";
}

// nombre del icono del tema para un tipo MIME (image/png -> image-png)
function mimeIcon(mime) {
    if (!mime) return "unknown";
    if (mime === "inode/directory") return "folder";
    return mime.replace("/", "-");
}

// respaldo genérico si el tema no tiene el icono exacto del tipo
function mimeFallback(mime) {
    const top = String(mime || "").split("/")[0];
    if (top === "image") return "image-x-generic";
    if (top === "audio") return "audio-x-generic";
    if (top === "video") return "video-x-generic";
    if (top === "text") return "text-x-generic";
    if (/zip|tar|compressed|archive|x-7z|rar|xz|bzip|gzip|zstd/.test(mime)) return "package-x-generic";
    if (/spreadsheet|excel|csv/.test(mime)) return "x-office-spreadsheet";
    if (/presentation|powerpoint/.test(mime)) return "x-office-presentation";
    if (/word|opendocument.text|rtf/.test(mime)) return "x-office-document";
    return "application-x-generic";
}

// glifo de Material Symbols si no hay ningún archivo de icono
function mimeGlyph(mime) {
    const top = String(mime || "").split("/")[0];
    if (mime === "inode/directory") return "folder";
    if (top === "image") return "image";
    if (top === "audio") return "music_note";
    if (top === "video") return "movie";
    return "description";
}
