#!/usr/bin/env python3
"""Quantum Task Manager - bộ thu thập số liệu.

Mỗi giây in ra 1 dòng JSON (stdout) với CPU, RAM, ổ đĩa, mạng, GPU, pin, cảm biến
và danh sách tiến trình (% CPU tính theo tổng CPU như Task Manager của Windows).
Chỉ đọc /proc và /sys, không cần thư viện ngoài. Lệnh từ stdin (mỗi dòng):
    interval <giây>      đổi tốc độ cập nhật (0.5 .. 5)
    procs on|off         bật/tắt thu danh sách tiến trình (tab Hiệu năng không cần)
"""
import json
import os
import pwd
import select
import socket
import sys
import time

HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def read_int(path, default=0):
    try:
        return int(read(path).strip() or default)
    except ValueError:
        return default


# ------------------------------------------------------------------ CPU
def cpu_times():
    out = []
    for line in read("/proc/stat").splitlines():
        if not line.startswith("cpu"):
            break
        f = line.split()
        v = list(map(int, f[1:9]))
        idle = v[3] + v[4]
        out.append((sum(v), idle))
    return out  # [total, cpu0, cpu1, ...]


def cpu_static():
    model = ""
    for line in read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            model = line.split(":", 1)[1].strip()
            break
    cores = set()
    for line in read("/proc/cpuinfo").splitlines():
        if line.startswith("core id"):
            cores.add(line.split(":")[1].strip())
    maxf = read_int("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq") / 1e6
    return {"model": model, "threads": NCPU, "cores": len(cores) or NCPU, "maxGHz": round(maxf, 2)}


def cpu_freq():
    fs = [read_int(f"/sys/devices/system/cpu/cpu{i}/cpufreq/scaling_cur_freq") for i in range(NCPU)]
    fs = [f for f in fs if f]
    return round(sum(fs) / len(fs) / 1e6, 2) if fs else 0


# ------------------------------------------------------------------ cảm biến
def hwmons():
    res = {}
    base = "/sys/class/hwmon"
    for h in sorted(os.listdir(base)):
        p = os.path.join(base, h)
        res.setdefault(read(p + "/name").strip(), p)
    return res


HW = hwmons()


def temp(name, idx=1):
    p = HW.get(name)
    if not p:
        return None
    v = read_int(f"{p}/temp{idx}_input", -1)
    return round(v / 1000, 1) if v >= 0 else None


# ------------------------------------------------------------------ RAM
def memory():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, v = line.split(":", 1)
        m[k] = int(v.split()[0]) * 1024
    total = m.get("MemTotal", 0)
    avail = m.get("MemAvailable", 0)
    return {
        "total": total, "used": total - avail, "avail": avail,
        "cached": m.get("Cached", 0) + m.get("SReclaimable", 0), "buffers": m.get("Buffers", 0),
        "shared": m.get("Shmem", 0), "dirty": m.get("Dirty", 0),
        "swapTotal": m.get("SwapTotal", 0), "swapUsed": m.get("SwapTotal", 0) - m.get("SwapFree", 0),
        "committed": m.get("Committed_AS", 0), "commitLimit": m.get("CommitLimit", 0),
    }


# ------------------------------------------------------------------ ổ đĩa
def disk_list():
    out = []
    for d in sorted(os.listdir("/sys/block")):
        if d.startswith(("loop", "ram", "zram", "dm-")):
            continue
        p = f"/sys/block/{d}"
        out.append({
            "name": d,
            "model": read(p + "/device/model").strip() or d,
            "size": read_int(p + "/size") * 512,
            "rotational": read_int(p + "/queue/rotational"),
            "ssd": "nvme" in d or not read_int(p + "/queue/rotational"),
        })
    return out


def diskstats():
    res = {}
    for line in read("/proc/diskstats").splitlines():
        f = line.split()
        if len(f) < 14:
            continue
        # sectores leídos (5), escritos (9), ms ocupado (12)
        res[f[2]] = (int(f[5]) * 512, int(f[9]) * 512, int(f[12]))
    return res


