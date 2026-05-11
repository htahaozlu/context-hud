"""Aggregate Claude Code + Codex CLI token usage across all projects.

Stdout: single JSON document. Layout:

  {
    "claude":  AgentBlock,
    "codex":   AgentBlock,
    "collected_at": ISO8601,
    "source": "python3"
  }

AgentBlock contains:
  - Live HUD fields (used by ~/.zed-context/hud.json):
      session_5h_tokens, week_7d_tokens, active_session_tokens,
      active_session_file, last_turn_input_tokens, last_turn_output_tokens,
      last_model, last_context_window, last_context_pct, last_turn_at,
      last_cwd, active_session_started_at
  - Aggregates for the detail page:
      total_tokens_30d, total_sessions_30d,
      by_day:   [{date, tokens, sessions}]   (last 30 days)
      by_week:  [{week, tokens, sessions}]   (last 12 ISO weeks)
      by_month: [{month, tokens, sessions}]  (last 12 months)
      by_model: [{model, tokens, sessions}]  (all-time within scanned files)
      by_project:[{project, tokens, sessions}]
      recent_sessions: last 20 sessions {id, started_at, ended_at,
                       duration_minutes, tokens, model, project}

Why python3: aggregating dozens of multi-MB JSONL files from the wasm32
extension sandbox in pure Rust would duplicate logic python3 ships natively.
"""

import glob
import json
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone, timedelta

NOW = time.time()
WIN_SESSION = 5 * 3600
WIN_WEEK = 7 * 86400
WIN_30D = 30 * 86400


