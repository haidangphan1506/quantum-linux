#!/usr/bin/env python3
"""Claude Agent HQ - bộ thu thập dữ liệu cho app 3D (shell.qml).

Đọc thẳng transcript của Claude Code (~/.claude/projects/<dự án>/<phiên>.jsonl và
<phiên>/subagents/agent-*.jsonl), không cần hook. Mỗi dự án (cwd) = một văn phòng.

Thu được cho từng dự án / phiên:
  * token: input / output / cache read / cache write (khử trùng theo message.id), theo model, theo ngày
  * chi phí (cost-state cuối cùng của mỗi phiên, nếu Claude Code có ghi)
  * yêu cầu của người dùng (mỗi prompt = một việc đã giao) + token đã tiêu cho lượt đó
  * subagent (tool Agent/Task): loại, model, token, thời gian, trạng thái
  * todo (TodoWrite) và task (TaskCreate/TaskUpdate, có blockedBy) -> pending / running / blocked / done
  * trạng thái phiên: working / waiting (chờ duyệt quyền) / idle / offline

Chế độ:
  scan.py            in một lần JSON ra stdout
  scan.py --watch    chạy mãi, đọc tăng dần (chỉ phần mới ghi thêm), in một dòng JSON mỗi khi dữ liệu đổi
  scan.py --pretty   in một lần, có thụt lề (để xem bằng mắt)
Biến môi trường: CLAUDE_CONFIG_DIR (mặc định ~/.claude), AGENTHQ_INTERVAL (giây, mặc định 2).
"""
import glob
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
PROJECTS = os.path.join(CLAUDE, "projects")
INTERVAL = float(os.environ.get("AGENTHQ_INTERVAL", "2"))

LIVE_SECS = 120          # transcript ghi trong khoảng này coi như phiên còn sống (khi không thấy tiến trình)
WAIT_SECS = 12           # tool_use chưa có kết quả lâu hơn => đang chờ người dùng duyệt
MAX_TASKS = 400
MAX_REQ = 150
DAYS = 14
LONG_TOOLS = {"Agent", "Task", "Monitor", "TaskOutput", "WebFetch", "WebSearch"}   # chờ lâu là bình thường


def ts_of(s):
    if not s:
        return 0.0
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def clip(s, n):
    s = re.sub(r"\s+", " ", s or "").strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def short_model(m):
    m = (m or "").lower()
    if m.startswith("<"):          # "<synthetic>": thông báo do Claude Code tự sinh, không phải model
        return ""
    for k in ("opus", "sonnet", "haiku", "fable"):
        if k in m:
            v = re.search(k + r"[-_ ]?(\d+)[-.](\d+)", m)
            return f"{k} {v.group(1)}.{v.group(2)}" if v else k
    return m or "?"


def prompt_text(content):
    """Nội dung prompt người dùng -> chuỗi ngắn gọn (bỏ khối dán, đổi lệnh /slash)."""
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        content = " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    if not isinstance(content, str):
        return None
    t = content
    m = re.search(r"<command-name>(.*?)</command-name>", t, re.S)
    if m:
        a = re.search(r"<command-args>(.*?)</command-args>", t, re.S)
        return (m.group(1).strip() + " " + (a.group(1).strip() if a else "")).strip()
    t = re.sub(r"<pasted_content[^>]*>.*?</pasted_content>", " [dán] ", t, flags=re.S)
    t = re.sub(r"<system-reminder>.*?</system-reminder>", " ", t, flags=re.S)
    return t.strip()


ACTS = 8


