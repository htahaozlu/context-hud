//! Developer-only native harness for the context engine.
//!
//! This is NOT part of the user-facing product flow. End users install the
//! extension into Zed and the artifacts appear automatically — see
//! `src/auto_refresh.rs` and the README. Use this binary only when you need
//! to inspect or debug the engine without launching Zed.
//!
//! Usage: `cargo run --example snapshot -- [worktree_root]`
//! Default worktree_root is the current directory.

use std::env;
use std::path::PathBuf;
use std::process::Command;
use context_hud::context_engine;
use context_hud::git_signal::{
    self, ChangeSummary, CommitSummary, GitSignals,
};
use context_hud::state_writer;

fn main() {
    if let Err(error) = run() {
        eprintln!("snapshot failed: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let root = env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| env::current_dir().expect("cwd"));
    let root = root
        .canonicalize()
        .map_err(|error| format!("cannot canonicalize {}: {error}", root.display()))?;

    let git = collect_git(&root)?;
    let files = context_engine::collect_files(&root)?;
    let snapshot = context_engine::assemble(root.clone(), git, files)?;
    let result = state_writer::write(&root, &snapshot)?;

    println!("Wrote:");
    println!("  {}", result.state_path.display());
    println!("  {}", result.now_brief_path.display());
    println!("  {}", result.session_brief_path.display());
    println!("  {}", result.week_brief_path.display());
    println!("  {}  <- primary agent surface", result.agent_brief_path.display());
    println!("  {}  <- Claude Code surface", result.claude_brief_path.display());
    Ok(())
}

fn collect_git(root: &PathBuf) -> Result<GitSignals, String> {
    let branch = run_git(root, &["rev-parse", "--abbrev-ref", "HEAD"])?
        .trim()
        .to_string();
    let log = run_git(
        root,
        &["log", "--since=7 days ago", "--max-count=40", "--format=%H%x09%ct%x09%s"],
    )?;
    let recent_commits: Vec<CommitSummary> = git_signal::parse_commits(&log);
    let status = run_git(root, &["status", "--short"])?;
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

fn run_git(root: &PathBuf, args: &[&str]) -> Result<String, String> {
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