def parse_iso(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def empty_block():
    return {
        # live HUD
        "session_5h_tokens": 0,
        "week_7d_tokens": 0,
        "active_session_tokens": 0,
        "active_session_file": None,
        "active_session_started_at": None,
        "last_turn_input_tokens": 0,
        "last_turn_output_tokens": 0,
        "last_model": None,
        "last_context_window": None,
        "last_context_pct": None,
        "last_turn_at": None,
        "last_cwd": None,
        # aggregates
        "total_tokens_30d": 0,
        "total_sessions_30d": 0,
        "by_day": [],
        "by_week": [],
        "by_month": [],
        "by_model": [],
        "by_project": [],
        "recent_sessions": [],
    }


def claude_context_window(model):
    if not model:
        return 200000
    m = model.lower()
    if "[1m]" in m or "-1m" in m:
        return 1_000_000
    return 200_000


def project_name_from_cwd(cwd):
    if not cwd:
        return "—"
    return os.path.basename(cwd.rstrip("/")) or cwd


def bucket_aggregates(per_session, days=30, weeks=12, months=12):
    """Roll a list of session records into time buckets."""
    by_day = defaultdict(lambda: {"tokens": 0, "sessions": 0})
    by_week = defaultdict(lambda: {"tokens": 0, "sessions": 0})
    by_month = defaultdict(lambda: {"tokens": 0, "sessions": 0})
    by_model = defaultdict(lambda: {"tokens": 0, "sessions": 0})
    by_project = defaultdict(lambda: {"tokens": 0, "sessions": 0})

    total30 = 0
    sessions30 = 0
    cutoff30 = NOW - WIN_30D

    for s in per_session:
        ts = s["last_ts"]
        if ts is None:
            continue
        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        day = dt.strftime("%Y-%m-%d")
        # ISO week label e.g. 2026-W19
        iy, iw, _ = dt.isocalendar()
        week = f"{iy}-W{iw:02d}"
        month = dt.strftime("%Y-%m")

        by_day[day]["tokens"] += s["tokens"]
        by_day[day]["sessions"] += 1
        by_week[week]["tokens"] += s["tokens"]
        by_week[week]["sessions"] += 1
        by_month[month]["tokens"] += s["tokens"]
        by_month[month]["sessions"] += 1

        if s["model"]:
            by_model[s["model"]]["tokens"] += s["tokens"]
            by_model[s["model"]]["sessions"] += 1
        proj = project_name_from_cwd(s["cwd"])
        by_project[proj]["tokens"] += s["tokens"]
        by_project[proj]["sessions"] += 1

        if ts >= cutoff30:
            total30 += s["tokens"]
            sessions30 += 1

    def take(d, key_name, n, sort_key=None):
        items = [{key_name: k, **v} for k, v in d.items()]
        if sort_key:
            items.sort(key=sort_key, reverse=True)
        else:
            items.sort(key=lambda x: x["tokens"], reverse=True)
        return items[:n]

    return {
        "total_tokens_30d": total30,
        "total_sessions_30d": sessions30,
        "by_day": take(by_day, "date", days, sort_key=lambda x: x["date"]),
        "by_week": take(by_week, "week", weeks, sort_key=lambda x: x["week"]),
        "by_month": take(by_month, "month", months, sort_key=lambda x: x["month"]),
        "by_model": take(by_model, "model", 20),
        "by_project": take(by_project, "project", 20),
    }


def collect_claude():
    out = empty_block()
    home = os.environ.get("HOME", "")
    if not home:
        return out
    last_ts = 0.0
    per_session = {}  # path -> {first_ts, last_ts, tokens, model, cwd}

    for path in glob.glob(os.path.join(home, ".claude", "projects", "*", "*.jsonl")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_30D and NOW - mtime > WIN_WEEK:
            # skip very old for speed; still allow 30d scan above
            pass
        if NOW - mtime > WIN_30D:
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if '"usage"' not in line or '"assistant"' not in line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if obj.get("type") != "assistant":
                        continue
                    msg = obj.get("message") or {}
                    if not isinstance(msg, dict):
                        continue
                    usage = msg.get("usage") or {}
                    if not isinstance(usage, dict):
                        continue
                    inp = (
                        int(usage.get("input_tokens", 0) or 0)
                        + int(usage.get("cache_creation_input_tokens", 0) or 0)
                        + int(usage.get("cache_read_input_tokens", 0) or 0)
                    )
                    outp = int(usage.get("output_tokens", 0) or 0)
                    total = inp + outp
                    ts = parse_iso(obj.get("timestamp")) or mtime
                    age = NOW - ts

                    sess = per_session.setdefault(path, {
                        "first_ts": ts, "last_ts": ts, "tokens": 0,
                        "model": msg.get("model"), "cwd": obj.get("cwd"),
                    })
                    sess["first_ts"] = min(sess["first_ts"], ts)
                    sess["last_ts"] = max(sess["last_ts"], ts)
                    sess["tokens"] += total
                    if msg.get("model"):
                        sess["model"] = msg.get("model")
                    if obj.get("cwd"):
                        sess["cwd"] = obj.get("cwd")

                    if age <= WIN_WEEK:
                        out["week_7d_tokens"] += total
                    if age <= WIN_SESSION:
                        out["session_5h_tokens"] += total

                    if ts > last_ts:
                        last_ts = ts
                        out["last_turn_input_tokens"] = inp
                        out["last_turn_output_tokens"] = outp
                        out["last_model"] = msg.get("model")
                        out["last_turn_at"] = obj.get("timestamp")
                        out["last_cwd"] = obj.get("cwd")
                        out["active_session_file"] = path
                        window = claude_context_window(msg.get("model"))
                        out["last_context_window"] = window
                        raw_in = (
                            int(usage.get("input_tokens", 0) or 0)
                            + int(usage.get("cache_read_input_tokens", 0) or 0)
                            + int(usage.get("cache_creation_input_tokens", 0) or 0)
                        )
                        out["last_context_pct"] = round(raw_in / window * 100.0, 2) if window else None
        except OSError:
            continue

    if out["active_session_file"]:
        s = per_session.get(out["active_session_file"])
        if s:
            out["active_session_tokens"] = s["tokens"]
            out["active_session_started_at"] = datetime.fromtimestamp(
                s["first_ts"], tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    # Build aggregates from per_session list.
    sessions = []
    recent = []
    for path, s in per_session.items():
        sessions.append({
            "tokens": s["tokens"], "last_ts": s["last_ts"],
            "model": s["model"], "cwd": s["cwd"],
        })
        recent.append({
            "id": os.path.basename(path).rsplit(".", 1)[0],
            "started_at": datetime.fromtimestamp(s["first_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "ended_at": datetime.fromtimestamp(s["last_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "duration_minutes": round((s["last_ts"] - s["first_ts"]) / 60.0, 1),
            "tokens": s["tokens"],
            "model": s["model"] or "—",
            "project": project_name_from_cwd(s["cwd"]),
        })
    out.update(bucket_aggregates(sessions))
    recent.sort(key=lambda r: r["ended_at"], reverse=True)
    out["recent_sessions"] = recent[:20]
    return out


def collect_codex():
    out = empty_block()
    home = os.environ.get("HOME", "")
    if not home:
        return out
    last_ts = 0.0
    per_session = {}

    for path in glob.glob(
        os.path.join(home, ".codex", "sessions", "**", "*.jsonl"), recursive=True
    ):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_30D:
            continue
        current_model = None
        current_cwd = None
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if '"token_count"' not in line and '"turn_context"' not in line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    t = obj.get("type")
                    payload = obj.get("payload") or {}
                    if t == "turn_context" and isinstance(payload, dict):
                        current_model = payload.get("model") or current_model
                        current_cwd = payload.get("cwd") or current_cwd
                        continue
                    if t != "event_msg" or not isinstance(payload, dict):
                        continue
                    if payload.get("type") != "token_count":
                        continue
                    info = payload.get("info") or {}
                    if not isinstance(info, dict):
                        continue
                    last_use = info.get("last_token_usage") or {}
                    if not isinstance(last_use, dict):
                        continue
                    total = int(last_use.get("total_tokens", 0) or 0)
                    inp = int(last_use.get("input_tokens", 0) or 0)
                    outp = int(last_use.get("output_tokens", 0) or 0)
                    window = info.get("model_context_window")
                    ts = parse_iso(obj.get("timestamp")) or mtime
                    age = NOW - ts

                    sess = per_session.setdefault(path, {
                        "first_ts": ts, "last_ts": ts, "tokens": 0,
                        "model": current_model, "cwd": current_cwd,
                    })
                    sess["first_ts"] = min(sess["first_ts"], ts)
                    sess["last_ts"] = max(sess["last_ts"], ts)
                    sess["tokens"] += total
                    if current_model:
                        sess["model"] = current_model
                    if current_cwd:
                        sess["cwd"] = current_cwd

                    if age <= WIN_WEEK:
                        out["week_7d_tokens"] += total
                    if age <= WIN_SESSION:
                        out["session_5h_tokens"] += total

                    if ts > last_ts:
                        last_ts = ts
                        out["last_turn_input_tokens"] = inp
                        out["last_turn_output_tokens"] = outp
                        out["last_model"] = current_model
                        out["last_turn_at"] = obj.get("timestamp")
                        out["last_cwd"] = current_cwd
                        out["active_session_file"] = path
                        out["last_context_window"] = int(window) if window else None
                        if window:
                            out["last_context_pct"] = round(inp / int(window) * 100.0, 2)
        except OSError:
            continue

    if out["active_session_file"]:
        s = per_session.get(out["active_session_file"])
        if s:
            out["active_session_tokens"] = s["tokens"]
            out["active_session_started_at"] = datetime.fromtimestamp(
                s["first_ts"], tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    sessions = []
    recent = []
    for path, s in per_session.items():
        sessions.append({
            "tokens": s["tokens"], "last_ts": s["last_ts"],
            "model": s["model"], "cwd": s["cwd"],
        })
        recent.append({
            "id": os.path.basename(path).rsplit(".", 1)[0],
            "started_at": datetime.fromtimestamp(s["first_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "ended_at": datetime.fromtimestamp(s["last_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "duration_minutes": round((s["last_ts"] - s["first_ts"]) / 60.0, 1),
            "tokens": s["tokens"],
            "model": s["model"] or "—",
            "project": project_name_from_cwd(s["cwd"]),
        })
    out.update(bucket_aggregates(sessions))
    recent.sort(key=lambda r: r["ended_at"], reverse=True)
    out["recent_sessions"] = recent[:20]
    return out


def main():
    snap = {
        "claude": collect_claude(),
        "codex": collect_codex(),
        "collected_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "python3",
    }
    sys.stdout.write(json.dumps(snap))


if __name__ == "__main__":
    main()