def tool_sum(name, inp):
    """Tóm tắt một lần gọi tool thành một dòng ngắn (đang làm gì)."""
    name = name or ""
    g = inp.get
    fp = g("file_path") or g("notebook_path") or g("path")
    if name in ("Bash", "PowerShell", "bash"):
        s = g("description") or g("command")
    elif name in ("Read", "Edit", "Write", "NotebookEdit", "MultiEdit") and fp:
        s = "/".join(str(fp).rstrip("/").split("/")[-2:])
    elif name in ("Grep", "Glob"):
        s = (g("pattern") or "") + (" trong " + "/".join(str(fp).split("/")[-2:]) if fp else "")
    elif name == "WebFetch":
        s = re.sub(r"^https?://(www\.)?", "", g("url") or "")
    elif name == "WebSearch":
        s = g("query")
    elif name in ("Agent", "Task"):
        s = (g("subagent_type") or "agent") + ": " + (g("description") or "")
    elif name == "TodoWrite":
        cur = [t.get("activeForm") or t.get("content") for t in g("todos") or [] if t.get("status") == "in_progress"]
        s = cur[0] if cur else f"{len(g('todos') or [])} todo"
    elif name == "TaskCreate":
        s = g("subject")
    elif name == "TaskUpdate":
        s = f"#{g('taskId')} → {g('status') or 'cập nhật'}"
    elif name == "AskUserQuestion":
        q = g("questions") or []
        s = q[0].get("question") if q and isinstance(q[0], dict) else ""
    elif name == "Skill":
        s = g("skill")
    else:
        s = next((v for v in inp.values() if isinstance(v, str) and v.strip()), "")
    return clip(str(s or ""), 90)


def acts_out(tr, now_live):
    out = []
    for tid, name, summ, ts in tr.acts:
        res = tr.results.get(tid)
        st = "err" if res and res["err"] else "ok" if res else ("run" if now_live else "stop")
        out.append({"tool": name, "text": summ, "ts": ts, "st": st})
    return out[::-1]


def tok_total(u):
    return u[0] + u[1] + u[2] + u[3]


