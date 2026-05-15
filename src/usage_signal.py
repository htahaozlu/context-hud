"""Aggregate Claude Code + Codex CLI token usage across all projects.

Stdout: single JSON document. Layout:

  {
    "claude":  AgentBlock,
    "codex":   AgentBlock,
    "collected_at": ISO8601,
    "source": "python3"
  }

AgentBlock contains:
  - Live HUD fields (used by ~/.context-hud/hud.json):
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
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from urllib import request

NOW = time.time()
WIN_SESSION = 5 * 3600
WIN_WEEK = 7 * 86400
WIN_30D = 30 * 86400
# History window for streaks / longest streak / heatmap. Files older than this
# are skipped during scan; aggregates pad calendar days inside this window.
WIN_HIST = 365 * 86400
# Idle gap that splits a single .jsonl into multiple logical sessions. Matches
# the 5h rolling window Claude uses to reset session metrics in its own UI.
SESSION_IDLE_GAP = 5 * 3600
# A session is "active" if its last turn is within this window. 30 min covers
# slow human-in-the-loop pauses without surfacing stale sessions as live.
ACTIVE_WINDOW = 30 * 60
CACHE_TTL_OK = 5 * 60
CACHE_TTL_ERR = 15
STATUSLINE_TTL = 12 * 3600


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
        "session_5h_percent": None,
        "week_7d_tokens": 0,
        "week_7d_percent": None,
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
        "active_sessions": [],
        # When the rolling 5h / 7d usage windows next free up — the timestamp
        # of the oldest in-window turn plus the window length.
        "session_5h_resets_at": None,
        "week_7d_resets_at": None,
    }


def usage_cache_path():
    home = os.environ.get("HOME", "")
    if not home:
        return None
    return os.path.join(home, ".context-hud", "usage_api_cache.json")


def claude_statusline_path():
    override = os.environ.get("CONTEXTHUD_CLAUDE_STATUSLINE_PATH")
    if override:
        return override
    home = os.environ.get("HOME", "")
    if not home:
        return None
    return os.path.join(home, ".context-hud", "claude-statusline.json")


def load_usage_cache():
    path = usage_cache_path()
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def save_usage_cache(payload):
    path = usage_cache_path()
    if not path:
        return
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
    except Exception:
        pass


def read_claude_credentials():
    home = os.environ.get("HOME", "")
    if not home:
        return None
    now_ms = int(time.time() * 1000)

    raw = None
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if out.returncode == 0:
            raw = out.stdout.strip()
    except Exception:
        raw = None

    if raw:
        try:
            data = json.loads(raw)
            oauth = data.get("claudeAiOauth") or {}
            token = oauth.get("accessToken")
            expires_at = oauth.get("expiresAt")
            if token and (expires_at is None or expires_at > now_ms):
                return token
        except Exception:
            if raw.startswith("sk-ant"):
                return raw

    credentials_path = os.path.join(home, ".claude", ".credentials.json")
    if not os.path.exists(credentials_path):
        return None
    try:
        with open(credentials_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        oauth = data.get("claudeAiOauth") or {}
        token = oauth.get("accessToken")
        expires_at = oauth.get("expiresAt")
        if token and (expires_at is None or expires_at > now_ms):
            return token
    except Exception:
        return None
    return None


def fetch_claude_usage_api():
    cached = load_usage_cache()
    now = int(time.time())
    if cached:
        ts = int(cached.get("timestamp", 0) or 0)
        ttl = CACHE_TTL_OK if cached.get("ok") else CACHE_TTL_ERR
        if ts > 0 and now - ts < ttl:
            return cached.get("data")

    token = read_claude_credentials()
    if not token:
        save_usage_cache({"timestamp": now, "ok": False, "data": None})
        return None

    req = request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.1",
        },
    )
    try:
        with request.urlopen(req, timeout=15) as resp:
            if resp.status != 200:
                save_usage_cache({"timestamp": now, "ok": False, "data": None})
                return None
            payload = json.loads(resp.read().decode("utf-8"))
            save_usage_cache({"timestamp": now, "ok": True, "data": payload})
            return payload
    except Exception:
        fallback = cached.get("data") if cached else None
        save_usage_cache({"timestamp": now, "ok": False, "data": fallback})
        return fallback


def parse_usage_percent(value):
    if isinstance(value, (int, float)):
        return round(max(0.0, min(100.0, float(value))), 1)
    return None


def apply_claude_usage_api(out):
    payload = fetch_claude_usage_api()
    if not isinstance(payload, dict):
        return out
    five = payload.get("five_hour") or {}
    seven = payload.get("seven_day") or {}
    out["session_5h_percent"] = parse_usage_percent(five.get("utilization"))
    out["week_7d_percent"] = parse_usage_percent(seven.get("utilization"))
    if five.get("resets_at"):
        out["session_5h_resets_at"] = five.get("resets_at")
    if seven.get("resets_at"):
        out["week_7d_resets_at"] = seven.get("resets_at")
    return out


def load_claude_statusline_snapshot():
    path = claude_statusline_path()
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            payload = json.load(fh)
    except Exception:
        return None
    ts = parse_iso(payload.get("updated_at"))
    if ts is None:
        try:
            ts = os.path.getmtime(path)
        except OSError:
            ts = None
    if ts is None or NOW - ts > STATUSLINE_TTL:
        return None
    payload["_timestamp"] = ts
    return payload


def build_active_sessions(per_session):
    """Return list of session dicts where last_ts is within ACTIVE_WINDOW."""
    actives = []
    for path, s in per_session.items():
        if NOW - s["last_ts"] > ACTIVE_WINDOW:
            continue
        # Per-session context window — explicit override (Codex), or derived
        # from model (Claude). Falls back to None when neither is known.
        window = s.get("last_window")
        if not window:
            try:
                window = claude_context_window(s.get("model"))
            except Exception:
                window = None
        last_input = int(s.get("last_input", 0) or 0)
        context_pct = None
        if window and last_input > 0:
            context_pct = round(min(100.0, last_input / window * 100.0), 1)
        actives.append({
            "id": os.path.basename(path).rsplit(".", 1)[0],
            "tokens": s["tokens"],
            "started_at": datetime.fromtimestamp(s["first_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "last_turn_at": datetime.fromtimestamp(s["last_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            "model": s["model"],
            "cwd": s["cwd"],
            "project": project_name_from_cwd(s["cwd"]),
            "context_pct": context_pct,
            "context_window": window,
            "last_input_tokens": last_input,
        })
    actives.sort(key=lambda x: x["last_turn_at"], reverse=True)
    return actives


def claude_context_window(model):
    if not model:
        return 200000
    m = model.lower()
    if "[1m]" in m or "-1m" in m:
        return 1_000_000
    if any(tag in m for tag in [
        "claude-mythos",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-sonnet-4-6",
    ]):
        return 1_000_000
    return 200_000


def parse_claude_rate_limit_window(rate_limits, *keys):
    if not isinstance(rate_limits, dict):
        return (None, None)
    current = rate_limits
    for key in keys:
        current = current.get(key) if isinstance(current, dict) else None
    if not isinstance(current, dict):
        return (None, None)
    pct = parse_usage_percent(current.get("used_percentage"))
    if pct is None:
        pct = parse_usage_percent(current.get("utilization"))
    if pct is None:
        pct = parse_usage_percent(current.get("used_percent"))
    resets = current.get("resets_at")
    if isinstance(resets, (int, float)):
        resets = datetime.fromtimestamp(resets, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    elif not isinstance(resets, str):
        resets = None
    return (pct, resets)


def apply_claude_statusline_snapshot(out):
    snap = load_claude_statusline_snapshot()
    if not isinstance(snap, dict):
        return out

    # Statusline snapshot is authoritative for live context fields — it is
    # what Claude itself displays. Transcript scan picks the newest assistant
    # turn across all JSONL files (including subagent transcripts with large
    # cache_read totals), which can wildly inflate last_context_pct. Trust
    # the snapshot whenever it is fresh (TTL-checked in loader).
    ctx = snap.get("context_window") or {}
    current_usage = ctx.get("current_usage") or {}

    input_total = ctx.get("total_input_tokens")
    if input_total is None and isinstance(current_usage, dict):
        input_total = (
            int(current_usage.get("input_tokens", 0) or 0)
            + int(current_usage.get("cache_creation_input_tokens", 0) or 0)
            + int(current_usage.get("cache_read_input_tokens", 0) or 0)
        )
    output_total = ctx.get("total_output_tokens")
    if output_total is None and isinstance(current_usage, dict):
        output_total = int(current_usage.get("output_tokens", 0) or 0)

    model = snap.get("model") or {}
    workspace = snap.get("workspace") or {}
    cwd = workspace.get("current_dir") or snap.get("cwd")
    model_id = model.get("id") or model.get("display_name")
    used_pct = parse_usage_percent(ctx.get("used_percentage"))
    window = ctx.get("context_window_size")
    if window is not None:
        try:
            window = int(window)
        except Exception:
            window = None

    out["last_turn_at"] = snap.get("updated_at") or out.get("last_turn_at")
    if model_id:
        out["last_model"] = model_id
    if cwd:
        out["last_cwd"] = cwd
    if input_total is not None:
        out["last_turn_input_tokens"] = int(input_total or 0)
    if output_total is not None:
        out["last_turn_output_tokens"] = int(output_total or 0)
    if window:
        out["last_context_window"] = window
    if used_pct is not None:
        out["last_context_pct"] = used_pct

    rate_limits = snap.get("rate_limits") or {}
    for keyset, pct_key, reset_key in [
        (("five_hour",), "session_5h_percent", "session_5h_resets_at"),
        (("seven_day",), "week_7d_percent", "week_7d_resets_at"),
        (("primary",), "session_5h_percent", "session_5h_resets_at"),
        (("secondary",), "week_7d_percent", "week_7d_resets_at"),
    ]:
        pct, resets = parse_claude_rate_limit_window(rate_limits, *keyset)
        if pct is not None:
            out[pct_key] = pct
        if resets:
            out[reset_key] = resets
    return out


def project_name_from_cwd(cwd):
    if not cwd:
        return "—"
    return os.path.basename(cwd.rstrip("/")) or cwd


def bucket_aggregates(per_session, days=365, weeks=52, months=24):
    """Roll a list of session records into time buckets.

    Bucketing uses the LOCAL timezone so "most active day" and streaks line up
    with what a human reading their calendar would see. `by_day` is padded
    with zero-token entries for every calendar day inside the history window
    so consumers can compute streaks by walking the array without first
    filling in missing dates themselves.
    """
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
        dt = datetime.fromtimestamp(ts).astimezone()
        day = dt.strftime("%Y-%m-%d")
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

    today_local = datetime.fromtimestamp(NOW).astimezone().date()
    padded_day = []
    for i in range(days):
        d = today_local - timedelta(days=i)
        key = d.strftime("%Y-%m-%d")
        rec = by_day.get(key) or {"tokens": 0, "sessions": 0}
        padded_day.append({"date": key, "tokens": rec["tokens"], "sessions": rec["sessions"]})

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
        "by_day": padded_day,
        "by_week": take(by_week, "week", weeks, sort_key=lambda x: x["week"]),
        "by_month": take(by_month, "month", months, sort_key=lambda x: x["month"]),
        "by_model": take(by_model, "model", 20),
        "by_project": take(by_project, "project", 20),
    }


def split_logical_sessions(per_session):
    """Split each file's events into sub-sessions on idle gaps.

    Returns (sessions, recent) where sessions feeds bucket_aggregates and
    recent feeds recent_sessions. A "logical session" ends when the gap to
    the next turn exceeds SESSION_IDLE_GAP (matches Claude's 5h reset).
    """
    sessions = []
    recent = []
    for path, s in per_session.items():
        events = sorted(s.get("events") or [], key=lambda e: e[0])
        if not events:
            continue
        chunks = []
        cur = [events[0]]
        for prev, nxt in zip(events, events[1:]):
            if nxt[0] - prev[0] > SESSION_IDLE_GAP:
                chunks.append(cur)
                cur = [nxt]
            else:
                cur.append(nxt)
        chunks.append(cur)
        base_id = os.path.basename(path).rsplit(".", 1)[0]
        for i, chunk in enumerate(chunks):
            first_ts = chunk[0][0]
            last_ts = chunk[-1][0]
            tokens = sum(t for _, t in chunk)
            sessions.append({
                "tokens": tokens, "last_ts": last_ts,
                "model": s["model"], "cwd": s["cwd"],
            })
            recent.append({
                "id": base_id if len(chunks) == 1 else f"{base_id}#{i + 1}",
                "started_at": datetime.fromtimestamp(first_ts, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
                "ended_at": datetime.fromtimestamp(last_ts, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
                "duration_minutes": round((last_ts - first_ts) / 60.0, 1),
                "tokens": tokens,
                "model": s["model"] or "—",
                "project": project_name_from_cwd(s["cwd"]),
            })
    return sessions, recent


def collect_claude():
    out = empty_block()
    home = os.environ.get("HOME", "")
    if not home:
        return out
    last_ts = 0.0
    per_session = {}  # path -> {first_ts, last_ts, tokens, model, cwd}
    session_5h_oldest = None  # oldest turn ts within last 5h
    week_7d_oldest = None     # oldest turn ts within last 7d

    for path in glob.glob(os.path.join(home, ".claude", "projects", "*", "*.jsonl")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_30D and NOW - mtime > WIN_WEEK:
            # skip very old for speed; still allow 30d scan above
            pass
        if NOW - mtime > WIN_HIST:
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
                    # Per Anthropic docs total input = input_tokens +
                    # cache_creation_input_tokens + cache_read_input_tokens
                    # (all three count toward billing). For "tokens used"
                    # displays we follow the ccusage / Claude Code convention
                    # and sum input + cache_creation + output, omitting
                    # cache_read so the same cached prefix isn't counted on
                    # every turn (which would inflate totals 10-100×).
                    # cache_read is still rolled into `inp` for context-window
                    # % math because the model does see those tokens.
                    fresh_in = int(usage.get("input_tokens", 0) or 0)
                    cache_create = int(usage.get("cache_creation_input_tokens", 0) or 0)
                    cache_read = int(usage.get("cache_read_input_tokens", 0) or 0)
                    outp = int(usage.get("output_tokens", 0) or 0)
                    inp = fresh_in + cache_create + cache_read  # context-window view
                    total = fresh_in + cache_create + outp      # consumed view
                    ts = parse_iso(obj.get("timestamp")) or mtime
                    age = NOW - ts

                    sess = per_session.setdefault(path, {
                        "first_ts": ts, "last_ts": 0, "tokens": 0,
                        "model": msg.get("model"), "cwd": obj.get("cwd"),
                        "last_input": 0,
                        "events": [],
                    })
                    sess["first_ts"] = min(sess["first_ts"], ts)
                    if ts >= sess["last_ts"]:
                        sess["last_ts"] = ts
                        sess["last_input"] = inp
                    sess["tokens"] += total
                    sess["events"].append((ts, total))
                    if msg.get("model"):
                        sess["model"] = msg.get("model")
                    if obj.get("cwd"):
                        sess["cwd"] = obj.get("cwd")

                    if age <= WIN_WEEK:
                        out["week_7d_tokens"] += total
                        if week_7d_oldest is None or ts < week_7d_oldest:
                            week_7d_oldest = ts
                    if age <= WIN_SESSION:
                        out["session_5h_tokens"] += total
                        if session_5h_oldest is None or ts < session_5h_oldest:
                            session_5h_oldest = ts

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
                        out["last_context_pct"] = round(min(100.0, raw_in / window * 100.0), 2) if window else None
        except OSError:
            continue

    if out["active_session_file"]:
        s = per_session.get(out["active_session_file"])
        if s:
            out["active_session_tokens"] = s["tokens"]
            out["active_session_started_at"] = datetime.fromtimestamp(
                s["first_ts"], tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    # Split each .jsonl into logical sessions on idle gaps > SESSION_IDLE_GAP
    # so a file left open across days doesn't show up as one giant session.
    sessions, recent = split_logical_sessions(per_session)
    out.update(bucket_aggregates(sessions))
    recent.sort(key=lambda r: r["ended_at"], reverse=True)
    out["recent_sessions"] = recent[:20]
    out["active_sessions"] = build_active_sessions(per_session)
    if session_5h_oldest is not None:
        ts = session_5h_oldest + WIN_SESSION
        out["session_5h_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    if week_7d_oldest is not None:
        ts = week_7d_oldest + WIN_WEEK
        out["week_7d_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    out = apply_claude_statusline_snapshot(out)
    return apply_claude_usage_api(out)


def collect_codex():
    out = empty_block()
    home = os.environ.get("HOME", "")
    if not home:
        return out
    last_ts = 0.0
    per_session = {}
    session_5h_oldest = None
    week_7d_oldest = None
    latest_rate_ts = 0.0
    latest_rate_limits = None

    for path in glob.glob(
        os.path.join(home, ".codex", "sessions", "**", "*.jsonl"), recursive=True
    ):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_HIST:
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
                    # rate_limits is present alongside info (may be null info)
                    rl = payload.get("rate_limits")
                    if isinstance(rl, dict):
                        ts_rl = parse_iso(obj.get("timestamp")) or mtime
                        if ts_rl > latest_rate_ts:
                            latest_rate_ts = ts_rl
                            latest_rate_limits = rl
                    info = payload.get("info") or {}
                    if not isinstance(info, dict):
                        continue
                    last_use = info.get("last_token_usage") or {}
                    if not isinstance(last_use, dict):
                        continue
                    inp_raw = int(last_use.get("input_tokens", 0) or 0)
                    cached = int(last_use.get("cached_input_tokens", 0) or 0)
                    outp = int(last_use.get("output_tokens", 0) or 0)
                    reasoning = int(last_use.get("reasoning_output_tokens", 0) or 0)
                    # input_tokens includes cached_input_tokens — subtract to
                    # avoid counting the same cached prefix every turn.
                    fresh_in = max(0, inp_raw - cached)
                    inp = inp_raw  # context-window view (full prompt)
                    total = fresh_in + outp + reasoning  # consumed view
                    window = info.get("model_context_window")
                    ts = parse_iso(obj.get("timestamp")) or mtime
                    age = NOW - ts

                    sess = per_session.setdefault(path, {
                        "first_ts": ts, "last_ts": 0, "tokens": 0,
                        "model": current_model, "cwd": current_cwd,
                        "last_input": 0, "last_window": window,
                        "events": [],
                    })
                    sess["first_ts"] = min(sess["first_ts"], ts)
                    if ts >= sess["last_ts"]:
                        sess["last_ts"] = ts
                        sess["last_input"] = inp
                        if window:
                            sess["last_window"] = window
                    sess["tokens"] += total
                    sess["events"].append((ts, total))
                    if current_model:
                        sess["model"] = current_model
                    if current_cwd:
                        sess["cwd"] = current_cwd

                    if age <= WIN_WEEK:
                        out["week_7d_tokens"] += total
                        if week_7d_oldest is None or ts < week_7d_oldest:
                            week_7d_oldest = ts
                    if age <= WIN_SESSION:
                        out["session_5h_tokens"] += total
                        if session_5h_oldest is None or ts < session_5h_oldest:
                            session_5h_oldest = ts

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
                            out["last_context_pct"] = round(min(100.0, inp / int(window) * 100.0), 2)
        except OSError:
            continue

    if latest_rate_limits:
        primary = latest_rate_limits.get("primary") or {}
        secondary = latest_rate_limits.get("secondary") or {}
        # Only use primary if its reset window hasn't passed yet
        p_resets = primary.get("resets_at")
        if "used_percent" in primary and p_resets and p_resets > NOW:
            out["session_5h_percent"] = parse_usage_percent(primary["used_percent"])
            out["session_5h_resets_at"] = datetime.fromtimestamp(
                p_resets, tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")
        s_resets = secondary.get("resets_at")
        if "used_percent" in secondary and s_resets and s_resets > NOW:
            out["week_7d_percent"] = parse_usage_percent(secondary["used_percent"])
            out["week_7d_resets_at"] = datetime.fromtimestamp(
                s_resets, tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    if out["active_session_file"]:
        s = per_session.get(out["active_session_file"])
        if s:
            out["active_session_tokens"] = s["tokens"]
            out["active_session_started_at"] = datetime.fromtimestamp(
                s["first_ts"], tz=timezone.utc
            ).isoformat().replace("+00:00", "Z")

    sessions, recent = split_logical_sessions(per_session)
    out.update(bucket_aggregates(sessions))
    recent.sort(key=lambda r: r["ended_at"], reverse=True)
    out["recent_sessions"] = recent[:20]
    out["active_sessions"] = build_active_sessions(per_session)
    if session_5h_oldest is not None:
        ts = session_5h_oldest + WIN_SESSION
        out["session_5h_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    if week_7d_oldest is not None:
        ts = week_7d_oldest + WIN_WEEK
        out["week_7d_resets_at"] = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    return out


# ── Additional AI tool probes ─────────────────────────────────────────────────

def empty_tool(name):
    return {
        "name": name,
        "sessions_7d": 0,
        "sessions_today": 0,
        "tokens_7d": 0,
        "tokens_today": 0,
        "last_used": None,
        "last_model": None,
    }


def probe_llm_cli():
    """Simon Willison's 'llm' CLI — ~/.config/io.datasette.llm/logs.db"""
    try:
        import sqlite3
    except ImportError:
        return None
    db = os.path.expanduser("~/.config/io.datasette.llm/logs.db")
    if not os.path.exists(db):
        return None
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        cur = conn.cursor()
        rows = cur.execute(
            """SELECT datetime_utc,
                      COALESCE(input_tokens,0)+COALESCE(output_tokens,0),
                      model
               FROM responses
               WHERE datetime_utc >= datetime('now','-7 days')
               ORDER BY datetime_utc DESC LIMIT 2000"""
        ).fetchall()
        conn.close()
    except Exception:
        return None
    if not rows:
        return None
    out = empty_tool("LLM")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    session_days, today_count = set(), 0
    for (dt_utc, tokens, model) in rows:
        if dt_utc:
            day = dt_utc[:10]
            session_days.add(day)
            if day == today:
                today_count += 1
                out["tokens_today"] += tokens or 0
        out["tokens_7d"] += tokens or 0
        if out["last_used"] is None:
            out["last_used"] = dt_utc
            out["last_model"] = model
    out["sessions_7d"] = len(session_days)
    out["sessions_today"] = today_count
    return out


def probe_gemini_cli():
    """Google Gemini CLI — ~/.gemini/ JSONL sessions"""
    home = os.environ.get("HOME", "")
    if not home:
        return None
    candidates = [
        os.path.join(home, ".gemini", "sessions"),
        os.path.join(home, ".gemini"),
        os.path.join(home, ".config", "gemini", "sessions"),
    ]
    base = next((d for d in candidates if os.path.isdir(d)), None)
    if not base:
        return None
    out = empty_tool("Gemini")
    found = False
    for path in glob.glob(os.path.join(base, "**", "*.jsonl"), recursive=True) + \
                glob.glob(os.path.join(base, "*.jsonl")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime > WIN_WEEK:
            continue
        found = True
        out["sessions_7d"] += 1
        if NOW - mtime <= 86400:
            out["sessions_today"] += 1
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    u = obj.get("usageMetadata") or obj.get("usage") or {}
                    if isinstance(u, dict):
                        total = int(u.get("totalTokenCount") or
                                    (int(u.get("promptTokenCount", 0) or 0) +
                                     int(u.get("candidatesTokenCount", 0) or 0)))
                        out["tokens_7d"] += total
                        if NOW - mtime <= 86400:
                            out["tokens_today"] += total
                    if out["last_used"] is None:
                        ts = obj.get("timestamp") or obj.get("createTime")
                        if ts:
                            out["last_used"] = ts
                    if not out["last_model"]:
                        out["last_model"] = obj.get("model")
        except OSError:
            continue
    return out if found else None


def probe_aider():
    """Aider — check ~/.aider/ for recent activity (no full home scan)."""
    home = os.environ.get("HOME", "")
    if not home:
        return None
    aider_dir = os.path.join(home, ".aider")
    if not os.path.isdir(aider_dir):
        return None
    found_paths = []
    # Check only within ~/.aider/ — safe, bounded directory
    for path in glob.glob(os.path.join(aider_dir, "**", "*.jsonl"), recursive=True) + \
                glob.glob(os.path.join(aider_dir, "*.jsonl")) + \
                glob.glob(os.path.join(aider_dir, "**", "*.yaml"), recursive=True):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if NOW - mtime <= WIN_WEEK:
            found_paths.append((mtime, path))
    if not found_paths:
        return None
    found_paths.sort(reverse=True)
    out = empty_tool("Aider")
    out["sessions_7d"] = len(found_paths)
    out["sessions_today"] = sum(1 for (m, _) in found_paths if NOW - m <= 86400)
    latest_mtime, _ = found_paths[0]
    out["last_used"] = datetime.fromtimestamp(latest_mtime, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    return out


# Shell history AI tool detection
_HISTORY_TOOLS = [
    ("aider", "Aider"),
    ("sgpt", "ShellGPT"),
    ("mods", "Mods"),
    ("fabric", "Fabric"),
    ("tgpt", "tGPT"),
    ("continue", "Continue"),
    ("copilot", "Copilot CLI"),
    ("gemini", "Gemini"),
    ("deepseek", "DeepSeek"),
    ("qwen", "Qwen"),
    ("minimax", "MiniMax"),
]


def probe_shell_history():
    """Scan ~/.zsh_history (extended format) for AI CLI invocations in last 7 days."""
    home = os.environ.get("HOME", "")
    if not home:
        return []
    hist_path = os.path.join(home, ".zsh_history")
    if not os.path.exists(hist_path):
        return []
    cutoff = NOW - WIN_WEEK
    counts = defaultdict(lambda: {"count": 0, "last_ts": 0})
    try:
        with open(hist_path, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            fh.seek(max(0, size - 2 * 1024 * 1024))
            content = fh.read().decode("utf-8", errors="replace")
        ts = None
        for line in content.splitlines():
            if line.startswith(": "):
                parts = line.split(";", 1)
                if len(parts) == 2:
                    try:
                        ts = int(parts[0].split(":")[1])
                    except Exception:
                        ts = None
                    cmd = parts[1].strip()
                else:
                    cmd = ""
            else:
                cmd = line.strip()
                # no timestamp available for this line
            if ts is None or ts < cutoff:
                continue
            for binary, display in _HISTORY_TOOLS:
                if cmd == binary or cmd.startswith(binary + " ") or cmd.startswith(binary + "\t"):
                    counts[display]["count"] += 1
                    if ts > counts[display]["last_ts"]:
                        counts[display]["last_ts"] = ts
    except Exception:
        return []
    results = []
    for display, data in counts.items():
        if data["count"] == 0:
            continue
        t = empty_tool(display)
        t["sessions_7d"] = data["count"]
        t["sessions_today"] = 0  # not tracked at daily granularity from history
        if data["last_ts"]:
            t["last_used"] = datetime.fromtimestamp(data["last_ts"], tz=timezone.utc).isoformat().replace("+00:00", "Z")
        results.append(t)
    return results


def collect_others():
    tools = []
    for probe_fn in [probe_llm_cli, probe_gemini_cli, probe_aider]:
        try:
            result = probe_fn()
        except Exception:
            result = None
        if result is not None:
            tools.append(result)
    existing = {t["name"].lower() for t in tools}
    try:
        for t in probe_shell_history():
            if t["name"].lower() not in existing:
                tools.append(t)
                existing.add(t["name"].lower())
    except Exception:
        pass
    tools.sort(key=lambda t: t["last_used"] or "", reverse=True)
    return tools


def main():
    snap = {
        "claude": collect_claude(),
        "codex": collect_codex(),
        "others": collect_others(),
        "collected_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "python3",
    }
    sys.stdout.write(json.dumps(snap))


if __name__ == "__main__":
    main()
