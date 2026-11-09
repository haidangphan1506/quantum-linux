#!/usr/bin/env python3
# Uso de Claude Code para la barra de Quantum. Salida: un objeto JSON con:
#  - session: la sesión más reciente (contexto, coste, líneas…), según claude-statusline.py
#  - limits:  % usado de la ventana de 5 h y de 7 días (solo suscriptores; viene del statusLine)
#  - block / week: tokens sumados de los registros locales (~/.claude/projects), de respaldo
#    (ventana de 5 h como ccusage y 7 días). tokens = input + output + creación de caché.
import glob
import json
import os
import sys
import time
from datetime import datetime

PROJECTS = os.path.expanduser("~/.claude/projects")
STATE = os.path.expanduser("~/.local/state/quantum/claude")
BLOCK = 5 * 3600
WEEK = 7 * 24 * 3600


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def log_usage(now):
    since = now - WEEK
    # id de mensaje -> (ts, tokens); las entradas en streaming repiten el id, gana la última
    msgs = {}
    for path in glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True):
        try:
            if os.path.getmtime(path) < since:
                continue
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if '"usage"' not in line:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    m = o.get("message") or {}
                    u = m.get("usage")
                    ts = parse_ts(o.get("timestamp", ""))
                    if not u or ts is None or ts < since:
                        continue
                    tok = (u.get("input_tokens") or 0) + (u.get("output_tokens") or 0) \
                        + (u.get("cache_creation_input_tokens") or 0)
                    key = m.get("id") or o.get("uuid") or f"{path}:{ts}"
                    msgs[key] = (ts, tok)
        except OSError:
            continue

    entries = sorted(msgs.values())
    blocks = []
    for ts, tok in entries:
        if blocks and ts < blocks[-1]["end"]:
            b = blocks[-1]
        else:
            start = ts - (ts % 3600)
            b = {"start": start, "end": start + BLOCK, "tokens": 0, "msgs": 0}
            blocks.append(b)
        b["tokens"] += tok
        b["msgs"] += 1
    cur = blocks[-1] if blocks and now < blocks[-1]["end"] else None
    return {
        "block": {
            "active": cur is not None,
            "reset": int(cur["end"]) if cur else 0,
            "tokens": cur["tokens"] if cur else 0,
            "msgs": cur["msgs"] if cur else 0,
        },
        "week": {"tokens": sum(t for _, t in entries), "msgs": len(entries)},
    }


def statusline_state(now):
    sessions = []
    try:
        for path in glob.glob(os.path.join(STATE, "*.json")):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    sessions.append(json.load(f))
            except (OSError, ValueError):
                continue
    except OSError:
        pass
    sessions.sort(key=lambda s: s.get("updated", 0), reverse=True)

    # Los límites son de la cuenta: para cada ventana se toma la lectura más reciente.
    # Si esa ventana ya se reinició (resets <= ahora) y no hay lectura nueva, el uso es
    # desconocido (used = None): no se puede asumir 0 %, porque pudo usarse después del reinicio.
    # "read" es cuándo se leyó el valor (epoch s), para mostrar lo antiguo que es.
    limits = {}
    for k in ("five_hour", "seven_day"):
        for s in sessions:
            v = (s.get("limits") or {}).get(k)
            if v and v.get("used") is not None:
                reset = v.get("resets") or 0
                limits[k] = {
                    "used": v["used"] if reset > now else None,
                    "resets": reset,
                    "read": s.get("updated") or 0,
                }
                break
    limits = limits or None

    # Coste de las sesiones activas en la última ventana de 5 h (aproximado)
    recent = [s for s in sessions if now - s.get("updated", 0) < BLOCK]
    cost = sum(s.get("cost_usd") or 0 for s in recent)

    return {
        "session": sessions[0] if sessions else None,
        "limits": limits,
        "sessions_5h": len(recent),
        "cost_5h": round(cost, 2),
    }


def main():
    now = time.time()
    out = {"updated": int(now)}
    out.update(statusline_state(now))
    out.update(log_usage(now))
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
