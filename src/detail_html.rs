//! Detail page renderer.
//!
//! Produces `~/.zed-context/detail.html`, a self-contained dark-themed HTML
//! report that the menubar app opens in a WKWebView. The report is a single
//! full-page tabbed layout with no external assets.

use crate::usage_signal::{AgentUsage, NamedBucket, SessionRecord, TimeBucket, ToolSummary, UsageSnapshot};

pub fn render(snap: &UsageSnapshot) -> String {
    let lang = Language::detect();
    let updated = snap.collected_at.as_deref().unwrap_or("-");
    let mut html = String::new();
    html.push_str(HEAD);
    html.push_str(&format!(
        r#"<header><h1>{}</h1><div class="muted">{} {}</div></header>"#,
        lang.text("Agent Usage Detail", "Ajan Kullanım Detayı"),
        lang.text("Updated", "Güncellendi"),
        html_escape(updated),
    ));
    html.push_str(
        &format!(r#"<nav class="tabs"><div class="seg-ctrl">
  <button class="tab-btn active" data-tab="today">{}</button>
  <button class="tab-btn" data-tab="history">{}</button>
  <button class="tab-btn" data-tab="sessions">{}</button>
  <button class="tab-btn" data-tab="breakdown">{}</button>
</div></nav>"#,
            lang.text("Today", "Bugün"),
            lang.text("History", "Geçmiş"),
            lang.text("Sessions", "Oturumlar"),
            lang.text("Breakdown", "Kırılım"),
        ),
    );
    html.push_str(r#"<main>"#);
    html.push_str(&panel("today", true, &render_today(snap, lang)));
    html.push_str(&panel("history", false, &render_history(snap, lang)));
    html.push_str(&panel("sessions", false, &render_sessions(snap, lang)));
    html.push_str(&panel("breakdown", false, &render_breakdown(snap, lang)));
    html.push_str(r#"</main>"#);
    html.push_str(FOOT);
    html
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Language {
    En,
    Tr,
}

impl Language {
    fn detect() -> Self {
        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let Ok(value) = std::env::var(key) {
                if value.to_ascii_lowercase().starts_with("tr") {
                    return Self::Tr;
                }
                if !value.is_empty() {
                    return Self::En;
                }
            }
        }
        Self::En
    }

    fn text(self, en: &'static str, tr: &'static str) -> &'static str {
        match self {
            Self::En => en,
            Self::Tr => tr,
        }
    }
}

fn panel(id: &str, active: bool, body: &str) -> String {
    let class = if active {
        "tab-panel active"
    } else {
        "tab-panel"
    };
    format!(r#"<div class="{class}" id="tab-{id}">{body}</div>"#)
}

fn render_today(snap: &UsageSnapshot, lang: Language) -> String {
    let mut out = format!(
        r#"<section class="today-grid">{}{}</section>"#,
        today_agent("Claude", &snap.claude, lang),
        today_agent("Codex", &snap.codex, lang)
    );
    if !snap.others.is_empty() {
        out.push_str(&render_other_tools(&snap.others, lang));
    }
    out
}

fn render_other_tools(tools: &[ToolSummary], lang: Language) -> String {
    let mut rows = String::new();
    for t in tools {
        let sessions = if t.sessions_7d > 0 {
            if lang == Language::Tr {
                format!("bu hafta {}", t.sessions_7d)
            } else {
                format!("{} this week", t.sessions_7d)
            }
        } else {
            "—".to_string()
        };
        let tokens = if t.tokens_7d > 0 {
            format_tokens(t.tokens_7d)
        } else {
            "—".to_string()
        };
        let last = t.last_used.as_deref().map(format_time).unwrap_or_else(|| "—".to_string());
        let model = t.last_model.as_deref().unwrap_or("—");
        rows.push_str(&format!(
            r#"<tr><td><strong>{}</strong></td><td>{}</td><td class="num">{}</td><td class="muted">{}</td><td class="muted">{}</td></tr>"#,
            html_escape(&t.name),
            html_escape(model),
            tokens,
            sessions,
            html_escape(&last),
        ));
    }
    format!(
        r#"<section class="other-tools"><h2>{}</h2><div class="table-card wide"><table><thead><tr><th>{}</th><th>{}</th><th>{}</th><th>{}</th><th>{}</th></tr></thead><tbody>{rows}</tbody></table></div></section>"#,
        lang.text("Other AI Tools", "Diğer AI Araçları"),
        lang.text("tool", "araç"),
        lang.text("last model", "son model"),
        lang.text("7d tokens", "7g token"),
        lang.text("7d sessions", "7g oturum"),
        lang.text("last used", "son kullanım"),
    )
}

fn today_agent(name: &str, usage: &AgentUsage, lang: Language) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        r#"<article class="agent-card"><div class="agent-heading"><h2>{}</h2><span class="status-pill" data-active="{}">{}</span></div>"#,
        html_escape(name),
        usage.active_session_started_at.is_some(),
        if usage.active_session_started_at.is_some() {
            lang.text("active", "aktif")
        } else {
            lang.text("idle", "boşta")
        }
    ));
    out.push_str(r#"<div class="metric-grid">"#);
    out.push_str(&metric(lang.text("Active session tokens", "Aktif oturum token"), &active_session_value(usage, lang)));
    out.push_str(&metric(lang.text("30d tokens", "30g token"), &format_tokens(usage.total_tokens_30d)));
    out.push_str(&metric(
        lang.text("30d sessions", "30g oturum"),
        &usage.total_sessions_30d.to_string(),
    ));
    out.push_str(&metric(
        lang.text("Last model", "Son model"),
        usage.last_model.as_deref().unwrap_or("-"),
    ));
    out.push_str(&metric(lang.text("Context", "Bağlam"), &format_pct(usage.last_context_pct)));
    out.push_str(&metric(lang.text("Last turn", "Son tur"), &last_turn_value(usage)));
    out.push_str(r#"</div></article>"#);
    out
}

fn active_session_value(usage: &AgentUsage, lang: Language) -> String {
    let tokens = format_tokens(usage.active_session_tokens);
    match usage.active_session_started_at.as_deref() {
        Some(started) if usage.active_session_tokens > 0 => format!(
            r#"{tokens}<br><span class="muted">since {}</span>"#,
            html_escape(&format!("{} {}", lang.text("since", "beri"), format_time(started)))
        ),
        Some(started) => format!(
            r#"0<br><span class="muted">since {}</span>"#,
            html_escape(&format!("{} {}", lang.text("since", "beri"), format_time(started)))
        ),
        None if usage.active_session_tokens > 0 => tokens,
        None => "-".to_string(),
    }
}

fn last_turn_value(usage: &AgentUsage) -> String {
    usage
        .last_turn_at
        .as_deref()
        .map(format_time)
        .unwrap_or_else(|| "-".to_string())
}

fn metric(label: &str, value: &str) -> String {
    format!(
        r#"<div class="metric"><div class="label">{}</div><div class="value">{}</div></div>"#,
        html_escape(label),
        value
    )
}

fn render_history(snap: &UsageSnapshot, lang: Language) -> String {
    format!(
        r#"<div class="stack">{}{}</div>"#,
        history_agent("Claude", &snap.claude, lang),
        history_agent("Codex", &snap.codex, lang)
    )
}

fn history_agent(name: &str, usage: &AgentUsage, lang: Language) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        r#"<section class="agent-section"><h2>{}</h2><div class="charts">"#,
        html_escape(name)
    ));
    out.push_str(&chart_card(lang.text("Daily", "Günlük"), &usage.by_day, lang));
    out.push_str(&chart_card(lang.text("Weekly", "Haftalık"), &usage.by_week, lang));
    out.push_str(&chart_card(lang.text("Monthly", "Aylık"), &usage.by_month, lang));
    out.push_str(r#"</div></section>"#);
    out
}

