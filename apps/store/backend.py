#!/usr/bin/env python3
"""Quantum Store backend: đọc pacman / AppStream / AUR và in ra JSON (1 lần gọi = 1 JSON).

  backend.py catalog [lang]   tất cả gói repo + gói đã cài + ứng dụng AppStream
  backend.py info <pkg>       chi tiết 1 gói (pacman -Qi / -Si, hoặc AUR nếu không có trong repo)
  backend.py aur <query>      tìm trên AUR (RPC v5)
  backend.py popularity       tải độ phổ biến (pkgstats.archlinux.de, % máy Arch cài gói đó), cache 7 ngày

Chỉ đọc, không bao giờ sửa hệ thống: cài/gỡ do Store.qml gọi pkexec pacman / paru.
AppStream (gói archlinux-appstream-data) là tuỳ chọn: có thì có icon, ảnh, danh mục.
"""
import glob, gzip, json, os, re, shutil, subprocess, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
import xml.etree.ElementTree as ET

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "quantum")
ENV = dict(os.environ, LC_ALL="C")
PKG_RE = re.compile(r"^[a-zA-Z0-9@_+][a-zA-Z0-9@._+-]*$")
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, env=ENV, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def out(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")


# ----------------------------------------------------------------------------- pacman
def parse_ss(text):
    """`pacman -Ss` / `-Qs`: 'repo/name ver (groups) [installed: x]' + dòng mô tả thụt vào."""
    res, cur = [], None
    for line in text.splitlines():
        if line.startswith("    "):
            if cur is not None:
                cur["d"] = line.strip()
            continue
        m = re.match(r"^(\S+)/(\S+) (\S+)(.*)$", line)
        if not m:
            continue
        repo, name, ver, rest = m.groups()
        inst = ""
        mi = re.search(r"\[installed(?:: (\S+))?\]", rest)
        if mi:
            inst = mi.group(1) or ver
        cur = {"n": name, "r": repo, "v": ver, "d": "", "i": inst}
        res.append(cur)
    return res


def pacman_catalog():
    repo = parse_ss(run("pacman", "-Ss"))
    local = parse_ss(run("pacman", "-Qs"))
    explicit = set(run("pacman", "-Qeq").split())
    by = {p["n"]: p for p in repo}
    for p in local:
        q = by.get(p["n"])
        if q is None:               # có cài nhưng không có trong repo nào: AUR / gói tự build
            p["r"] = "aur"
            p["i"] = p["v"]
            repo.append(p)
            by[p["n"]] = p
        else:
            q["i"] = p["v"]
    for p in repo:
        p["e"] = p["n"] in explicit
    return repo


def parse_info(text):
    """`pacman -Qi/-Si`: 'Key            : value' (giá trị nhiều dòng thụt vào)."""
    info, key = {}, None
    for line in text.splitlines():
        m = re.match(r"^([A-Za-z][A-Za-z ]*?)\s*: (.*)$", line)
        if m and not line.startswith(" "):
            key = m.group(1)
            info[key] = m.group(2).strip()
        elif key and line.startswith(" "):
            info[key] += "\n" + line.strip()
        elif not line.strip() and info:
            break                    # -Si có thể in nhiều repo: lấy cái đầu
    return info


def split_list(v):
    return [] if not v or v == "None" else v.split()


def cmd_info(pkg):
    if not PKG_RE.match(pkg):
        return out({"error": "invalid package name"})
    local = parse_info(run("pacman", "-Qi", pkg))
    sync = parse_info(run("pacman", "-Si", pkg))
    src = local or sync
    if not src:
        return out(aur_info(pkg))
    files = run("pacman", "-Qlq", pkg).split() if local else []
    desktop = [os.path.basename(f)[:-8] for f in files
               if f.startswith("/usr/share/applications/") and f.endswith(".desktop")]
    out({
        "name": src.get("Name", pkg),
        "version": src.get("Version", ""),
        "desc": src.get("Description", ""),
        "url": src.get("URL", "") if src.get("URL") != "None" else "",
        "licenses": src.get("Licenses", ""),
        "repo": sync.get("Repository", "aur" if local else ""),
        "depends": split_list(src.get("Depends On", "")),
        "optdepends": src.get("Optional Deps", "") if src.get("Optional Deps") != "None" else "",
        "requiredBy": split_list(local.get("Required By", "")),
        "installedSize": src.get("Installed Size", ""),
        "downloadSize": sync.get("Download Size", ""),
        "packager": src.get("Packager", ""),
        "buildDate": src.get("Build Date", ""),
        "installDate": local.get("Install Date", ""),
        "installed": bool(local),
        "installedVersion": local.get("Version", ""),
        "explicit": local.get("Install Reason", "").startswith("Explicitly"),
        "desktop": desktop,
    })


# ----------------------------------------------------------------------------- AUR
def aur_get(path):
    req = urllib.request.Request("https://aur.archlinux.org/rpc/v5/" + path,
                                 headers={"User-Agent": "quantum-store/1.0"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)


def cmd_aur(query):
    q = query.strip()
    if len(q) < 2:
        return out({"results": []})
    try:
        data = aur_get("search/" + urllib.parse.quote(q, safe="") + "?by=name-desc")
    except Exception as e:  # mạng, timeout, quá nhiều kết quả…
        return out({"error": str(e), "results": []})
    if data.get("type") == "error":
        return out({"error": data.get("error", ""), "results": []})
    res = sorted(data.get("results", []), key=lambda r: -(r.get("Popularity") or 0))[:80]
    out({"results": [{
        "n": r["Name"], "v": r.get("Version", ""), "d": r.get("Description") or "",
        "votes": r.get("NumVotes", 0), "pop": round(r.get("Popularity") or 0, 2),
        "ood": bool(r.get("OutOfDate")), "maint": r.get("Maintainer") or "",
    } for r in res]})


def aur_info(pkg):
    try:
        data = aur_get("info?arg[]=" + urllib.parse.quote(pkg, safe=""))
        r = (data.get("results") or [None])[0]
    except Exception as e:
        return {"error": str(e)}
    if not r:
        return {"error": "not found"}
    return {
        "name": r["Name"], "version": r.get("Version", ""), "desc": r.get("Description") or "",
        "url": r.get("URL") or "", "licenses": " ".join(r.get("License") or []), "repo": "aur",
        "depends": r.get("Depends") or [], "optdepends": "\n".join(r.get("OptDepends") or []),
        "requiredBy": [], "installedSize": "", "downloadSize": "",
        "packager": r.get("Maintainer") or "", "buildDate": "", "installDate": "",
        "installed": False, "installedVersion": "", "explicit": False, "desktop": [],
        "votes": r.get("NumVotes", 0), "ood": bool(r.get("OutOfDate")),
    }


# ----------------------------------------------------------------------------- độ phổ biến
# pkgstats: thống kê ẩn danh của người dùng Arch. Chỉ tải danh sách chung (không gửi gì về máy này).
POP_FILE = os.path.join(CACHE, "store-popularity.json")
POP_MAX_AGE = 7 * 86400


def popularity():
    try:
        with open(POP_FILE) as fh:
            return json.load(fh).get("pop", {})
    except (OSError, ValueError):
        return {}


def cmd_popularity():
    try:
        if time.time() - os.path.getmtime(POP_FILE) < POP_MAX_AGE:
            return out({"fresh": False})
    except OSError:
        pass
    pop = {}
    try:
        for offset in (0, 10000):
            req = urllib.request.Request(
                f"https://pkgstats.archlinux.de/api/packages?limit=10000&offset={offset}",
                headers={"User-Agent": "quantum-store/1.0", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.load(r)
            rows = data.get("packagePopularities", [])
            for row in rows:
                pop[row["name"]] = row.get("popularity", 0)
            if len(rows) < 10000:
                break
    except Exception as e:
        if not pop:
            return out({"fresh": False, "error": str(e)})
    os.makedirs(CACHE, exist_ok=True)
    tmp = POP_FILE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump({"pop": pop}, fh, separators=(",", ":"))
    os.replace(tmp, POP_FILE)
    out({"fresh": True, "count": len(pop)})


# ----------------------------------------------------------------------------- AppStream
XML_DIRS = ["/usr/share/swcatalog/xml", "/usr/share/app-info/xmls"]
ICON_DIRS = ["/usr/share/swcatalog/icons", "/usr/share/app-info/icons"]


def appstream_files():
    fs = []
    for d in XML_DIRS:
        fs += glob.glob(d + "/*.xml.gz") + glob.glob(d + "/*.xml")
    return sorted(fs)


def text_of(el):
    return "".join(el.itertext()).strip() if el is not None else ""


def localized(comp, tag, lang):
    best = None
    for el in comp.findall(tag):
        l = el.get(XML_LANG)
        if l is None and best is None:
            best = el
        elif l and lang and (l == lang or l.split("_")[0] == lang):
            return el
    return best


def description(comp, lang):
    el = localized(comp, "description", lang)
    if el is None:
        return ""
    parts = []
    for child in el:
        if child.tag == "p":
            parts.append(text_of(child))
        elif child.tag in ("ul", "ol"):
            parts.extend("• " + text_of(li) for li in child if li.tag == "li")
    return "\n\n".join(p for p in parts if p) or text_of(el)


def icon_for(comp, origin):
    stock = ""
    for ic in comp.findall("icon"):
        t, name = ic.get("type"), (ic.text or "").strip()
        if t == "cached" and name:
            for base in ICON_DIRS:
                for size in ("128x128", "64x64"):
                    p = os.path.join(base, origin, size, name)
                    if os.path.exists(p):
                        return {"file": p}
        elif t == "stock" and name:
            stock = name
    return {"name": stock} if stock else {}


# Icon cache của Arch là JPEG XL (.jxl): Qt chỉ đọc được nếu có plugin kimageformats.
# Không có thì đổi sang PNG một lần bằng djxl (libjxl) vào ~/.cache/quantum/store-icons.
ICON_CACHE = os.path.join(CACHE, "store-icons")


def qt_reads_jxl():
    return any(glob.glob(d + "/*jxl*") for d in ("/usr/lib/qt6/plugins/imageformats",
                                                  "/usr/lib/qt/plugins/imageformats"))


def to_png(src):
    dst = os.path.join(ICON_CACHE, os.path.basename(src).rsplit(".", 1)[0] + ".png")
    if os.path.exists(dst):
        return dst
    try:
        tmp = dst + ".tmp.png"
        subprocess.run(["djxl", src, tmp], capture_output=True, timeout=20, check=True)
        os.replace(tmp, dst)
        return dst
    except (OSError, subprocess.SubprocessError):
        return ""


def convert_icons(apps):
    todo = [a for a in apps.values() if a["icf"].endswith(".jxl")]
    if not todo or qt_reads_jxl():
        return
    if not shutil.which("djxl"):
        for a in todo:
            a["icf"] = ""
        return
    os.makedirs(ICON_CACHE, exist_ok=True)
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        for a, png in zip(todo, ex.map(lambda a: to_png(a["icf"]), todo)):
            a["icf"] = png


def keywords(comp, lang):
    ks = []
    for group in comp.iter("keywords"):
        gl = group.get(XML_LANG)
        for k in group.iter("keyword"):
            l = k.get(XML_LANG) or gl
            if l is None or (lang and l.split("_")[0] == lang):
                ks.append(text_of(k))
    return " ".join(dict.fromkeys(ks))[:300]


def parse_appstream(lang):
    apps = {}
    for f in appstream_files():
        try:
            fh = gzip.open(f) if f.endswith(".gz") else open(f, "rb")
            root = ET.parse(fh).getroot()
        except (OSError, ET.ParseError, EOFError):
            continue
        origin = root.get("origin", "")
        for comp in root.iter("component"):
            if comp.get("type") not in ("desktop-application", "desktop", "console-application"):
                continue
            pkg = text_of(comp.find("pkgname"))
            if not pkg or pkg in apps:
                continue
            ic = icon_for(comp, origin)
            shots = []
            for s in comp.iter("screenshot"):
                imgs = s.findall("image")
                src = next((i for i in imgs if i.get("type") == "source"), imgs[0] if imgs else None)
                if src is not None and src.text:
                    shots.append(src.text.strip())
                if len(shots) >= 5:
                    break
            launch = comp.find("launchable")
            apps[pkg] = {
                "p": pkg,
                "id": text_of(comp.find("id")),
                "n": text_of(localized(comp, "name", None)) or pkg,   # tên app giữ nguyên, không dịch
                "s": text_of(localized(comp, "summary", lang)),
                "desc": description(comp, lang),
                "c": [text_of(c) for c in comp.iter("category")],
                "k": keywords(comp, lang),
                "icf": ic.get("file", ""),
                "icn": ic.get("name", ""),
                "sh": shots,
                "u": text_of(comp.find("url[@type='homepage']")),
                "dsk": (launch.text or "").strip().removesuffix(".desktop") if launch is not None else "",
                "con": comp.get("type") == "console-application",
            }
    convert_icons(apps)
    return apps


def appstream_cached(lang):
    files = appstream_files()
    if not files:
        return {}
    stamp = [lang] + [[f, os.path.getmtime(f)] for f in files]
    path = os.path.join(CACHE, "store-appstream.json")
    try:
        with open(path) as fh:
            c = json.load(fh)
        if c.get("stamp") == stamp:
            return c["apps"]
    except (OSError, ValueError, KeyError):
        pass
    apps = parse_appstream(lang)
    try:
        os.makedirs(CACHE, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump({"stamp": stamp, "apps": apps}, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass
    return apps


def cmd_catalog(lang):
    pkgs = pacman_catalog()
    pop = popularity()
    for p in pkgs:
        if p["n"] in pop:
            p["pp"] = pop[p["n"]]
    apps = appstream_cached(lang)
    known = {p["n"] for p in pkgs}
    out({
        "pkgs": pkgs,
        # chỉ giữ ứng dụng mà pacman thật sự có (AppStream có thể cũ hơn database)
        "apps": [a for a in apps.values() if a["p"] in known],
        "appstream": bool(apps),
        "locked": os.path.exists("/var/lib/pacman/db.lck"),
        # multilib (steam, wine…) tắt theo mặc định trong /etc/pacman.conf
        "multilib": any(p["r"] == "multilib" for p in pkgs),
    })


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else ""
    if cmd == "catalog":
        cmd_catalog(a[1] if len(a) > 1 else "")
    elif cmd == "info" and len(a) > 1:
        cmd_info(a[1])
    elif cmd == "popularity":
        cmd_popularity()
    elif cmd == "aur" and len(a) > 1:
        cmd_aur(" ".join(a[1:]))
    else:
        out({"error": "usage: catalog [lang] | info <pkg> | aur <query>"})


if __name__ == "__main__":
    main()
