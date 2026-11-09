#!/usr/bin/env python3
# statusLine de Claude Code: recibe por stdin el JSON de la sesión (contexto, límites
# 5 h / 7 días del suscriptor, coste…) y lo guarda en ~/.local/state/quantum/claude/<sesión>.json
# para que la barra de Quantum lo lea (services/ClaudeUsage.qml vía claude-usage.py).
# Imprime una línea corta, que Claude Code muestra debajo del chat. Nunca falla.
import json
import os
import sys
import time

STATE = os.path.expanduser("~/.local/state/quantum/claude")


# Mismas palabras que la barra de Quantum (idioma: ui.lang de ~/.config/quantum/settings.json)
LABELS = {
    "vi": {"ctx": "Ngữ cảnh", "5h": "5 giờ", "7d": "7 ngày"},
    "en": {"ctx": "Context", "5h": "5 h", "7d": "7 days"},
}


def lang():
    try:
        with open(os.path.expanduser("~/.config/quantum/settings.json"), encoding="utf-8") as f:
            return "en" if json.load(f).get("ui", {}).get("lang") == "en" else "vi"
    except (OSError, ValueError, AttributeError):
        return "vi"


def pct(v):
    return round(v, 1) if isinstance(v, (int, float)) else None


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        return

    ctx = d.get("context_window") or {}
    cur = ctx.get("current_usage") or {}
    size = ctx.get("context_window_size") or 0
    ctx_tokens = ctx.get("total_input_tokens")
    if ctx_tokens is None:
        ctx_tokens = sum((cur.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    used = pct(ctx.get("used_percentage"))
    if used is None and size and ctx_tokens:
        used = pct(ctx_tokens * 100 / size)

    rl = d.get("rate_limits") or {}
    cost = d.get("cost") or {}
    cache = d.get("prompt_cache") or {}
    sid = d.get("session_id") or "unknown"

    rec = {
        "updated": int(time.time()),
        "session_id": sid,
        "name": d.get("session_name") or "",
        "cwd": (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or "",
        "model": (d.get("model") or {}).get("display_name") or (d.get("model") or {}).get("id") or "",
        "ctx_pct": used,
        "ctx_tokens": ctx_tokens or 0,
        "ctx_size": size,
        "cost_usd": cost.get("total_cost_usd"),
        "duration_ms": cost.get("total_duration_ms"),
        "lines_added": cost.get("total_lines_added"),
        "lines_removed": cost.get("total_lines_removed"),
        "cache_warm": cache.get("warm") if cache.get("caching_observed") else None,
        "limits": {
            k: {"used": pct(rl[k].get("used_percentage")), "resets": rl[k].get("resets_at")}
            for k in ("five_hour", "seven_day") if isinstance(rl.get(k), dict)
        } or None,
    }

    try:
        os.makedirs(STATE, exist_ok=True)
        path = os.path.join(STATE, sid + ".json")
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(rec, f)
        os.replace(tmp, path)
    except OSError:
        pass

    L = LABELS[lang()]
    parts = []
    if used is not None:
        parts.append(f"{L['ctx']} {used:.0f}%")
    lim = rec["limits"] or {}
    if "five_hour" in lim and lim["five_hour"]["used"] is not None:
        parts.append(f"{L['5h']} {100 - lim['five_hour']['used']:.0f}%")
    if "seven_day" in lim and lim["seven_day"]["used"] is not None:
        parts.append(f"{L['7d']} {100 - lim['seven_day']['used']:.0f}%")
    if rec["cost_usd"] is not None:
        parts.append(f"${rec['cost_usd']:.2f}")
    print("  ·  ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
