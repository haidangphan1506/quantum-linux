#!/usr/bin/env python3
"""Tim cac chuoi giao dien (tieng Tay Ban Nha) trong QML.

extract <root>            -> in JSON: [{file,line,start,end,s,ctx}]
apply <root> <keys.json>  -> boc cac chuoi co trong keys bang I18n.t("...")
"""
import json, os, re, sys

DATE_FMT = re.compile(r"^[dMyHhmsapAPz '\.:•,\-/]+$")
SKIP_LINE = re.compile(r"^\s*(import |//@|pragma )")
SKIP_CTX = ("font.family", "namespace:", "objectName", "target:", "localeCompare", "heuristicLookup",
            "DesktopEntries.byId", "Qt.locale(", "toLocale", ".toString(", "Sounds.play", "iconTheme")
SKIP_PREV = ("===", "!==", "==", "!=", "case", "indexOf(", "includes(", "startsWith(", "endsWith(", "split(",
             "replace(", "set(", "setUi(", "setPath(", "Settings.get(", "play(", "toggle(", "env(")
BRAND = {"Quantum", "Inter", "JetBrains Mono", "Material Symbols Rounded", "Caelestial", "Serpantium",
         "Quantum Linux", "Wi-Fi", "Bluetooth", "Ollama", "OK", "HH:mm", "Papirus", "Tela", "Fluent",
         "WhiteSur", "Colloid", "Candy"}


def strings(src):
    """Duyet ma nguon, bo qua comment, tra ve (start, end, value) cua chuoi "..." ."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            if i < 0: return
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c in "\"'`":
            q, j, buf = c, i + 1, []
            while j < n and src[j] != q:
                if src[j] == "\\":
                    buf.append(src[j:j + 2]); j += 2; continue
                buf.append(src[j]); j += 1
            if q == '"':
                yield i, j + 1, "".join(buf)
            i = j + 1
            continue
        i += 1


def is_ui(src, start, end, s):
    if not re.search(r"[A-Za-zÁÉÍÓÚáéíóúñÑ]", s): return False
    if s in BRAND or DATE_FMT.match(s) or "'de'" in s: return False
    if s.startswith(("/", "~", "$", "-", "#", "file:", "http", "qs.", "image:", "qrc:")): return False
    if re.search(r"[;|&$]|\\n.*sh|\.(svg|png|jpg|oga|json|ini|qml|desktop)$", s): return False
    if re.fullmatch(r"[a-z0-9_.\-:]+", s): return False            # identificadores, iconos, ids
    if re.fullmatch(r"[a-z]+[A-Z][A-Za-z]*", s): return False        # claves camelCase (showStart)
    if s in ("\\n", "Content-Type", "Escape") or re.fullmatch(r"[\w.\-]+/[\w.\-+]+", s) or s.startswith("org."): return False
    if re.fullmatch(r"[A-Za-z0-9_]+", s) and not re.search(r"[A-Z][a-z]", s): return False
    ls = src.rfind("\n", 0, start) + 1
    le = src.find("\n", end); le = len(src) if le < 0 else le
    line = src[ls:le]
    if SKIP_LINE.match(line) or any(k in line for k in SKIP_CTX): return False
    if re.search(r"command\s*:|execDetached|\bexec\(", line): return False
    before = src[ls:start].rstrip()
    after = src[end:le].lstrip()
    if any(before.endswith(p) for p in SKIP_PREV): return False
    if after.startswith(("===", "!==", "==", "!=")): return False
    if after.startswith(":") and (before.endswith("{") or before.endswith(",") or before == ""):
        return False                                               # clave de objeto
    if before.endswith("I18n.t("): return False                   # ya traducido
    return True


def scan(root):
    out = []
    for d, _, fs in os.walk(root):
        if "/.git" in d: continue
        for f in sorted(fs):
            if not f.endswith(".qml"): continue
            p = os.path.join(d, f)
            src = open(p, encoding="utf-8").read()
            for s0, e0, s in strings(src):
                if is_ui(src, s0, e0, s):
                    ln = src.count("\n", 0, s0) + 1
                    ls = src.rfind("\n", 0, s0) + 1
                    le = src.find("\n", e0)
                    out.append({"file": os.path.relpath(p, root), "line": ln, "start": s0, "end": e0,
                                "s": s, "ctx": src[ls:le].strip()[:160]})
    return out


def apply(root, keys):
    keys = set(keys)
    by = {}
    for h in scan(root):
        if h["s"] in keys: by.setdefault(h["file"], []).append(h)
    for f, hs in by.items():
        p = os.path.join(root, f)
        src = open(p, encoding="utf-8").read()
        for h in sorted(hs, key=lambda x: -x["start"]):
            src = src[:h["start"]] + "I18n.t(" + src[h["start"]:h["end"]] + ")" + src[h["end"]:]
        if not re.search(r"^import qs\.services\s*$", src, re.M):
            m = list(re.finditer(r"^import .*$", src, re.M))
            pos = m[-1].end() if m else 0
            src = src[:pos] + "\nimport qs.services" + src[pos:]
        open(p, "w", encoding="utf-8").write(src)
        print(f"{f}: {len(hs)}")


if __name__ == "__main__":
    if sys.argv[1] == "extract":
        json.dump(scan(sys.argv[2]), sys.stdout, ensure_ascii=False, indent=0)
    else:
        apply(sys.argv[2], json.load(open(sys.argv[3], encoding="utf-8")))
