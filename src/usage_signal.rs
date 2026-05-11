//! Cross-project agent usage signals.
//!
//! Reads Claude Code (`~/.claude/projects/**/*.jsonl`) and Codex CLI
//! (`~/.codex/sessions/**/*.jsonl`) transcript files to summarize token usage
//! over a rolling 5-hour session and 7-day week, plus the most recent turn's
//! context-window utilization. Output drives the HUD surface.
//!
//! Implementation note: the heavy lifting lives in `usage_signal.py` invoked
//! through `process:exec`. The Rust side validates the JSON envelope and
//! returns a typed snapshot. On systems without `python3` (or where the
//! script aborts) the snapshot is empty and the HUD degrades gracefully.

use serde::{Deserialize, Serialize};

#[cfg(target_arch = "wasm32")]
use zed_extension_api::{self as zed, process::Command, serde_json};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct AgentUsage {
    #[serde(default)]
    pub session_5h_tokens: u64,
    #[serde(default)]
    pub week_7d_tokens: u64,
    #[serde(default)]
    pub active_session_tokens: u64,
    #[serde(default)]
    pub active_session_file: Option<String>,
    #[serde(default)]
    pub last_turn_input_tokens: u64,
    #[serde(default)]
    pub last_turn_output_tokens: u64,
    #[serde(default)]
    pub last_model: Option<String>,
    #[serde(default)]
    pub last_context_window: Option<u64>,
    #[serde(default)]
    pub last_context_pct: Option<f64>,
    #[serde(default)]
    pub last_turn_at: Option<String>,
    #[serde(default)]
    pub last_cwd: Option<String>,
    #[serde(default)]
    pub active_session_started_at: Option<String>,

    // Aggregates for the detail page. All optional/empty in the no-data case.
    #[serde(default)]
    pub total_tokens_30d: u64,
    #[serde(default)]
    pub total_sessions_30d: u64,
    #[serde(default)]
    pub by_day: Vec<TimeBucket>,
    #[serde(default)]
    pub by_week: Vec<TimeBucket>,
    #[serde(default)]
    pub by_month: Vec<TimeBucket>,
    #[serde(default)]
    pub by_model: Vec<NamedBucket>,
    #[serde(default)]
    pub by_project: Vec<NamedBucket>,
    #[serde(default)]
    pub recent_sessions: Vec<SessionRecord>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TimeBucket {
    #[serde(default, alias = "week", alias = "month")]
    pub date: String,
    #[serde(default)]
    pub tokens: u64,
    #[serde(default)]
    pub sessions: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct NamedBucket {
    #[serde(default, alias = "project")]
    pub model: String,
    #[serde(default)]
    pub tokens: u64,
    #[serde(default)]
    pub sessions: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SessionRecord {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub started_at: String,
    #[serde(default)]
    pub ended_at: String,
    #[serde(default)]
    pub duration_minutes: f64,
    #[serde(default)]
    pub tokens: u64,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub project: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct UsageSnapshot {
    #[serde(default)]
    pub claude: AgentUsage,
    #[serde(default)]
    pub codex: AgentUsage,
    #[serde(default)]
    pub collected_at: Option<String>,
    #[serde(default)]
    pub source: String,
}

impl UsageSnapshot {
    pub fn unavailable(reason: impl Into<String>) -> Self {
        Self {
            source: reason.into(),
            ..Default::default()
        }
    }
}

const SCRIPT: &str = include_str!("usage_signal.py");

#[cfg(target_arch = "wasm32")]
pub fn collect(worktree: &zed::Worktree) -> UsageSnapshot {
    let Some(python) = worktree
        .which("python3")
        .or_else(|| worktree.which("python"))
    else {
        return UsageSnapshot::unavailable("python3 not found on PATH");
    };

    let mut command = Command::new(python);
    command = command.arg("-c").arg(SCRIPT);
    command = command.envs(worktree.shell_env());

    let output = match command.output() {
        Ok(value) => value,
        Err(error) => {
            return UsageSnapshot::unavailable(format!("python spawn failed: {error}"));
        }
    };

    if output.status != Some(0) {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return UsageSnapshot::unavailable(format!(
            "usage_signal.py exited with status {:?}: {}",
            output.status,
            stderr.trim()
        ));
    }

    match serde_json::from_slice::<UsageSnapshot>(&output.stdout) {
        Ok(snapshot) => snapshot,
        Err(error) => UsageSnapshot::unavailable(format!("usage parse failed: {error}")),
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub fn collect_native() -> UsageSnapshot {
    use std::process::Command;

    let output = match Command::new("python3").arg("-c").arg(SCRIPT).output() {
        Ok(out) => out,
        Err(_) => match Command::new("python").arg("-c").arg(SCRIPT).output() {
            Ok(out) => out,
            Err(error) => {
                return UsageSnapshot::unavailable(format!("python spawn failed: {error}"));
            }
        },
    };

    if !output.status.success() {
        return UsageSnapshot::unavailable(format!(
            "usage_signal.py exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    match serde_json::from_slice::<UsageSnapshot>(&output.stdout) {
        Ok(snapshot) => snapshot,
        Err(error) => UsageSnapshot::unavailable(format!("usage parse failed: {error}")),
    }
}
