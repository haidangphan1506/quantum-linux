#!/usr/bin/env python3
# Uso de Claude Code para la barra de Quantum. Salida: un objeto JSON con:
#  - session: la sesión más reciente (contexto, coste, líneas…), según claude-statusline.py
#  - limits:  % usado de la ventana de 5 h y de 7 días (solo suscriptores; viene del statusLine)
#  - block / week: tokens sumados de los registros locales (~/.claude/projects), de respaldo
#    (ventana de 5 h como ccusage y 7 días). tokens = input + output + creación de caché;
#    además desglose (entrada/salida/caché), tokens por modelo, por día y ritmo (tokens/h).
import glob
import json
import os
import sys
import time
import urllib.request
from datetime import datetime

PROJECTS = os.path.expanduser("~/.claude/projects")
STATE = os.path.expanduser("~/.local/state/quantum/claude")
API_CACHE = os.path.join(STATE, "api-usage.cache")
API_TTL = 600  # s: cada cuánto se consulta la API cuando no hay sesión de Claude Code activa
CREDS = os.path.expanduser("~/.claude/.credentials.json")
WEEK_START_DAY = 2  # miércoles (lunes = 0)
RESET_HOUR = 4  # hora local a la que se reinicia el límite cada día
BLOCK = 5 * 3600
WEEK = 7 * 24 * 3600
CACHE_TTL_5M = 300    # s: caché de prompt efímero por defecto de Anthropic
CACHE_TTL_1H = 3600   # s: caché de 1 h (si la respuesta lo escribió así)


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _blank():
    return {"tokens": 0, "msgs": 0, "input": 0, "output": 0, "cache_write": 0, "cache_read": 0}


def _add(acc, e):
    acc["tokens"] += e["tok"]
    acc["msgs"] += 1
    for k in ("input", "output", "cache_write", "cache_read"):
        acc[k] += e[k]


