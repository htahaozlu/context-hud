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

/// One in-flight session for an agent — a JSONL file whose last turn is
/// within ACTIVE_WINDOW (currently 30 minutes). Multiple of these can be
/// live at the same time when the user runs 3-5 sessions in parallel.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ActiveSession {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub tokens: u64,
    #[serde(default)]
    pub started_at: Option<String>,
    #[serde(default)]
    pub last_turn_at: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub project: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct AgentUsage {
    #[serde(default)]
    pub session_5h_tokens: u64,
    #[serde(default)]
    pub session_5h_percent: Option<f64>,
    #[serde(default)]
    pub week_7d_tokens: u64,
    #[serde(default)]
    pub week_7d_percent: Option<f64>,
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
    #[serde(default)]
    pub active_sessions: Vec<ActiveSession>,
    #[serde(default)]
    pub session_5h_resets_at: Option<String>,
    #[serde(default)]
    pub week_7d_resets_at: Option<String>,
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
pub struct ToolSummary {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub sessions_7d: u64,
    #[serde(default)]
    pub sessions_today: u64,
    #[serde(default)]
    pub tokens_7d: u64,
    #[serde(default)]
    pub tokens_today: u64,
    #[serde(default)]
    pub last_used: Option<String>,
    #[serde(default)]
    pub last_model: Option<String>,
}

/// Subscription account read from `~/.claude/auth-*.json`.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct AccountInfo {
    /// Filename stem, e.g. "hasan" from auth-hasan.json.
    pub name: String,
    /// "pro", "max", "free", etc.
    pub subscription_type: String,
    /// Raw tier string from the auth file.
    pub rate_limit_tier: String,
    /// Rolling 5-hour message limit (0 = unknown).
    pub limit_5h_messages: u32,
    /// Rolling 7-day message limit (0 = unknown).
    pub limit_7d_messages: u32,
    /// Whether this is the currently active account (matched via keychain).
    pub is_active: bool,
}

impl AccountInfo {
    fn from_tier(name: String, subscription_type: String, rate_limit_tier: String) -> Self {
        let (limit_5h_messages, limit_7d_messages) = match rate_limit_tier.as_str() {
            t if t.contains("max_20x") => (900, 4500),
            t if t.contains("max_5x") => (225, 1125),
            t if t.contains("max") => (225, 1125),
            _ => (45, 225),
        };
        Self { name, subscription_type, rate_limit_tier, limit_5h_messages, limit_7d_messages, is_active: false }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct UsageSnapshot {
    #[serde(default)]
    pub claude: AgentUsage,
    #[serde(default)]
    pub codex: AgentUsage,
    #[serde(default)]
    pub others: Vec<ToolSummary>,
    #[serde(default)]
    pub accounts: Vec<AccountInfo>,
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

#[cfg(target_arch = "wasm32")]
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

    let script_path = concat!(env!("CARGO_MANIFEST_DIR"), "/src/usage_signal.py");

    let output = match Command::new("python3").arg(script_path).output() {
        Ok(out) => out,
        Err(_) => match Command::new("python").arg(script_path).output() {
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
        Ok(mut snapshot) => {
            snapshot.accounts = collect_accounts();
            snapshot
        }
        Err(error) => UsageSnapshot::unavailable(format!("usage parse failed: {error}")),
    }
}

/// Reads all `~/.claude/auth-*.json` files and returns one `AccountInfo` per file.
/// Marks the active account by matching the token stored in macOS Keychain under
/// service "Claude Code-credentials".
#[cfg(not(target_arch = "wasm32"))]
fn collect_accounts() -> Vec<AccountInfo> {
    use std::fs;
    use serde_json;

    let home = match std::env::var("HOME") {
        Ok(h) => h,
        Err(_) => return vec![],
    };
    let claude_dir = std::path::PathBuf::from(&home).join(".claude");

    let read_dir = match fs::read_dir(&claude_dir) {
        Ok(d) => d,
        Err(_) => return vec![],
    };

    let paths: Vec<_> = read_dir
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with("auth-") && n.ends_with(".json"))
                .unwrap_or(false)
        })
        .collect();

    // Read the active token prefix from keychain.
    let active_token_prefix = active_token_prefix_from_keychain();

    let mut accounts = Vec::new();
    for path in &paths {
        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .trim_start_matches("auth-")
            .to_string();

        let Ok(content) = fs::read_to_string(path) else { continue };
        let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) else { continue };

        let oauth = &val["claudeAiOauth"];
        let subscription_type = oauth["subscriptionType"]
            .as_str()
            .unwrap_or("unknown")
            .to_string();
        let rate_limit_tier = oauth["rateLimitTier"]
            .as_str()
            .unwrap_or("")
            .to_string();
        let file_token = oauth["accessToken"].as_str().unwrap_or("");

        let mut info = AccountInfo::from_tier(stem, subscription_type, rate_limit_tier);
        if let Some(ref prefix) = active_token_prefix {
            if !file_token.is_empty() && file_token.starts_with(prefix.as_str()) {
                info.is_active = true;
            }
        }
        accounts.push(info);
    }

    accounts.sort_by(|a, b| a.name.cmp(&b.name));

    // If exactly one account exists, treat it as active regardless.
    if accounts.len() == 1 {
        accounts[0].is_active = true;
    }

    accounts
}

/// Returns the first 40 chars of the access token stored in the macOS Keychain
/// under service "Claude Code-credentials", or None if unavailable.
#[cfg(not(target_arch = "wasm32"))]
fn active_token_prefix_from_keychain() -> Option<String> {
    let output = std::process::Command::new("security")
        .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
    // The stored value is the full auth JSON — parse it.
    if let Ok(val) = serde_json::from_str::<serde_json::Value>(&raw) {
        let token = val["claudeAiOauth"]["accessToken"].as_str()?;
        return Some(token[..token.len().min(40)].to_string());
    }
    // Fallback: stored value might itself be just the token string.
    if raw.starts_with("sk-ant") {
        return Some(raw[..raw.len().min(40)].to_string());
    }
    None
}