def mounts_usage():
    """Dung lượng theo phân vùng gắn (gộp theo thiết bị gốc)."""
    seen, out = set(), []
    for line in read("/proc/mounts").splitlines():
        dev, mnt, fstype = line.split()[:3]
        if not dev.startswith("/dev/") or dev in seen or fstype in ("squashfs",):
            continue
        seen.add(dev)
        try:
            st = os.statvfs(mnt)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        out.append({"dev": dev.split("/")[-1], "mount": mnt, "fs": fstype, "total": total, "used": total - free})
    return out


# ------------------------------------------------------------------ mạng
def netdev():
    res = {}
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, data = line.split(":", 1)
        name = name.strip()
        if name == "lo":
            continue
        f = data.split()
        res[name] = (int(f[0]), int(f[8]))
    return res


def net_info(name):
    p = f"/sys/class/net/{name}"
    kind = "Wi-Fi" if os.path.isdir(p + "/wireless") else ("Ethernet" if os.path.isdir(p + "/device") else "Ảo")
    ip = ""
    try:
        import fcntl
        import struct
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ip = socket.inet_ntoa(fcntl.ioctl(s.fileno(), 0x8915, struct.pack("256s", name[:15].encode()))[20:24])
        s.close()
    except OSError:
        pass
    ssid = ""
    if kind == "Wi-Fi":
        for line in read("/proc/net/wireless").splitlines()[2:]:
            if line.strip().startswith(name + ":"):
                pass
    return {"kind": kind, "ip": ip, "up": read(p + "/operstate").strip() == "up",
            "speed": read_int(p + "/speed", 0), "ssid": ssid}


# ------------------------------------------------------------------ GPU
def gpu():
    for c in sorted(os.listdir("/sys/class/drm")):
        p = f"/sys/class/drm/{c}/device"
        if not c.startswith("card") or "-" in c or not os.path.exists(p + "/gpu_busy_percent"):
            continue
        hw = HW.get("amdgpu")
        power = read_int(f"{hw}/power1_average", 0) or read_int(f"{hw}/power1_input", 0) if hw else 0
        return {
            "name": "AMD Radeon (iGPU)", "busy": read_int(p + "/gpu_busy_percent"),
            "vramUsed": read_int(p + "/mem_info_vram_used"), "vramTotal": read_int(p + "/mem_info_vram_total"),
            "gttUsed": read_int(p + "/mem_info_gtt_used"), "gttTotal": read_int(p + "/mem_info_gtt_total"),
            "temp": temp("amdgpu"), "power": round(power / 1e6, 1),
        }
    return None


def battery():
    for b in sorted(os.listdir("/sys/class/power_supply")):
        p = f"/sys/class/power_supply/{b}"
        if read(p + "/type").strip() != "Battery":
            continue
        return {"percent": read_int(p + "/capacity"), "status": read(p + "/status").strip(),
                "power": round(read_int(p + "/power_now") / 1e6, 1)}
    return None


# ------------------------------------------------------------------ tiến trình
USERS = {}