fn render_sessions(snap: &UsageSnapshot, lang: Language) -> String {
    format!(
        r#"<div class="stack">{}{}</div>"#,
        sessions_agent("Claude", &snap.claude.recent_sessions, lang),
        sessions_agent("Codex", &snap.codex.recent_sessions, lang)
    )
}

fn sessions_agent(name: &str, sessions: &[SessionRecord], lang: Language) -> String {
    format!(
        r#"<section class="agent-section"><h2>{}</h2>{}</section>"#,
        html_escape(name),
        recent_sessions_table(sessions, lang)
    )
}

fn render_breakdown(snap: &UsageSnapshot, lang: Language) -> String {
    format!(
        r#"<div class="stack">{}{}</div>"#,
        breakdown_agent("Claude", &snap.claude, lang),
        breakdown_agent("Codex", &snap.codex, lang)
    )
}

fn breakdown_agent(name: &str, usage: &AgentUsage, lang: Language) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        r#"<section class="agent-section"><h2>{}</h2><div class="tables">"#,
        html_escape(name)
    ));
    out.push_str(&named_table(lang.text("By model", "Modele göre"), lang.text("model", "model"), &usage.by_model, lang));
    out.push_str(&named_table(lang.text("By project", "Projeye göre"), lang.text("project", "proje"), &usage.by_project, lang));
    out.push_str(r#"</div></section>"#);
    out
}