def log_usage(now):
    since = now - WEEK
    # id de mensaje -> entrada; las entradas en streaming repiten el id, gana la última
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
                    cc = u.get("cache_creation") or {}
                    e = {
                        "ts": ts,
                        "model": m.get("model") or "",
                        "input": u.get("input_tokens") or 0,
                        "output": u.get("output_tokens") or 0,
                        "cache_write": u.get("cache_creation_input_tokens") or 0,
                        "cache_read": u.get("cache_read_input_tokens") or 0,
                        # TTL del caché escrito en esta respuesta: 1 h si se pidió, si no 5 min
                        "ttl": CACHE_TTL_1H if cc.get("ephemeral_1h_input_tokens") else CACHE_TTL_5M,
                    }
                    e["tok"] = e["input"] + e["output"] + e["cache_write"]
                    key = m.get("id") or o.get("uuid") or f"{path}:{ts}"
                    msgs[key] = e
        except OSError:
            continue

    entries = sorted(msgs.values(), key=lambda e: e["ts"])
    blocks = []
    for e in entries:
        if blocks and e["ts"] < blocks[-1]["end"]:
            b = blocks[-1]
        else:
            start = e["ts"] - (e["ts"] % 3600)
            b = {"start": start, "end": start + BLOCK, "first": e["ts"], **_blank()}
            blocks.append(b)
        _add(b, e)
        b["last"] = e["ts"]
    cur = blocks[-1] if blocks and now < blocks[-1]["end"] else None

    block = {"active": cur is not None, "reset": 0, "start": 0, "burn_per_h": 0, **_blank()}
    if cur:
        block.update({k: cur[k] for k in _blank()})
        block["reset"] = int(cur["end"])
        block["start"] = int(cur["start"])
        hours = max((now - cur["first"]) / 3600, 1 / 6)  # mínimo 10 min para no disparar la tasa
        block["burn_per_h"] = int(cur["tokens"] / hours)

    # Ciclo diario: el límite del usuario se reinicia cada día a las 04:00 (hora local)
    d4 = datetime.fromtimestamp(now).replace(hour=RESET_HOUR, minute=0, second=0, microsecond=0).timestamp()
    if d4 > now:
        d4 -= 86400
    since = _blank()
    since["start"] = int(d4)
    since["models"] = {}
    for e in entries:
        if e["ts"] >= d4:
            _add(since, e)
            n = e["model"] or "?"
            if not n.startswith("<"):
                mm = since["models"].setdefault(n, {"model": n, "tokens": 0, "msgs": 0})
                mm["tokens"] += e["tok"]
                mm["msgs"] += 1
    since["models"] = sorted(since["models"].values(), key=lambda m: m["tokens"], reverse=True)

    # Semana: empieza el último miércoles a las 04:00; 7 columnas (mié … mar), las futuras a 0
    w0 = d4 - ((datetime.fromtimestamp(d4).weekday() - WEEK_START_DAY) % 7) * 86400
    w0 = datetime.fromtimestamp(w0).replace(hour=RESET_HOUR, minute=0, second=0, microsecond=0).timestamp()
    week = _blank()
    week["start"] = int(w0)
    models = {}
    daily = [0] * 7
    for e in entries:
        if e["ts"] < w0:
            continue
        _add(week, e)
        name = e["model"] or "?"
        if name.startswith("<"):  # mensajes sintéticos
            continue
        mm = models.setdefault(name, {"model": name, "tokens": 0, "msgs": 0})
        mm["tokens"] += e["tok"]
        mm["msgs"] += 1
        d = int((e["ts"] - w0) // 86400)
        if 0 <= d < 7:
            daily[d] += e["tok"]
    week["daily"] = daily
    week["models"] = sorted(models.values(), key=lambda m: m["tokens"], reverse=True)

    # Caché del prompt: cada respuesta que lee o escribe caché la renueva, así que el último
    # uso de caché fija cuándo caduca. Tiempo restante = TTL - (ahora - último uso).
    cache = {"last": 0, "ttl": CACHE_TTL_5M, "left": 0}
    for e in reversed(entries):
        if e["cache_write"] or e["cache_read"]:
            ttl = e["ttl"]
            cache = {"last": int(e["ts"]), "ttl": ttl, "left": max(0, int(e["ts"] + ttl - now))}
            break

    return {"block": block, "week": week, "cache": cache, "since4": since}


def api_limits(now):
    """% de las ventanas 5 h / 7 d leído de la API de Anthropic (con el token de Claude Code),
    como mucho cada API_TTL s. Sirve cuando no hay ninguna sesión escribiendo el statusLine.
    Si falla (sin red, token caducado, 429) se devuelve la última lectura guardada."""
    cache = {}
    try:
        with open(API_CACHE, encoding="utf-8") as f:
            cache = json.load(f)
    except (OSError, ValueError):
        pass
    if now - cache.get("tried", 0) >= API_TTL:
        cache["tried"] = now  # también si falla: no insistir antes de API_TTL
        try:
            with open(CREDS, encoding="utf-8") as f:
                tok = json.load(f)["claudeAiOauth"]["accessToken"]
            req = urllib.request.Request(
                "https://api.anthropic.com/api/oauth/usage",
                headers={"Authorization": "Bearer " + tok, "anthropic-beta": "oauth-2025-04-20", "User-Agent": "quantum-bar"},
            )
            with urllib.request.urlopen(req, timeout=8) as r:
                d = json.load(r)
            lim = {}
            for k in ("five_hour", "seven_day"):
                v = d.get(k) or {}
                if v.get("utilization") is not None and v.get("resets_at"):
                    lim[k] = {"used": v["utilization"], "resets": int(parse_ts(v["resets_at"]) or 0), "read": int(now)}
            if lim:
                cache["limits"] = lim
        except Exception:
            pass
        try:
            os.makedirs(STATE, exist_ok=True)
            tmp = API_CACHE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(cache, f)
            os.replace(tmp, API_CACHE)
        except OSError:
            pass
    return cache.get("limits") or {}


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
    # Lectura de la API: se usa si es más reciente que la del statusLine (o si no hay ninguna)
    for k, v in api_limits(now).items():
        cur = limits.get(k)
        if not cur or v["read"] > cur["read"]:
            limits[k] = {"used": v["used"] if v["resets"] > now else None, "resets": v["resets"], "read": v["read"]}
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
