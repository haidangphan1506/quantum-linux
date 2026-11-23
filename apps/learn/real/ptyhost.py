#!/usr/bin/env python3
"""Chạy một lệnh trong PTY thật. stdin: mỗi dòng JSON {"i":"<base64>"} (phím) hoặc {"r":[hàng,cột]}.
stdout: mỗi dòng JSON {"o":"<base64>"} (đầu ra) và cuối cùng {"x":mã_thoát}."""
import os, sys, pty, json, base64, select, fcntl, termios, struct, signal

argv = sys.argv[1:]
rows, cols = 28, 100
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp(argv[0], argv)
def setsize(r, c):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", r, c, 0, 0))
    try: os.kill(pid, signal.SIGWINCH)
    except OSError: pass
setsize(rows, cols)
out = sys.stdout
inb = b""
while True:
    try:
        rl, _, _ = select.select([fd, 0], [], [])
    except InterruptedError:
        continue
    if fd in rl:
        try: d = os.read(fd, 65536)
        except OSError: d = b""
        if not d: break
        out.write(json.dumps({"o": base64.b64encode(d).decode()}) + "\n"); out.flush()
    if 0 in rl:
        d = os.read(0, 65536)
        if not d: break
        inb += d
        while b"\n" in inb:
            line, inb = inb.split(b"\n", 1)
            try: m = json.loads(line)
            except ValueError: continue
            if "i" in m: os.write(fd, base64.b64decode(m["i"]))
            elif "r" in m: setsize(int(m["r"][0]), int(m["r"][1]))
try: _, st = os.waitpid(pid, 0)
except ChildProcessError: st = 0
out.write(json.dumps({"x": os.waitstatus_to_exitcode(st)}) + "\n"); out.flush()
