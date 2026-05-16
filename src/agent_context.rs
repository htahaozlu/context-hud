//! Combined, agent-readable brief.
//!
//! Produces `.context-hud/AGENT.md` — a compact briefing any coding agent
//! (Codex ACP, Claude Code, future MCP bridge) can read on demand. Format
//! is stable so a future bridge can ship without redesigning the engine.
//!
//! Uncertainty: Zed Preview ACP threads do not currently surface extension
//! slash commands, and no public automatic-prompt hook is verified. Agents
//! are expected to read this file via filesystem or a future MCP/ACP bridge.

use std::path::Path;

use crate::context_engine::{ContextSnapshot, WindowSummary};

pub fn render(snapshot: &ContextSnapshot) -> String {
    let mut out = String::new();

    // ── Header ───────────────────────────────────────────────────────────────
    let repo = Path::new(&snapshot.worktree_root)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or(&snapshot.worktree_root);
    // "2026-05-11T08:23:09.304042Z" → "2026-05-11 08:23Z"
    let ts = snapshot
        .updated_at
        .get(..16)
        .unwrap_or(&snapshot.updated_at)
        .replace('T', " ");
    out.push_str(&format!(
        "# AGENT BRIEF — {} · {} · {}Z\n\n",
        repo, snapshot.branch, ts
    ));

    // ── Current focus ────────────────────────────────────────────────────────
    out.push_str("## Current focus\n");
    let now_files = &snapshot.now.top_files;
    if now_files.is_empty() {
        out.push_str("No file activity in the last 15 min.\n");
    } else {
        let primary = &now_files[0];
        let also: Vec<&str> = now_files[1..].iter().take(3).map(|s| s.as_str()).collect();
        if also.is_empty() {
            out.push_str(&format!("Active: {}\n", primary));
        } else {
            out.push_str(&format!("Active: {}  |  {}\n", primary, also.join("  ")));
        }
        if let Some(area) = snapshot.now.focus_areas.first() {
            out.push_str(&format!("Area: {}/\n", area));
        }
    }
    out.push('\n');

    // ── Open loops ───────────────────────────────────────────────────────────
    let changes = &snapshot.now.change_summary;
    if !changes.is_empty() {
        out.push_str("## Open loops\n");
        let staged: Vec<&str> = changes
            .iter()
            .filter(|c| c.staged)
            .map(|c| c.path.as_str())
            .collect();
        let modified: Vec<&str> = changes
            .iter()
            .filter(|c| c.unstaged && c.code != "??")
            .map(|c| c.path.as_str())
            .collect();
        let untracked: Vec<&str> = changes
            .iter()
            .filter(|c| c.code == "??")
            .map(|c| c.path.as_str())
            .collect();

        if !staged.is_empty() {
            out.push_str(&format!(
                "- Staged ({}): {}\n",
                staged.len(),
                staged.join("  ")
            ));
        }
        if !modified.is_empty() {
            out.push_str(&format!(
                "- Unstaged ({}): {}\n",
                modified.len(),
                modified.join("  ")
            ));
        }
        if !untracked.is_empty() {
            out.push_str(&format!(
                "- Untracked ({}): {}\n",
                untracked.len(),
                untracked.join("  ")
            ));
        }
        out.push('\n');
    }

    // ── Now (last 15 min) ────────────────────────────────────────────────────
    render_now(&mut out, &snapshot.now);

    // ── Session (last 5 hr) ──────────────────────────────────────────────────
    render_session(&mut out, &snapshot.session);

    // ── Week (last 7 days) ───────────────────────────────────────────────────
    render_week(&mut out, &snapshot.week, &snapshot.branch);

    // ── Footer ───────────────────────────────────────────────────────────────
    out.push_str("---\n");
    out.push_str(
        "hud.json is the machine-readable source. Regenerated on save; do not edit.\n",
    );

    out
}

fn render_now(out: &mut String, window: &WindowSummary) {
    if window.top_files.is_empty() {
        return;
    }
    out.push_str("## Now  (last 15 min)\n");
    let files: Vec<&str> = window.top_files.iter().take(5).map(|s| s.as_str()).collect();
    out.push_str(&format!("{}\n\n", files.join("  ")));
}

fn render_session(out: &mut String, window: &WindowSummary) {
    out.push_str("## Session  (last 5 hr)\n");

    if let Some(area) = window.focus_areas.first() {
        out.push_str(&format!("Focus: {}/\n", area));
    }

    if !window.commit_refs.is_empty() {
        let commits: Vec<String> = window
            .commit_refs
            .iter()
            .take(4)
            .map(|c| format!("{} {}", c.sha, c.subject))
            .collect();
        out.push_str(&format!("Commits: {}\n", commits.join("  ·  ")));
    } else {
        out.push_str("Commits: none in window\n");
    }

    out.push('\n');
}

fn render_week(out: &mut String, window: &WindowSummary, branch: &str) {
    out.push_str("## Week  (last 7 days)\n");

    let n = window.commit_refs.len();
    if n == 0 {
        out.push_str("No commits in window.\n");
    } else {
        let subjects: Vec<&str> = window
            .commit_refs
            .iter()
            .take(3)
            .map(|c| c.subject.as_str())
            .collect();
        out.push_str(&format!(
            "Direction: {} commit(s) on {}  —  {}\n",
            n,
            branch,
            subjects.join("  ·  ")
        ));
    }

    // Only emit themes that carry real signal (skip "focus on X" / "root-level edits")
    let signal_themes: Vec<&str> = window
        .themes
        .iter()
        .filter(|t| !t.starts_with("focus on") && t.as_str() != "root-level edits")
        .map(|t| t.as_str())
        .take(3)
        .collect();
    if !signal_themes.is_empty() {
        out.push_str(&format!("Themes: {}\n", signal_themes.join("  ·  ")));
    }

    out.push('\n');
}
