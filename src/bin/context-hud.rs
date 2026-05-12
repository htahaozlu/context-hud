//! Standalone CLI for the ContextHUD engine.
//!
//! Why this exists: Zed `extension_api` 0.7 has no install-time hook and no
//! status-bar primitive, and Zed Preview's ACP agent threads do not surface
//! extension slash commands at all. So the in-Zed extension is effectively
//! one-shot. This binary makes the same engine usable without Zed at all —
//! run once to refresh `.context-hud/{hud.md,AGENT.md,state.json,...}`, or
//! run `watch` to keep the HUD live as a sidecar daemon.
//!
//! Subcommands:
//!   `hud`          — refresh artifacts in the given (or current) repo and
//!                    print the HUD to stdout
//!   `snapshot`     — same as `hud` but without printing the HUD body
//!   `watch [secs]` — loop forever, refreshing every `secs` seconds (default 30)
//!
//! Example: `context-hud watch 30 .` (or set up launchd to keep this alive).

use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

use serde_json;

use context_hud::context_engine::{self, ContextSnapshot};
use context_hud::git_signal::{self, ChangeSummary, CommitSummary, GitSignals};
use context_hud::hud;
use context_hud::state_writer;
use context_hud::usage_signal;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("hud");

    let exit_code = match cmd {
        "hud" => run_hud(args.get(1).map(PathBuf::from)),
        "snapshot" => run_snapshot(args.get(1).map(PathBuf::from)),
        "global" => run_global(),
        "watch" => {
            let secs: u64 = args
                .get(1)
                .and_then(|value| value.parse().ok())
                .unwrap_or(30);
            let root = args.get(2).map(PathBuf::from);
            run_watch(root, secs)
        }
        "watch-global" => {
            let secs: u64 = args
                .get(1)
                .and_then(|value| value.parse().ok())
                .unwrap_or(30);
            run_watch_global(secs)
        }
        "--help" | "-h" | "help" => {
            print_help();
            0
        }
        other => {
            eprintln!("unknown command: {other}");
            print_help();
            2
        }
    };

    std::process::exit(exit_code);
}

fn print_help() {
    eprintln!(
        "context-hud — Claude Code + Codex CLI usage HUD for any repo\n\n\
         USAGE:\n\
         \x20   context-hud hud          [worktree_root]   refresh repo .context-hud/hud.md\n\
         \x20   context-hud snapshot     [worktree_root]   refresh full repo artifacts\n\
         \x20   context-hud global                         write ~/.context-hud/hud.md\n\
         \x20   context-hud watch        [secs] [root]     loop per-repo (default 30s)\n\
         \x20   context-hud watch-global [secs]            loop ~/.context-hud/hud.md\n\n\
         Pin `~/.context-hud/hud.md` in Zed for an always-visible cross-project HUD.\n"
    );
}

fn run_hud(root: Option<PathBuf>) -> i32 {
    match refresh(root) {
        Ok((root, snapshot)) => {
            print!("{}", hud::render(&snapshot, &snapshot.usage));
            eprintln!("\nHUD written to {}/.context-hud/hud.md", root.display());
            0
        }
        Err(error) => {
            eprintln!("hud failed: {error}");
            1
        }
    }
}

fn run_snapshot(root: Option<PathBuf>) -> i32 {
    match refresh(root) {
        Ok((root, _)) => {
            println!("artifacts refreshed in {}/.context-hud/", root.display());
            0
        }
        Err(error) => {
            eprintln!("snapshot failed: {error}");
            1
        }
    }
}

fn run_global() -> i32 {
    match refresh_global() {
        Ok(path) => {
            let body = std::fs::read_to_string(&path).unwrap_or_default();
            print!("{body}");
            eprintln!("\nHUD written to {}", path.display());
            0
        }
        Err(error) => {
            eprintln!("global hud failed: {error}");
            1
        }
    }
}

fn run_watch_global(secs: u64) -> i32 {
    eprintln!("context-hud watch-global: every {secs}s. Ctrl-C to stop.");
    loop {
        match refresh_global() {
            Ok(path) => eprintln!("[{}] refreshed {}", now_local(), path.display()),
            Err(error) => eprintln!("[{}] refresh error: {error}", now_local()),
        }
        thread::sleep(Duration::from_secs(secs));
    }
}