fn chart_card(title: &str, buckets: &[TimeBucket], lang: Language) -> String {
    if buckets.is_empty() {
        return format!(
            r#"<div class="chart-card"><h3>{}</h3><div class="empty">{}</div></div>"#,
            html_escape(title),
            lang.text("no data", "veri yok"),
        );
    }

    let max_tokens = buckets.iter().map(|b| b.tokens).max().unwrap_or(1).max(1);
    let bar_w = 18;
    let gap = 4;
    let w = (bar_w + gap) * buckets.len() + 40;
    let h = 150;
    let mut svg = format!(r#"<svg viewBox="0 0 {w} {h}" preserveAspectRatio="none" class="chart">"#);
    for (i, b) in buckets.iter().enumerate() {
        let bh = (b.tokens as f64 / max_tokens as f64 * (h as f64 - 34.0)).max(1.0);
        let x = (i * (bar_w + gap)) as f64 + 20.0;
        let y = h as f64 - 22.0 - bh;
        svg.push_str(&format!(
            r#"<rect x="{x}" y="{y}" width="{bar_w}" height="{bh}" rx="3" class="bar"><title>{}</title></rect>"#,
            html_escape(&format!(
                "{}\n{} tokens · {} sessions",
                b.date,
                b.tokens,
                b.sessions
            ))
        ));
    }
    if let (Some(first), Some(last)) = (buckets.first(), buckets.last()) {
        svg.push_str(&format!(
            r#"<text x="20" y="{}" class="label-x start">{}</text><text x="{}" y="{}" class="label-x end">{}</text>"#,
            h - 4,
            html_escape(&first.date),
            w - 20,
            h - 4,
            html_escape(&last.date)
        ));
    }
    svg.push_str("</svg>");

    format!(
        r#"<div class="chart-card"><h3>{}</h3>{svg}</div>"#,
        html_escape(title)
    )
}

fn named_table(title: &str, name_heading: &str, items: &[NamedBucket], lang: Language) -> String {
    let mut rows = String::new();
    let total: u64 = items.iter().map(|i| i.tokens).sum::<u64>().max(1);
    for it in items.iter().take(12) {
        let pct = it.tokens as f64 / total as f64 * 100.0;
        rows.push_str(&format!(
            r#"<tr><td>{}</td><td class="num">{}</td><td class="num">{}</td><td class="bar-cell"><div class="hbar" style="width:{:.1}%"></div><span>{:.1}%</span></td></tr>"#,
            html_escape(&it.model),
            it.sessions,
            format_tokens(it.tokens),
            pct,
            pct
        ));
    }
    if rows.is_empty() {
        rows = format!(
            r#"<tr><td colspan="4" class="empty">{}</td></tr>"#,
            lang.text("no data", "veri yok")
        );
    }
    format!(
        r#"<div class="table-card"><h3>{}</h3><table><thead><tr><th>{}</th><th>{}</th><th>{}</th><th>{}</th></tr></thead><tbody>{rows}</tbody></table></div>"#,
        html_escape(title),
        html_escape(name_heading),
        lang.text("sessions", "oturum"),
        lang.text("tokens", "token"),
        lang.text("share", "pay"),
    )
}

fn recent_sessions_table(items: &[SessionRecord], lang: Language) -> String {
    let mut rows = String::new();
    for s in items {
        rows.push_str(&format!(
            r#"<tr><td>{}</td><td>{}</td><td>{}</td><td>{:.0} min</td><td class="num">{}</td><td><code>{}</code></td></tr>"#,
            html_escape(&format_time(&s.started_at)),
            html_escape(&s.project),
            html_escape(&s.model),
            s.duration_minutes,
            format_tokens(s.tokens),
            html_escape(&s.id)
        ));
    }
    if rows.is_empty() {
        rows = format!(
            r#"<tr><td colspan="6" class="empty">{}</td></tr>"#,
            lang.text("no recent sessions", "yakın oturum yok")
        );
    }
    format!(
        r#"<div class="table-card wide"><table><thead><tr><th>{}</th><th>{}</th><th>{}</th><th>{}</th><th>{}</th><th>{}</th></tr></thead><tbody>{rows}</tbody></table></div>"#,
        lang.text("started", "başlangıç"),
        lang.text("project", "proje"),
        lang.text("model", "model"),
        lang.text("duration", "süre"),
        lang.text("tokens", "token"),
        lang.text("session id", "oturum id"),
    )
}

fn format_tokens(value: u64) -> String {
    if value >= 1_000_000_000 {
        format!("{:.2}B", value as f64 / 1_000_000_000.0)
    } else if value >= 1_000_000 {
        format!("{:.2}M", value as f64 / 1_000_000.0)
    } else if value >= 1_000 {
        format!("{:.1}k", value as f64 / 1_000.0)
    } else {
        value.to_string()
    }
}

fn format_pct(value: Option<f64>) -> String {
    value
        .map(|pct| format!("{pct:.0}%"))
        .unwrap_or_else(|| "-".to_string())
}

fn format_time(raw: &str) -> String {
    if raw.is_empty() {
        return "-".to_string();
    }
    raw.get(..16).unwrap_or(raw).replace('T', " ")
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

const HEAD: &str = r#"<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>zed-context · usage</title>
<style>
:root {
  color-scheme: light dark;
  --bg: Canvas;
  --text: CanvasText;
  --accent: AccentColor;

  /* light */
  --panel: rgba(255,255,255,0.72);
  --panel2: rgba(246,246,248,0.80);
  --border: rgba(0,0,0,0.09);
  --separator: rgba(0,0,0,0.06);
  --muted: rgba(60,60,67,0.60);
  --bar2: #007AFF;
  --seg-bg: rgba(118,118,128,0.12);
  --seg-thumb: rgba(255,255,255,0.95);
  --seg-thumb-shadow: 0 1px 3px rgba(0,0,0,0.18);
  --pill-active-bg: rgba(0,122,255,0.12);
  --pill-active-text: #007AFF;
  --pill-idle-bg: rgba(118,118,128,0.10);
  --pill-idle-text: rgba(60,60,67,0.55);
}
@media (prefers-color-scheme: dark) {
  :root {
    --panel: rgba(40,40,44,0.70);
    --panel2: rgba(28,28,32,0.75);
    --border: rgba(255,255,255,0.09);
    --separator: rgba(255,255,255,0.06);
    --muted: rgba(235,235,245,0.50);
    --bar2: #0A84FF;
    --seg-bg: rgba(118,118,128,0.24);
    --seg-thumb: rgba(72,72,76,0.98);
    --seg-thumb-shadow: 0 1px 4px rgba(0,0,0,0.55);
    --pill-active-bg: rgba(10,132,255,0.18);
    --pill-active-text: #0A84FF;
    --pill-idle-bg: rgba(118,118,128,0.18);
    --pill-idle-text: rgba(235,235,245,0.45);
  }
}
* { box-sizing: border-box; margin:0; padding:0; }
body {
  min-height: 100vh;
  background: var(--bg);
  color: var(--text);
  font: 13px/1.45 -apple-system, "SF Pro Text", ui-sans-serif, sans-serif;
  -webkit-font-smoothing: antialiased;
}

/* ── Header ───────────────────────────────────────────── */
header {
  padding: 20px 28px 14px;
  border-bottom: 1px solid var(--separator);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
  background: var(--panel);
  position: sticky; top: 0; z-index: 10;
}
h1 { font-size: 15px; font-weight: 600; letter-spacing: -0.01em; }
.muted { color: var(--muted); font-size: 11px; margin-top: 2px; }

/* ── Segmented Control (macOS NSSegmentedControl style) ── */
nav.tabs {
  display: flex;
  padding: 14px 28px 0;
  border-bottom: 1px solid var(--separator);
}
.seg-ctrl {
  display: inline-flex;
  background: var(--seg-bg);
  border-radius: 8px;
  padding: 2px;
  gap: 1px;
}
.tab-btn {
  background: none;
  border: none;
  padding: 5px 14px;
  border-radius: 6px;
  color: var(--muted);
  cursor: pointer;
  font: 12px/1.4 -apple-system, sans-serif;
  font-weight: 500;
  letter-spacing: -0.003em;
  transition: color 0.1s;
  -webkit-user-select: none;
  white-space: nowrap;
}
.tab-btn.active {
  background: var(--seg-thumb);
  box-shadow: var(--seg-thumb-shadow);
  color: var(--text);
  font-weight: 590;
}
.tab-panel { display: none; padding: 20px 28px 32px; }
.tab-panel.active { display: block; }
main { min-height: calc(100vh - 108px); }

/* ── Layout helpers ───────────────────────────────────── */
.stack { display: flex; flex-direction: column; gap: 14px; }
.today-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px,1fr)); gap: 14px; }