class Transcript:
    """Trạng thái đọc tăng dần của một file .jsonl (phiên chính hoặc subagent)."""

    def __init__(self, path):
        self.path = path
        self.offset = 0
        self.ino = None
        self.rest = b""
        self.mtime = 0.0
        self.sid = os.path.basename(path)[:-6]
        self.cwd = ""
        self.branch = ""
        self.title = ""
        self.last_prompt = ""
        self.model = ""
        self.first = 0.0
        self.last = 0.0
        self.cost = None
        self.usage = {}          # message.id -> [in, out, cache_read, cache_write, model, day, turn]
        self.turns = []          # yêu cầu: {ts, text, end, dur, stopped}
        self.tools = {}          # tool_use_id -> {name, input, ts, turn}
        self.results = {}        # tool_use_id -> {err, ts, tur}
        self.notified = set()    # tool_use_id đã có task-notification (subagent nền xong)
        self.todos = []
        self.task_ev = []        # (tool_use_id, name, input)
        self.last_kind = ""      # "assistant_end" | "assistant_tool" | "user" | "result"
        self.perm = ""           # permission mode gần nhất (auto / default / plan / acceptEdits / bypassPermissions)
        self.last_entry = 0.0
        self.acts = []           # hành động gần nhất: [tool_use_id, tool, tóm tắt, ts]
        self.last_text = ""      # câu trả lời / lời dẫn gần nhất của Claude
        self.last_text_ts = 0.0

    # -------------------------------------------------------------- đọc
    def refresh(self):
        try:
            st = os.stat(self.path)
        except OSError:
            return False
        if self.ino is not None and (st.st_ino != self.ino or st.st_size < self.offset):
            self.__init__(self.path)          # file bị thay / cắt ngắn: đọc lại từ đầu
        self.ino = st.st_ino
        self.mtime = st.st_mtime
        if st.st_size == self.offset:
            return False
        with open(self.path, "rb") as f:
            f.seek(self.offset)
            data = f.read()
        self.offset += len(data)
        data = self.rest + data
        lines = data.split(b"\n")
        self.rest = lines.pop()
        for ln in lines:
            if not ln.strip():
                continue
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            try:
                self.feed(d)
            except Exception:          # một dòng lạ không được làm hỏng cả file
                pass
        return True

    def feed(self, d):
        t = d.get("type")
        ts = ts_of(d.get("timestamp"))
        if ts:
            if not self.first:
                self.first = ts
            self.last = max(self.last, ts)
        if d.get("cwd") and not self.cwd:
            self.cwd = d["cwd"]
        if d.get("gitBranch"):
            self.branch = d["gitBranch"]
        if t == "ai-title":
            self.title = d.get("aiTitle") or self.title
        elif t == "last-prompt":
            self.last_prompt = d.get("lastPrompt") or self.last_prompt
        elif t == "permission-mode":
            self.perm = d.get("permissionMode") or self.perm
        elif t == "cost-state":
            self.cost = d.get("totalCostUSD", self.cost)
        elif t == "system" and d.get("subtype") == "turn_duration":
            if self.turns:
                self.turns[-1]["dur"] = (d.get("durationMs") or 0) / 1000
                self.turns[-1]["end"] = ts
        elif t == "assistant":
            self.on_assistant(d, ts)
        elif t == "user":
            self.on_user(d, ts)

    def on_assistant(self, d, ts):
        m = d.get("message") or {}
        mdl = m.get("model") or ""
        if mdl and not mdl.startswith("<"):
            self.model = mdl
        u = m.get("usage")
        mid = m.get("id") or d.get("uuid")
        if u and mid:
            day = datetime.fromtimestamp(ts or time.time()).strftime("%Y-%m-%d")
            prev = self.usage.get(mid)
            self.usage[mid] = [u.get("input_tokens") or 0, u.get("output_tokens") or 0,
                               u.get("cache_read_input_tokens") or 0, u.get("cache_creation_input_tokens") or 0,
                               mdl, prev[5] if prev else day, prev[6] if prev else len(self.turns) - 1]
        self.last_entry = ts or self.last_entry
        has_tool = False
        for b in m.get("content") or []:
            if isinstance(b, dict) and b.get("type") == "text" and (b.get("text") or "").strip():
                self.last_text, self.last_text_ts = clip(b["text"], 240), ts
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            has_tool = True
            name, inp, tid = b.get("name"), b.get("input") or {}, b.get("id")
            self.tools[tid] = {"name": name, "input": inp, "ts": ts, "turn": len(self.turns) - 1}
            self.acts.append([tid, name, tool_sum(name, inp), ts])
            del self.acts[:-ACTS]
            if self.turns:
                tn = self.turns[-1]
                tn["tools"][name] = tn["tools"].get(name, 0) + 1
                fp = inp.get("file_path") or inp.get("notebook_path")
                if name in ("Edit", "Write", "NotebookEdit", "MultiEdit") and fp and fp not in tn["files"]:
                    tn["files"].append(fp)
            if name == "TodoWrite":
                self.todos = inp.get("todos") or []
            elif name in ("TaskCreate", "TaskUpdate"):
                self.task_ev.append([tid, name, inp])
        self.last_kind = "assistant_tool" if has_tool else "assistant_end"

    def on_user(self, d, ts):
        m = d.get("message") or {}
        c = m.get("content")
        self.last_entry = ts or self.last_entry
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    tid = b.get("tool_use_id")
                    tur = d.get("toolUseResult")
                    txt = b.get("content")
                    if isinstance(txt, list):
                        txt = " ".join(x.get("text", "") for x in txt if isinstance(x, dict))
                    self.results[tid] = {"err": bool(b.get("is_error")), "ts": ts,
                                         "tur": tur if isinstance(tur, dict) else None,
                                         "text": (txt or "")[:300] if isinstance(txt, str) else ""}
                    self.last_kind = "result"
            if self.last_kind == "result" and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                return
        origin = (d.get("origin") or {}).get("kind")
        txt = prompt_text(c)
        if txt is None:
            return
        if origin == "task-notification" or txt.startswith("<task-notification>"):
            for tid in re.findall(r"<tool-use-id>(.*?)</tool-use-id>", txt):
                self.notified.add(tid)
            return
        if txt.startswith("[Request interrupted"):
            if self.turns:
                self.turns[-1]["stopped"] = True
                self.turns[-1]["end"] = self.turns[-1]["end"] or ts
            return
        if d.get("isMeta") or d.get("isSidechain"):
            return
        if origin not in (None, "human") or txt.startswith("<") or txt.startswith("[Image: source"):
            return
        if not txt:
            return
        if self.turns and not self.turns[-1]["end"]:
            self.turns[-1]["end"] = ts
        self.turns.append({"ts": ts, "text": txt, "end": 0.0, "dur": 0.0, "stopped": False, "tools": {}, "files": [],
                           "cmd": bool(re.match(r"/[\w:-]+( |$)", txt)) and "<command-name>" in str(c)})
        self.last_kind = "user"

    # -------------------------------------------------------------- tổng hợp
    def tokens(self):
        tot = [0, 0, 0, 0]
        for u in self.usage.values():
            for i in range(4):
                tot[i] += u[i]
        return tot


