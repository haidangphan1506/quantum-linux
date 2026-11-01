#!/usr/bin/env python3
"""Claude Code hook -> ~/.cache/claude-agentviz/state.json

Đăng ký cho các hook: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
PostToolUseFailure, SubagentStart, SubagentStop, Stop. Đọc JSON của hook từ stdin,
cập nhật trạng thái phiên (lead / subagent / advisor) để app Quickshell vẽ.
Khi có subagent bắt đầu chạy (tác vụ phức tạp) thì tự mở app nếu chưa mở.
Không bao giờ chặn Claude: mọi lỗi đều bị nuốt, luôn exit 0.
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", HOME + "/.cache"), "claude-agentviz")
STATE = os.path.join(DIR, "state.json")
APP = os.path.join(os.path.dirname(os.path.realpath(__file__)), "shell.qml")
ADVISORS = {"advisor"}


def short(model):
    m = (model or "").lower()
    for k in ("opus", "sonnet", "haiku", "fable"):
        if k in m:
            v = re.search(k + r"[-_ ]?(\d+)[-.](\d+)", m)
            return f"{k} {v.group(1)}.{v.group(2)}" if v else k
    return model or "?"


def agent_def_model(atype, cwd):
    """model: trong frontmatter của file agent (dự án trước, rồi ~/.claude)."""
    for base in (os.path.join(cwd or "", ".claude/agents"), HOME + "/.claude/agents"):
        p = os.path.join(base, atype + ".md")
        try:
            with open(p) as f:
                head = f.read(2000)
            m = re.search(r"^model:\s*(\S+)", head, re.M)
            if m:
                return m.group(1)
        except OSError:
            pass
    return {"Explore": "haiku"}.get(atype, "inherit")


def transcript_model(path):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 65536))
            tail = f.read().decode("utf-8", "ignore")
        found = re.findall(r'"model":"(claude-[^"]+)"', tail)
        return found[-1] if found else None
    except OSError:
        return None


def ensure_app():
    try:
        subprocess.Popen([HOME + "/.local/bin/claude-agentviz", "--quiet"], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception:
        pass


def main():
    ev = json.load(sys.stdin)
    name = ev.get("hook_event_name", "")
    sid = ev.get("session_id", "?")
    now = time.time()
    os.makedirs(DIR, exist_ok=True)
    launch = False

    with open(STATE + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            with open(STATE) as f:
                st = json.load(f)
        except (OSError, ValueError):
            st = {}
        sessions = st.setdefault("sessions", {})
        s = sessions.setdefault(sid, {
            "id": sid, "cwd": ev.get("cwd", ""), "model": "?", "effort": "",
            "busy": False, "turns": 0, "tools": 0, "errors": {}, "repeatError": "",
            "subs": {}, "pending": [], "advisor": {"calls": 0, "last": "", "at": 0},
            "promptAt": now, "phase": "idle",
        })
        s["at"] = now
        s["cwd"] = ev.get("cwd", s["cwd"])
        if ev.get("effort"):
            s["effort"] = ev["effort"].get("level", s["effort"])
        aid = ev.get("agent_id")
        sub = s["subs"].get(aid) if aid else None

        if name == "SessionStart":
            if ev.get("model"):
                s["model"] = short(ev["model"])
        elif name == "UserPromptSubmit":
            s.update(busy=True, promptAt=now, phase="lead", repeatError="", errors={})
            s["turns"] += 1
            # lượt mới: chỉ giữ subagent còn chạy
            s["subs"] = {k: v for k, v in s["subs"].items() if v["status"] == "running"}
            m = transcript_model(ev.get("transcript_path", ""))
            if m:
                s["model"] = short(m)
        elif name == "PreToolUse":
            if sub is not None:
                sub["tools"] += 1
                sub["tool"] = ev.get("tool_name", "")
            else:
                s["tools"] += 1
                s["busy"] = True
                if ev.get("tool_name") in ("Agent", "Task"):
                    ti = ev.get("tool_input") or {}
                    atype = ti.get("subagent_type") or "general-purpose"
                    model = ti.get("model") or ("inherit" if atype == "fork"
                                                else agent_def_model(atype, s["cwd"]))
                    s["pending"].append({"type": atype, "model": model,
                                         "desc": ti.get("description", ""),
                                         "bg": bool(ti.get("run_in_background"))})
                    s["pending"] = s["pending"][-20:]
        elif name in ("PostToolUse", "PostToolUseFailure"):
            if sub is None and name == "PostToolUseFailure":
                err = str(ev.get("error", ""))[:120]
                key = f'{ev.get("tool_name")}:{err}'
                s["errors"][key] = s["errors"].get(key, 0) + 1
                if s["errors"][key] >= 2:
                    s["repeatError"] = f'{ev.get("tool_name")}: {err}'
        elif name == "SubagentStart":
            atype = ev.get("agent_type", "?")
            p = next((x for x in s["pending"] if x["type"] == atype), None)
            if p:
                s["pending"].remove(p)
            model = (p or {}).get("model") or agent_def_model(atype, s["cwd"])
            if model == "inherit":
                model = s["model"]
            s["subs"][aid] = {"id": aid, "type": atype, "model": short(model),
                              "desc": (p or {}).get("desc", ""), "status": "running",
                              "tools": 0, "tool": "", "start": now, "end": 0,
                              "advisor": atype in ADVISORS, "fork": atype == "fork",
                              "bg": bool((p or {}).get("bg"))}
            s["phase"] = "advisor" if atype in ADVISORS else "swarm"
            launch = True
        elif name == "SubagentStop":
            if sub is None and aid:
                sub = s["subs"].setdefault(aid, {"id": aid, "type": ev.get("agent_type", "?"),
                                                 "model": "?", "desc": "", "tools": 0, "tool": "",
                                                 "start": now, "advisor": False, "fork": False})
            if sub is not None:
                sub.update(status="done", end=now, tool="")
                if sub.get("advisor"):
                    a = s["advisor"]
                    lines = [l.strip(" -*•\t") for l in (ev.get("last_assistant_message") or "").splitlines()
                             if l.strip()]
                    a.update(calls=a["calls"] + 1, at=now, last=lines[:3])
            if not any(v["status"] == "running" for v in s["subs"].values()):
                s["phase"] = "review" if s["subs"] else "lead"
        elif name == "Stop":
            s.update(busy=False, phase="done" if s["subs"] else "idle", doneAt=now)
            # lượt chính chỉ dừng khi subagent foreground đã xong (hoặc bị ngắt)
            for v in s["subs"].values():
                if v["status"] == "running" and not v.get("bg"):
                    v.update(status="done", end=now, tool="")
            m = transcript_model(ev.get("transcript_path", ""))
            if m:
                s["model"] = short(m)

        # giữ 8 phiên gần nhất trong 12 giờ
        keep = sorted(sessions.values(), key=lambda x: x.get("at", 0), reverse=True)[:8]
        st["sessions"] = {x["id"]: x for x in keep if now - x.get("at", 0) < 43200}
        st["active"] = sid
        st["at"] = now
        tmp = STATE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(st, f, ensure_ascii=False)
        os.replace(tmp, STATE)

    if launch:
        ensure_app()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