fn refresh_global() -> Result<PathBuf, String> {
    use time::{OffsetDateTime, format_description::well_known::Rfc3339};

    let home = env::var("HOME").map_err(|_| "HOME not set".to_string())?;
    let dir = PathBuf::from(&home).join(".context-hud");
    std::fs::create_dir_all(&dir)
        .map_err(|error| format!("mkdir {} failed: {error}", dir.display()))?;
    let path = dir.join("hud.md");

    let usage = usage_signal::collect_native();
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());

    let mut out = String::new();
    out.push_str("# Agent HUD (global)\n\n");
    out.push_str(&format!("_Updated: `{now}` · Source: `{}`_\n\n", usage.source));
    out.push_str("| Agent | Session (5h) | Week (7d) | Context | Model | Last turn |\n");
    out.push_str("|---|---:|---:|---:|---|---|\n");
    out.push_str(&format_usage_row("Claude", &usage.claude));
    out.push_str(&format_usage_row("Codex", &usage.codex));
    if usage.source != "python3" {
        out.push_str(&format!("\n> Usage unavailable: {}\n", usage.source));
    }

    std::fs::write(&path, out.as_bytes())
        .map_err(|error| format!("write {} failed: {error}", path.display()))?;

    // JSON sidecar — consumed by the menubar app for structured rendering.
    let json_path = dir.join("hud.json");
    let json = serde_json::to_string_pretty(&usage)
        .map_err(|error| format!("serialize hud.json failed: {error}"))?;
    std::fs::write(&json_path, json.as_bytes())
        .map_err(|error| format!("write {} failed: {error}", json_path.display()))?;

    // Detail page — opened by the menubar app's "Open detail" action.
    let html = context_hud::detail_html::render(&usage);
    let html_path = dir.join("detail.html");
    std::fs::write(&html_path, html.as_bytes())
        .map_err(|error| format!("write {} failed: {error}", html_path.display()))?;

    Ok(path)
}

fn format_usage_row(label: &str, usage: &context_hud::usage_signal::AgentUsage) -> String {
    let ctx = match (usage.last_context_pct, usage.last_context_window) {
        (Some(pct), Some(window)) => format!("{pct:.1}% of {}", fmt_tokens(window)),
        (Some(pct), None) => format!("{pct:.1}%"),
        _ => "—".to_string(),
    };
    let model = usage.last_model.as_deref().unwrap_or("—");
    let last = usage.last_turn_at.as_deref().unwrap_or("—");
    format!(
        "| {label} | {} | {} | {ctx} | `{model}` | {last} |\n",
        fmt_tokens(usage.session_5h_tokens),
        fmt_tokens(usage.week_7d_tokens),
    )
}

fn fmt_tokens(value: u64) -> String {
    if value >= 1_000_000 {
        format!("{:.2}M", value as f64 / 1_000_000.0)
    } else if value >= 1_000 {
        format!("{:.1}k", value as f64 / 1_000.0)
    } else {
        value.to_string()
    }
}

fn run_watch(root: Option<PathBuf>, secs: u64) -> i32 {
    eprintln!("context-hud watch: every {secs}s. Ctrl-C to stop.");
    loop {
        match refresh(root.clone()) {
            Ok((root, _)) => eprintln!(
                "[{}] refreshed {}/.context-hud/hud.md",
                now_local(),
                root.display()
            ),
            Err(error) => eprintln!("[{}] refresh error: {error}", now_local()),
        }
        thread::sleep(Duration::from_secs(secs));
    }
}

fn refresh(root: Option<PathBuf>) -> Result<(PathBuf, ContextSnapshot), String> {
    let root = root
        .unwrap_or_else(|| env::current_dir().expect("cwd"))
        .canonicalize()
        .map_err(|error| format!("canonicalize failed: {error}"))?;

    let git = collect_git(&root)?;
    let files = context_engine::collect_files(&root)?;
    let mut snapshot = context_engine::assemble(root.clone(), git, files)?;
    snapshot.usage = usage_signal::collect_native();
    state_writer::write(&root, &snapshot)?;
    Ok((root, snapshot))
}

fn collect_git(root: &Path) -> Result<GitSignals, String> {
    let branch = run_git(root, &["rev-parse", "--abbrev-ref", "HEAD"])
        .unwrap_or_else(|_| "HEAD".to_string())
        .trim()
        .to_string();
    let log = run_git(
        root,
        &["log", "--since=7 days ago", "--max-count=40", "--format=%H%x09%ct%x09%s"],
    )
    .unwrap_or_default();
    let recent_commits: Vec<CommitSummary> = git_signal::parse_commits(&log);
    let status = run_git(root, &["status", "--short"]).unwrap_or_default();
    let (staged, unstaged): (Vec<ChangeSummary>, Vec<ChangeSummary>) =
        git_signal::parse_status_public(&status);
    let clean = staged.is_empty() && unstaged.is_empty();
    Ok(GitSignals {
        branch,
        recent_commits,
        staged_changes: staged,
        unstaged_changes: unstaged,
        clean_worktree: clean,
    })
}

fn run_git(root: &Path, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .map_err(|error| format!("git spawn failed: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    String::from_utf8(output.stdout).map_err(|error| format!("git utf8: {error}"))
}

fn now_local() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{}", secs)
}