/* ── Cards ────────────────────────────────────────────── */
.agent-card, .agent-section {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 18px 20px;
  backdrop-filter: blur(16px) saturate(160%);
  -webkit-backdrop-filter: blur(16px) saturate(160%);
}
h2 { font-size: 14px; font-weight: 600; letter-spacing: -0.01em; }
h3 { font-size: 11px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: 0.055em; margin-bottom: 10px; }

/* ── Agent heading + status pill ─────────────────────── */
.agent-heading { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 16px; }
.status-pill {
  border-radius: 999px;
  padding: 2px 9px;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.03em;
  text-transform: uppercase;
}
.status-pill[data-active="true"]  { background: var(--pill-active-bg); color: var(--pill-active-text); }
.status-pill[data-active="false"] { background: var(--pill-idle-bg);   color: var(--pill-idle-text); }

/* ── Metric grid ──────────────────────────────────────── */
.metric-grid { display: grid; grid-template-columns: repeat(2, minmax(0,1fr)); gap: 10px; }
.metric {
  background: var(--panel2);
  border: 1px solid var(--border);
  border-radius: 10px;
  min-height: 80px;
  padding: 11px 13px;
}
.metric .label { font-size: 10.5px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.055em; margin-bottom: 7px; }
.metric .value { font-size: 19px; line-height: 1.2; font-weight: 650; letter-spacing: -0.02em; overflow-wrap: anywhere; }

