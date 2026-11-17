#!/usr/bin/env python3
"""Activity Monitor collector: lee /proc y emite 1 línea JSON por intervalo.
stdin: "interval <s>", "term <pid>", "kill <pid>"."""
import json, os, pwd, select, signal, sys, time

HZ = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1
PAGE = os.sysconf("SC_PAGE_SIZE")
interval = 2.0
_users = {}


def user_of(uid):
    if uid not in _users:
        try:
            _users[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            _users[uid] = str(uid)
    return _users[uid]


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def cpu_times():
    out = []
    for line in read("/proc/stat").splitlines():
        if line.startswith("cpu"):
            p = line.split()
            v = list(map(int, p[1:9]))
            out.append((p[0], v))
    return out


def meminfo():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) * 1024
    return m


def net_bytes():
    rx = tx = rp = tp = 0
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, _, v = line.partition(":")
        if name.strip() == "lo":
            continue
        f = v.split()
        rx += int(f[0]); rp += int(f[1]); tx += int(f[8]); tp += int(f[9])
    return rx, tx, rp, tp


def disk_bytes():
    rd = wr = rops = wops = 0
    for line in read("/proc/diskstats").splitlines():
        f = line.split()
        name = f[2]
        # solo discos enteros (sda, nvme0n1, vda), no particiones/loop/ram
        if name.startswith(("loop", "ram", "dm-", "zram")):
            continue
        if name[-1].isdigit() and not name.startswith("nvme") and not name.startswith("mmcblk"):
            continue
        if ("p" in name[-3:] and name.startswith(("nvme", "mmcblk"))):
            continue
        rops += int(f[3]); rd += int(f[5]) * 512
        wops += int(f[7]); wr += int(f[9]) * 512
    return rd, wr, rops, wops


def scan_procs():
    procs = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        base = "/proc/" + pid
        try:
            stat = read(base + "/stat")
            if not stat:
                continue
            rp = stat.rindex(")")
            name = stat[stat.index("(") + 1:rp]
            f = stat[rp + 2:].split()
            ticks = int(f[11]) + int(f[12])
            threads = int(f[17])
            rss = int(f[21]) * PAGE
            state = f[0]
            uid = os.stat(base).st_uid
            io = {}
            for line in read(base + "/io").splitlines():
                k, _, v = line.partition(":")
                io[k] = int(v)
            procs[int(pid)] = dict(name=name, user=user_of(uid), ticks=ticks, threads=threads,
                                   mem=rss, state=state,
                                   rd=io.get("read_bytes", 0), wr=io.get("write_bytes", 0))
        except (OSError, ValueError, IndexError):
            continue
    return procs


def battery():
    for d in os.listdir("/sys/class/power_supply") if os.path.isdir("/sys/class/power_supply") else []:
        p = "/sys/class/power_supply/" + d
        if read(p + "/type").strip() == "Battery":
            try:
                return dict(pct=int(read(p + "/capacity")), status=read(p + "/status").strip())
            except ValueError:
                pass
    return None


def main():
    global interval
    prev_cpu = dict(cpu_times())
    prev_net = net_bytes()
    prev_disk = disk_bytes()
    prev_procs = scan_procs()
    t0 = time.monotonic()
    totals = [0, 0]  # bytes acumulados
    while True:
        r, _, _ = select.select([sys.stdin], [], [], interval)
        if r:
            line = sys.stdin.readline()
            if not line:
                return
            cmd = line.split()
            try:
                if cmd[0] == "interval":
                    interval = max(0.5, min(10.0, float(cmd[1])))
                elif cmd[0] in ("term", "kill"):
                    os.kill(int(cmd[1]), signal.SIGTERM if cmd[0] == "term" else signal.SIGKILL)
            except (IndexError, ValueError, OSError):
                pass
            continue
        now = time.monotonic()
        dt = max(0.001, now - t0)
        t0 = now

        cur = cpu_times()
        cores = []
        total = None
        for name, v in cur:
            p = prev_cpu.get(name)
            if not p:
                continue
            d = [a - b for a, b in zip(v, p)]
            s = sum(d[:8]) or 1
            idle = d[3] + d[4]
            user = d[0] + d[1]
            sysm = d[2] + d[5] + d[6]
            row = dict(user=100 * user / s, system=100 * sysm / s, idle=100 * idle / s)
            if name == "cpu":
                total = row
            else:
                cores.append(row)
        prev_cpu = dict(cur)

        rx, tx, rp, tp = net_bytes()
        net = dict(rx=(rx - prev_net[0]) / dt, tx=(tx - prev_net[1]) / dt,
                   rp=(rp - prev_net[2]) / dt, tp=(tp - prev_net[3]) / dt, rxTotal=rx, txTotal=tx)
        prev_net = (rx, tx, rp, tp)

        rd, wr, rops, wops = disk_bytes()
        disk = dict(read=(rd - prev_disk[0]) / dt, write=(wr - prev_disk[1]) / dt,
                    rops=(rops - prev_disk[2]) / dt, wops=(wops - prev_disk[3]) / dt,
                    readTotal=rd, writeTotal=wr)
        prev_disk = (rd, wr, rops, wops)

        mi = meminfo()
        mtotal = mi.get("MemTotal", 0)
        avail = mi.get("MemAvailable", 0)
        cached = mi.get("Cached", 0) + mi.get("SReclaimable", 0) - mi.get("Shmem", 0)
        mem = dict(total=mtotal, used=mtotal - avail, free=mi.get("MemFree", 0),
                   cached=max(0, cached), swapTotal=mi.get("SwapTotal", 0),
                   swapUsed=mi.get("SwapTotal", 0) - mi.get("SwapFree", 0),
                   buffers=mi.get("Buffers", 0))
        # presión de memoria (como macOS): % realmente en uso
        mem["pressure"] = 100 * (mtotal - avail) / mtotal if mtotal else 0

        procs = scan_procs()
        plist = []
        nthreads = 0
        for pid, p in procs.items():
            q = prev_procs.get(pid)
            cpu = 0.0
            rdr = wrr = 0.0
            if q:
                cpu = 100 * (p["ticks"] - q["ticks"]) / HZ / dt
                rdr = (p["rd"] - q["rd"]) / dt
                wrr = (p["wr"] - q["wr"]) / dt
            nthreads += p["threads"]
            plist.append(dict(pid=pid, name=p["name"], user=p["user"], cpu=round(cpu, 1),
                              mem=p["mem"], threads=p["threads"], state=p["state"],
                              rd=int(rdr), wr=int(wrr), rdTotal=p["rd"], wrTotal=p["wr"]))
        prev_procs = procs

        load = read("/proc/loadavg").split()[:3]
        out = dict(cpu=total or dict(user=0, system=0, idle=100), cores=cores, mem=mem,
                   net=net, disk=disk, procs=plist, nproc=len(plist), nthreads=nthreads,
                   load=[float(x) for x in load], ncpu=NCPU,
                   uptime=float(read("/proc/uptime").split()[0] or 0), battery=battery())
        sys.stdout.write(json.dumps(out, separators=(",", ":")) + "\n")
        sys.stdout.flush()


try:
    main()
except KeyboardInterrupt:
    pass
