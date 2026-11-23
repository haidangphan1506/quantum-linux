#!/usr/bin/python3 -I
"""Trạng thái tiến trình + systemd + cổng lắng nghe của container, mỗi dòng một bản ghi cách nhau bằng TAB:
P pid ppid user ni stat tty sigign unit comm cmdline | S unit active sub enabled mainpid nrestarts result | L bind port pid"""
import os, re, subprocess, pwd

def run(*a):
    try: return subprocess.run(a, capture_output=True, text=True, timeout=10).stdout
    except Exception: return ""

me = os.getpid()
stat = {}
for ln in run("ps", "-eo", "pid=,stat=").splitlines():
    p = ln.split()
    if len(p) == 2: stat[p[0]] = p[1]
skip_comm = {"python3", "dump_state.py", "ps", "script", "docker"}
for d in sorted((x for x in os.listdir("/proc") if x.isdigit()), key=int):
    if int(d) == me: continue
    try:
        raw = open(f"/proc/{d}/stat").read()
        comm = raw[raw.index("(") + 1:raw.rindex(")")]
        rest = raw[raw.rindex(")") + 2:].split()
        ppid, tty_nr = rest[1], int(rest[4])
        if int(ppid) == 2 or int(d) == 2: continue
        cmd = open(f"/proc/{d}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
        if not cmd: continue                       # hilo del nhân
        if comm in skip_comm and ppid == str(me): continue
        st = open(f"/proc/{d}/status").read()
        uid = int(re.search(r"Uid:\s+(\d+)", st).group(1))
        try: user = pwd.getpwuid(uid).pw_name
        except KeyError: user = str(uid)
        sigign = int(re.search(r"SigIgn:\s+([0-9a-f]+)", st).group(1), 16)
        cg = open(f"/proc/{d}/cgroup").read()
        m = re.search(r"/([^/\n]+\.service)\b", cg)
        unit = m.group(1) if m else ""
        try: tty = os.readlink(f"/proc/{d}/fd/0").replace("/dev/", "") if tty_nr else "?"
        except OSError: tty = "?"
        if not tty.startswith("pts") and tty_nr: tty = "pts/0"
        ni = rest[16]
        print("\t".join(["P", d, ppid, user, ni, stat.get(d, rest[0]), tty if tty_nr else "?", str(sigign & 1), unit, comm, cmd]))
    except Exception:
        continue

names = set()
for ln in run("systemctl", "list-unit-files", "--no-legend", "--no-pager", "--type=service,timer").splitlines():
    p = ln.split()
    if p and p[1] not in ("static", "masked", "alias", "indirect", "generated", "transient") or (p and p[0].startswith(("ssh", "cron", "nginx"))):
        names.add(p[0])
for ln in run("systemctl", "list-units", "--all", "--no-legend", "--no-pager", "--plain", "--type=service,timer").splitlines():
    p = ln.split()
    if p and p[0].endswith((".service", ".timer")) and p[1] != "not-found": names.add(p[0])
for n in sorted(names):
    if n.startswith(("systemd-", "getty", "user@", "dbus", "apt-", "e2scrub", "fstrim", "man-db", "logrotate", "motd", "sshd-keygen")) and not n.startswith("systemd-journal"): continue
    out = run("systemctl", "show", n, "-p", "ActiveState,SubState,UnitFileState,MainPID,NRestarts,Result")
    kv = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
    if "@." in n or (kv.get("UnitFileState") in ("static", "masked", "alias", "indirect", "generated", "") and kv.get("ActiveState") == "inactive"):
        continue
    print("\t".join(["S", n, kv.get("ActiveState", "inactive"), kv.get("SubState", "dead"), kv.get("UnitFileState", "disabled") or "disabled",
                     kv.get("MainPID", "0"), kv.get("NRestarts", "0"), kv.get("Result", "success")]))

for ln in run("ss", "-tlnpH").splitlines():
    p = ln.split()
    if len(p) < 5: continue
    addr = p[3]; host, _, port = addr.rpartition(":")
    pids = re.findall(r"pid=(\d+)", ln)
    if pids: print("\t".join(["L", host.strip("[]") or "0.0.0.0", port, str(min(int(x) for x in pids))]))

# ---- ufw: trạng thái bật/tắt, chính sách mặc định, các luật đã thêm
st = run("ufw", "status")
active = "Status: active" in st
dflt = {}
try:
    for ln in open("/etc/default/ufw"):
        m = re.match(r'DEFAULT_(INPUT|OUTPUT)_POLICY="?(\w+)"?', ln.strip())
        if m: dflt[m.group(1)] = {"DROP": "deny", "ACCEPT": "allow", "REJECT": "reject"}.get(m.group(2), m.group(2).lower())
except OSError: pass
mlog = re.search(r"Logging:\s+(\w+)(?: \((\w+)\))?", run("ufw", "status", "verbose"))
print("\t".join(["G", (mlog.group(2) or "low") if mlog and mlog.group(1) == "on" else "off"]))
print("\t".join(["U", "1" if active else "0", dflt.get("INPUT", "deny"), dflt.get("OUTPUT", "allow")]))
for ln in run("ufw", "show", "added").splitlines():
    m = re.match(r"ufw\s+(?:route\s+)?(allow|deny|limit|reject)\s+(?:(in|out)\s+)?(.*)$", ln.strip())
    if not m: continue
    act, spec = m.group(1).upper(), m.group(3).strip()
    frm = "Anywhere"
    m2 = re.match(r"from\s+(\S+)(?:\s+port\s+\d+)?\s+to\s+(\S+)(?:\s+port\s+(\d+))?(?:\s+proto\s+(\w+))?", spec)
    if m2:
        frm = "Anywhere" if m2.group(1) == "any" else m2.group(1)
        to = m2.group(3) or "Anywhere"
        if m2.group(3) and m2.group(4): to += "/" + m2.group(4)
    else:
        to = re.sub(r"\s+comment\s+.*$", "", spec).strip("'\"")
    print("\t".join(["R", to, act, frm]))

# ---- ssh: chữ ký "đã nạp lại cấu hình" = PID chính + số lần nhận SIGHUP/khởi động lại trong nhật ký
j = run("journalctl", "-u", "ssh", "--no-pager", "-o", "cat")
mp = run("systemctl", "show", "ssh", "-p", "MainPID", "--value").strip()
print("\t".join(["X", mp, str(len(re.findall(r"SIGHUP|Started ssh|Reloaded", j)))]))