def tok_dict(t):
    return {"in": t[0], "out": t[1], "cacheRead": t[2], "cacheWrite": t[3], "total": tok_total(t)}


def add_tok(a, b):
    for i in range(4):
        a[i] += b[i]


class Scanner:
    def __init__(self):
        self.files = {}           # path -> Transcript
        self.metas = {}           # path -> (mtime, dict)

    def meta(self, p):
        try:
            mt = os.stat(p).st_mtime
        except OSError:
            return {}
        c = self.metas.get(p)
        if c and c[0] == mt:
            return c[1]
        try:
            with open(p) as f:
                d = json.load(f)
        except (OSError, ValueError):
            d = {}
        self.metas[p] = (mt, d)
        return d

    def refresh(self):
        changed = False
        seen = set()
        for p in glob.glob(os.path.join(glob.escape(PROJECTS), "*", "*.jsonl")) + \
                glob.glob(os.path.join(glob.escape(PROJECTS), "*", "*", "subagents", "*.jsonl")):
            seen.add(p)
            tr = self.files.get(p)
            if tr is None:
                tr = self.files[p] = Transcript(p)
                changed = True
            if tr.refresh():
                changed = True
        for p in list(self.files):
            if p not in seen:
                del self.files[p]
                changed = True
        return changed

    @staticmethod
    def live_cwds():
        """cwd của các tiến trình claude đang chạy (~/.claude/sessions/<pid>.json)."""
        out = {}
        for p in glob.glob(os.path.join(glob.escape(CLAUDE), "sessions", "*.json")):
            pid = os.path.basename(p)[:-5]
            if not pid.isdigit():
                continue
            try:                      # pid đã chết (file sót lại) => /proc/<pid> không còn
                cwd = os.readlink(f"/proc/{pid}/cwd")
            except OSError:
                continue
            out[cwd] = out.get(cwd, 0) + 1
        return out

    # -------------------------------------------------------------- dựng JSON
    def build(self):
        now = time.time()
        today = datetime.now().strftime("%Y-%m-%d")
        days = [datetime.fromtimestamp(now - 86400 * i).strftime("%Y-%m-%d") for i in range(DAYS - 1, -1, -1)]
        live = self.live_cwds()

        mains = {}
        subs = {}                 # session id -> [(Transcript, meta)]
        for p, tr in self.files.items():
            parts = p.split(os.sep)
            if parts[-2] == "subagents":
                sid = parts[-3]
                m = self.meta(p[:-6] + ".meta.json")
                subs.setdefault(sid, []).append((tr, m))
            else:
                mains[tr.sid] = tr

        projects = {}
        for sid, tr in mains.items():
            if not tr.usage and not tr.turns:
                continue
            cwd = tr.cwd or "/" + os.path.basename(os.path.dirname(tr.path)).lstrip("-").replace("-", "/")
            pr = projects.get(cwd)
            if pr is None:
                pr = projects[cwd] = {"cwd": cwd, "sessions": [], "tok": [0, 0, 0, 0], "cost": 0.0,
                                      "models": {}, "daily": {d: [0, 0] for d in days}, "tasks": [], "agents": [],
                                      "requests": [], "last": 0.0}
            pr["sessions"].append((tr, subs.get(sid, [])))

        # tên văn phòng = thư mục cuối; trùng tên (vd. hai thư mục "ui") thì thêm thư mục cha
        names = {}
        for cwd in projects:
            b = os.path.basename(cwd.rstrip("/")) or "/"
            names[cwd] = "~" if cwd.rstrip("/") == HOME else b
        dup = {n for n in names.values() if list(names.values()).count(n) > 1}
        for cwd in projects:
            if names[cwd] in dup:
                names[cwd] = "/".join(cwd.rstrip("/").split("/")[-2:])
        out_projects = []
        g_tok = [0, 0, 0, 0]
        g_cost = 0.0
        g_counts = {k: 0 for k in ("pending", "running", "blocked", "done", "failed", "stopped")}
        g_today = 0
        g_live = 0
        for cwd, pr in projects.items():
            # phiên mới nhất trong cwd có tiến trình claude đang chạy => sống
            pr["sessions"].sort(key=lambda x: x[0].mtime, reverse=True)
            n_live_proc = live.get(cwd, 0)
            sess_out = []
            for idx, (tr, sublist) in enumerate(pr["sessions"]):
                age = now - tr.mtime
                is_live = (idx < n_live_proc and age < 6 * 3600) or age < LIVE_SECS
                pend = [tid for tid in tr.tools if tid not in tr.results]
                pend_names = [tr.tools[t]["name"] for t in pend if tr.tools[t]["ts"] >= tr.last_entry - 1]
                if not is_live:
                    state = "offline"
                elif tr.last_kind == "assistant_tool" and pend_names and age > WAIT_SECS \
                        and not any(n in LONG_TOOLS or (n in ("Bash", "PowerShell") and tr.perm in ("auto", "bypassPermissions"))
                                    for n in pend_names):
                    state = "waiting"
                elif tr.last_kind == "assistant_end" and age > 3:
                    state = "idle"
                else:
                    state = "working" if age < 90 or pend_names else "idle"
                if is_live:
                    g_live += 1
                s_tok = tr.tokens()
                s_counts = {k: 0 for k in g_counts}
                models = {}
                for u in tr.usage.values():
                    k = short_model(u[4])
                    if k:
                        models[k] = models.get(k, 0) + tok_total(u)
                    if u[5] in pr["daily"]:
                        pr["daily"][u[5]][0] += tok_total(u)
                        pr["daily"][u[5]][1] += u[1]
                    if u[5] == today:
                        g_today += tok_total(u)
                sess = {"id": tr.sid, "title": clip(tr.title or tr.last_prompt or (tr.turns[-1]["text"] if tr.turns else ""), 90),
                        "model": short_model(tr.model), "start": tr.first, "last": max(tr.last, 0) or tr.mtime,
                        "mtime": tr.mtime, "live": is_live, "state": state, "branch": tr.branch,
                        "waitingTool": pend_names[-1] if state == "waiting" else "",
                        "cost": tr.cost or 0.0, "requests": len(tr.turns)}
                acts = acts_out(tr, is_live)
                sess["activity"] = acts if (is_live or idx == 0) else acts[:3]
                cur_turn = tr.turns[-1] if tr.turns else None
                sess["current"] = clip(cur_turn["text"], 220) if cur_turn else ""
                sess["currentTs"] = cur_turn["ts"] if cur_turn else 0
                sess["lastText"] = tr.last_text
                if state == "waiting":
                    w = next((a for a in acts if a["st"] == "run"), acts[0] if acts else None)
                    sess["doing"] = {"tool": w["tool"], "text": w["text"], "ts": w["ts"]} if w else None
                elif state == "working" and acts:
                    sess["doing"] = {"tool": acts[0]["tool"], "text": acts[0]["text"], "ts": acts[0]["ts"]}
                else:
                    sess["doing"] = None

                # ---- subagent của phiên
                by_tool = {m.get("toolUseId"): (st, m) for st, m in sublist}
                sub_tok = [0, 0, 0, 0]
                agents = []
                for tid, tl in tr.tools.items():
                    if tl["name"] not in ("Agent", "Task") or "prompt" not in tl["input"]:
                        continue
                    inp = tl["input"]
                    res = tr.results.get(tid)
                    tur = (res or {}).get("tur") or {}
                    st, meta = by_tool.pop(tid, (None, {}))
                    a_tok = st.tokens() if st else [0, 0, 0, 0]
                    if res and res["err"]:
                        status = "failed"
                    elif res and tur.get("status") in ("completed", None) and not (tur.get("status") is None and st and not meta.get("finished", True)):
                        status = "done"
                    elif res and tur.get("status") == "async_launched":
                        status = "done" if (meta.get("finished") or tid in tr.notified) else \
                            ("running" if is_live and st and now - st.mtime < 600 else "stopped")
                    elif res:
                        status = "done" if meta.get("finished", True) else "running"
                    else:
                        status = "running" if is_live else "stopped"
                    end = res["ts"] if res and status != "running" else (st.last if st and status != "running" else 0)
                    if status == "done" and tur.get("status") == "async_launched" and st:
                        end = st.last
                    a_total = tok_total(a_tok) or tur.get("totalTokens") or 0
                    agents.append({"id": tid, "kind": "agent", "title": clip(inp.get("description") or inp.get("prompt"), 90),
                                   "detail": clip(inp.get("prompt"), 700), "type": inp.get("subagent_type") or "general-purpose",
                                   "model": short_model(tur.get("resolvedModel") or meta.get("pickedEffortModel") or (st.model if st else "") or inp.get("model")),
                                   "status": status, "ts": tl["ts"], "end": end, "tokens": a_total,
                                   "out": a_tok[1] or ((tur.get("usage") or {}).get("output_tokens") or 0),
                                   "tools": tur.get("totalToolUseCount") or (len(st.tools) if st else 0),
                                   "bg": tur.get("status") == "async_launched" or inp.get("run_in_background") is True,
                                   "session": tr.sid, "result": clip((tur.get("handbackReport") or {}).get("text") if isinstance(tur.get("handbackReport"), dict) else (res or {}).get("text"), 500),
                                   "activity": acts_out(st, status == "running")[:5] if st else [],
                                   "doing": (lambda a: {"tool": a[1], "text": a[2], "ts": a[3]})(st.acts[-1]) if st and st.acts and status == "running" else None})
                    add_tok(sub_tok, a_tok)
                    if st:
                        for u in st.usage.values():
                            k = short_model(u[4])
                            if k:
                                models[k] = models.get(k, 0) + tok_total(u)
                            if u[5] in pr["daily"]:
                                pr["daily"][u[5]][0] += tok_total(u)
                                pr["daily"][u[5]][1] += u[1]
                            if u[5] == today:
                                g_today += tok_total(u)
                # subagent có transcript nhưng không khớp tool_use (fork, phiên cũ ...): vẫn tính token
                for st, meta in by_tool.values():
                    a_tok = st.tokens()
                    add_tok(sub_tok, a_tok)
                    for u in st.usage.values():
                        k = short_model(u[4])
                        if k:
                            models[k] = models.get(k, 0) + tok_total(u)
                        if u[5] in pr["daily"]:
                            pr["daily"][u[5]][0] += tok_total(u)
                        if u[5] == today:
                            g_today += tok_total(u)
                    agents.append({"id": st.sid, "kind": "agent", "title": clip(meta.get("description") or meta.get("agentType") or st.sid, 90),
                                   "detail": "", "type": meta.get("agentType") or "?", "model": short_model(st.model),
                                   "status": "done" if meta.get("finished", True) or not is_live else "running",
                                   "ts": st.first, "end": st.last, "tokens": tok_total(a_tok), "out": a_tok[1],
                                   "tools": len(st.tools), "bg": False, "session": tr.sid, "result": ""})

                # ---- yêu cầu người dùng (mỗi prompt = một việc đã giao)
                turn_tok = {}
                for u in tr.usage.values():
                    turn_tok[u[6]] = turn_tok.get(u[6], 0) + tok_total(u)
                for i, tn in enumerate(tr.turns):
                    last = i == len(tr.turns) - 1
                    if tn["stopped"]:
                        status = "stopped"
                    elif last and state in ("working", "waiting"):
                        status = "blocked" if state == "waiting" else "running"
                    elif last and not tn["end"] and not is_live and tr.last_kind not in ("assistant_end",):
                        status = "stopped"
                    else:
                        status = "done"
                    n_ag = sum(1 for a in agents if tr.tools.get(a["id"], {}).get("turn") == i)
                    pr["requests"].append({"id": f"{tr.sid}:{i}", "kind": "command" if tn["cmd"] else "request",
                                           "title": clip(tn["text"], 110),
                                           "tools": dict(sorted(tn["tools"].items(), key=lambda x: -x[1])[:6]),
                                           "nTools": sum(tn["tools"].values()), "files": tn["files"][:12],
                                           "detail": clip(tn["text"], 900), "status": status, "ts": tn["ts"],
                                           "end": tn["end"], "dur": tn["dur"], "tokens": turn_tok.get(i, 0),
                                           "agents": n_ag, "session": tr.sid, "model": short_model(tr.model)})

                # ---- todo (TodoWrite) + task (TaskCreate/TaskUpdate)
                tasks = []
                tmap = {"pending": "pending", "in_progress": "running", "completed": "done"}
                for j, td in enumerate(tr.todos):
                    stt = tmap.get(td.get("status"), "pending")
                    if stt != "done" and not is_live:
                        stt = "stopped"
                    tasks.append({"id": f"{tr.sid}:todo{j}", "kind": "todo", "title": clip(td.get("content"), 110),
                                  "detail": clip(td.get("activeForm") or td.get("content"), 300), "status": stt,
                                  "ts": tr.last, "session": tr.sid})
                tk = {}
                seq = 0
                for tid, name, inp in tr.task_ev:
                    res = tr.results.get(tid)
                    if res and res["err"]:
                        continue
                    if name == "TaskCreate":
                        seq += 1
                        mt = re.search(r"#(\d+)", (res or {}).get("text") or "")
                        k = mt.group(1) if mt else str(seq)
                        tk[k] = {"subject": inp.get("subject") or "", "description": inp.get("description") or "",
                                 "status": "pending", "blockedBy": set(), "owner": inp.get("owner") or "",
                                 "ts": tr.tools[tid]["ts"]}
                    else:
                        k = str(inp.get("taskId") or "")
                        t = tk.get(k)
                        if t is None:
                            t = tk[k] = {"subject": f"Task #{k}", "description": "", "status": "pending",
                                         "blockedBy": set(), "owner": "", "ts": tr.tools[tid]["ts"]}
                        for f in ("subject", "description", "owner", "status"):
                            if inp.get(f):
                                t[f] = inp[f]
                        for b in inp.get("addBlockedBy") or []:
                            t["blockedBy"].add(str(b))
                for k, t in tk.items():
                    if t["status"] == "deleted":
                        continue
                    stt = tmap.get(t["status"], "pending")
                    blockers = [b for b in t["blockedBy"] if b in tk and tk[b]["status"] not in ("completed", "deleted")]
                    if stt == "pending" and blockers:
                        stt = "blocked"
                    if stt in ("pending", "running") and not is_live:
                        stt = "stopped" if stt == "running" else stt
                    tasks.append({"id": f"{tr.sid}:task{k}", "kind": "task", "title": clip(f"#{k} " + t["subject"], 110),
                                  "detail": clip(t["description"], 600), "status": stt, "ts": t["ts"],
                                  "blockedBy": ["#" + b for b in blockers], "owner": t["owner"], "session": tr.sid})
                # phiên đang chờ duyệt quyền => một mục "blocked" để thấy ngay
                if state == "waiting":
                    tasks.append({"id": f"{tr.sid}:wait", "kind": "permission", "title": f"Chờ duyệt: {sess['waitingTool']}",
                                  "detail": "Claude đang chờ bạn cho phép dùng tool này trong terminal.", "status": "blocked",
                                  "ts": tr.last_entry, "session": tr.sid})

                tot = list(s_tok)
                add_tok(tot, sub_tok)
                sess["tokens"] = tok_dict(tot)
                sess["turnTok"] = turn_tok.get(len(tr.turns) - 1, 0)
                sess["agents"] = len(agents)
                for it in tasks + agents + [r for r in pr["requests"] if r["session"] == tr.sid and r["kind"] == "request"]:
                    s_counts[it["status"]] = s_counts.get(it["status"], 0) + 1
                sess["counts"] = s_counts
                for k, v in models.items():
                    pr["models"][k] = pr["models"].get(k, 0) + v
                add_tok(pr["tok"], tot)
                pr["cost"] += tr.cost or 0.0
                pr["tasks"] += tasks
                pr["agents"] += agents
                pr["last"] = max(pr["last"], tr.mtime)
                sess_out.append(sess)

            counts = {k: 0 for k in g_counts}
            for it in pr["tasks"] + pr["agents"] + [r for r in pr["requests"] if r["kind"] == "request"]:
                counts[it["status"]] = counts.get(it["status"], 0) + 1
            for k in g_counts:
                g_counts[k] += counts.get(k, 0)
            states = [s["state"] for s in sess_out]
            pstate = next((s for s in ("waiting", "working", "idle") if s in states), "offline")
            order = {"blocked": 0, "running": 1, "pending": 2, "failed": 3, "stopped": 4, "done": 5}
            pr["tasks"].sort(key=lambda x: (order.get(x["status"], 9), -(x["ts"] or 0)))
            pr["agents"].sort(key=lambda x: (order.get(x["status"], 9), -(x["ts"] or 0)))
            pr["requests"].sort(key=lambda x: -(x["ts"] or 0))
            add_tok(g_tok, pr["tok"])
            g_cost += pr["cost"]
            out_projects.append({
                "key": cwd, "cwd": cwd, "name": names[cwd],
                "doing": next((dict(s["doing"], session=s["id"]) for s in sess_out if s.get("doing")), None),
                "short": cwd.replace(HOME, "~", 1), "state": pstate, "live": any(s["live"] for s in sess_out),
                "last": pr["last"], "tokens": tok_dict(pr["tok"]), "cost": round(pr["cost"], 4),
                "models": dict(sorted(pr["models"].items(), key=lambda x: -x[1])),
                "daily": [{"day": d, "total": pr["daily"][d][0], "out": pr["daily"][d][1]} for d in days],
                "counts": counts, "sessions": sess_out, "tasks": pr["tasks"][:MAX_TASKS],
                "agents": pr["agents"][:MAX_TASKS], "requests": pr["requests"][:MAX_REQ],
                "nRequests": len(pr["requests"]), "nAgents": len(pr["agents"]),
            })
        out_projects.sort(key=lambda p: -p["last"])
        return {"generated": now, "days": days,
                "totals": {"tokens": tok_dict(g_tok), "cost": round(g_cost, 4), "today": g_today, "projects": len(out_projects),
                           "sessions": sum(len(p["sessions"]) for p in out_projects), "live": g_live, "counts": g_counts},
                "projects": out_projects}


def main():
    sc = Scanner()
    if "--watch" not in sys.argv:
        sc.refresh()
        json.dump(sc.build(), sys.stdout, ensure_ascii=False, indent=1 if "--pretty" in sys.argv else None)
        print()
        return
    last = ""
    tick = 0
    parent = os.getppid()
    while True:
        if os.getppid() != parent:      # app (qs) đã thoát / bị kill: không để tiến trình mồ côi chạy mãi
            return
        changed = sc.refresh()
        tick += 1
        # dữ liệu không đổi vẫn dựng lại mỗi ~10 s: trạng thái working/idle/waiting phụ thuộc thời gian
        if changed or tick % 5 == 0 or not last:
            data = sc.build()
            body = json.dumps({k: v for k, v in data.items() if k != "generated"}, ensure_ascii=False, sort_keys=True)
            if body != last:
                last = body
                sys.stdout.write(json.dumps(data, ensure_ascii=False) + "\n")
                sys.stdout.flush()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