/* ── Charts ───────────────────────────────────────────── */
.charts { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px,1fr)); gap: 10px; margin-top: 14px; }
.chart-card {
  background: var(--panel2);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 13px;
  min-height: 195px;
}
svg.chart { width: 100%; height: 148px; display: block; }
svg.chart rect.bar { fill: var(--bar2); opacity: 0.85; }
svg.chart rect.bar:hover { opacity: 1; }
svg.chart text.label-x { fill: var(--muted); font-size: 9.5px; }
svg.chart text.label-x.end { text-anchor: end; }

/* ── Tables ───────────────────────────────────────────── */
.tables { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px,1fr)); gap: 10px; margin-top: 14px; }
.table-card { background: var(--panel2); border: 1px solid var(--border); border-radius: 10px; padding: 13px; overflow-x: auto; }
.table-card.wide { margin-top: 14px; }
.other-tools { margin-top: 20px; }
.other-tools h2 { margin-bottom: 10px; font-size: 11px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: 0.055em; }
table { width: 100%; border-collapse: collapse; font-size: 11.5px; }
th { text-align: left; padding: 5px 8px; font-weight: 500; color: var(--muted); border-bottom: 1px solid var(--separator); white-space: nowrap; font-size: 11px; }
td { padding: 5px 8px; border-bottom: 1px solid var(--separator); vertical-align: top; }
tr:last-child td { border-bottom: none; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
code { font-family: "SF Mono", ui-monospace, "Menlo", monospace; font-size: 10.5px; color: var(--muted); }
.bar-cell { position: relative; min-width: 110px; padding-right: 46px; }
.bar-cell .hbar { height: 5px; background: var(--bar2); border-radius: 3px; opacity: 0.75; }
.bar-cell span { position: absolute; right: 8px; top: 50%; transform: translateY(-50%); font-size: 10.5px; color: var(--muted); }
.empty { color: var(--muted); font-size: 11.5px; padding: 10px 8px; }

@media (max-width: 680px) {
  header, nav.tabs { padding-left: 16px; padding-right: 16px; }
  .tab-panel { padding: 16px; }
  .today-grid, .metric-grid { grid-template-columns: 1fr; }
}
</style></head><body>"#;

const FOOT: &str = r#"<script>
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
  });
});
</script></body></html>"#;