def username(uid):
    if uid not in USERS:
        try:
            USERS[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            USERS[uid] = str(uid)
    return USERS[uid]


def processes(prev, dt_total):
    out, cur = [], {}
    threads = 0
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                st = f.read()
            r = st.rindex(")")
            comm = st[st.index("(") + 1:r]
            f = st[r + 2:].split()
            state = f[0]
            ticks = int(f[11]) + int(f[12])
            nthreads = int(f[17])
            rss = int(f[21]) * PAGE
            uid = os.stat(f"/proc/{pid}").st_uid
        except (OSError, ValueError, IndexError):
            continue
        threads += nthreads
        cur[pid] = ticks
        p0 = prev.get(pid)
        cpu = 0.0
        if p0 is not None and dt_total > 0:
            # % de TODA la CPU (16 hilos = 100 %), như Windows
            cpu = 100.0 * (ticks - p0) / dt_total
        cmd = read(f"/proc/{pid}/cmdline").replace("\0", " ").strip()
        name = comm
        if cmd:
            exe = os.path.basename(cmd.split(" ")[0])
            if exe and len(comm) >= 15 and exe.startswith(comm[:15]):
                name = exe  # comm bị cắt 15 ký tự
        out.append({"pid": int(pid), "name": name, "cmd": cmd[:300], "user": username(uid),
                    "cpu": round(max(0.0, cpu), 1), "mem": rss, "threads": nthreads, "state": state,
                    "ppid": int(f[1])})
    return out, cur, threads


# ------------------------------------------------------------------ vòng lặp
def main():
    interval = 1.0
    want_procs = True
    static = {"cpu": cpu_static(), "disks": disk_list(), "host": socket.gethostname(),
              "kernel": os.uname().release}
    prev_cpu = cpu_times()
    prev_disk = diskstats()
    prev_net = netdev()
    _, prev_procs, _ = processes({}, 0)   # ticks iniciales
    t_prev = time.monotonic()
    tick = 0
    mounts = mounts_usage()

    while True:
        # comandos de la app (no bloqueante)
        r, _, _ = select.select([sys.stdin], [], [], interval)
        if r:
            line = sys.stdin.readline()
            if not line:
                return  # la app se cerró
            cmd = line.split()
            if len(cmd) == 2 and cmd[0] == "interval":
                interval = min(5.0, max(0.5, float(cmd[1])))
            elif len(cmd) == 2 and cmd[0] == "procs":
                want_procs = cmd[1] == "on"
            continue

        now = time.monotonic()
        dt = max(1e-3, now - t_prev)
        t_prev = now
        tick += 1

        cur_cpu = cpu_times()
        usage = []
        for (t1, i1), (t0, i0) in zip(cur_cpu, prev_cpu):
            dtt = t1 - t0
            usage.append(round(100.0 * (dtt - (i1 - i0)) / dtt, 1) if dtt > 0 else 0.0)
        dt_total_jiffies = cur_cpu[0][0] - prev_cpu[0][0]
        prev_cpu = cur_cpu

        cur_disk = diskstats()
        disks = []
        for d in static["disks"]:
            a, b = cur_disk.get(d["name"]), prev_disk.get(d["name"])
            if a and b:
                disks.append({"name": d["name"], "read": (a[0] - b[0]) / dt, "write": (a[1] - b[1]) / dt,
                              "busy": min(100.0, round((a[2] - b[2]) / (dt * 10), 1))})
        prev_disk = cur_disk
        if tick % 10 == 1:
            mounts = mounts_usage()

        cur_net = netdev()
        nets = []
        for name, (rx, tx) in cur_net.items():
            if name in prev_net:
                info = net_info(name) if tick % 5 == 1 or tick == 1 else None
                nets.append({"name": name, "rx": (rx - prev_net[name][0]) / dt, "tx": (tx - prev_net[name][1]) / dt,
                             "rxTotal": rx, "txTotal": tx, "info": info})
        prev_net = cur_net

        procs, threads = [], 0
        if want_procs or tick % 5 == 1:
            plist, prev_procs, threads = processes(prev_procs, dt_total_jiffies)
            procs = plist if want_procs else []
            nproc = len(plist)
        else:
            nproc = None

        load = read("/proc/loadavg").split()
        data = {
            "t": time.time(),
            "cpu": {"total": usage[0], "cores": usage[1:], "freq": cpu_freq(),
                    "temp": temp("k10temp"), "load": [float(x) for x in load[:3]]},
            "mem": memory(),
            "disks": disks, "mounts": mounts,
            "nvmeTemp": temp("nvme"),
            "net": nets,
            "gpu": gpu(),
            "bat": battery(),
            "uptime": float(read("/proc/uptime").split()[0]),
            "nproc": nproc, "nthreads": threads,
            "procs": procs,
        }
        if tick % 10 == 1:
            data["static"] = static
        sys.stdout.write(json.dumps(data, separators=(",", ":")) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
