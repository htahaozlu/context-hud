use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    time::SystemTime,
};

use serde::Serialize;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
#[cfg(target_arch = "wasm32")]
use zed_extension_api as zed;

use crate::{
    git_signal::{ChangeSummary, CommitSummary, GitSignals},
    time_windows::{NOW_WINDOW, SESSION_WINDOW, WEEK_WINDOW},
    usage_signal::UsageSnapshot,
};
#[cfg(target_arch = "wasm32")]
use crate::{git_signal, usage_signal};

#[derive(Clone, Debug, Serialize)]
pub struct TouchedFile {
    pub path: String,
    pub modified_at: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct WindowSummary {
    pub label: String,
    pub top_files: Vec<String>,
    pub focus_areas: Vec<String>,
    pub themes: Vec<String>,
    pub resume_hint: String,
    pub commit_refs: Vec<CommitSummary>,
    pub change_summary: Vec<ChangeSummary>,
}

#[derive(Clone, Debug, Serialize)]
pub struct AssistantMemory {
    pub latest_summary: String,
    pub thread_refs: Vec<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ContextSnapshot {
    pub worktree_root: String,
    pub branch: String,
    pub updated_at: String,
    pub touched_files: Vec<TouchedFile>,
    pub now: WindowSummary,
    pub session: WindowSummary,
    pub week: WindowSummary,
    pub assistant_memory: AssistantMemory,
    #[serde(default)]
    pub usage: UsageSnapshot,
}

#[derive(Clone, Debug)]
pub struct FileObservation {
    pub relative_path: String,
    pub modified_at: SystemTime,
}

pub struct ContextEngine;

impl ContextEngine {
    /// Convenience entry point bound to Zed's `Worktree`. The actual snapshot
    /// assembly is delegated to [`assemble`] so non-Zed integration layers
    /// (e.g. a future MCP server or ACP bridge) can drive the engine with
    /// their own signal sources without redesign.
    #[cfg(target_arch = "wasm32")]
    pub fn generate(worktree: &zed::Worktree) -> Result<ContextSnapshot, String> {
        let root = PathBuf::from(worktree.root_path());
        let git = git_signal::collect(worktree)?;
        let touched_files = collect_file_observations(&root)?;
        let usage = usage_signal::collect(worktree);
        let mut snapshot = assemble(root, git, touched_files)?;
        snapshot.usage = usage;
        Ok(snapshot)
    }
}

/// Assemble a [`ContextSnapshot`] from already-collected signals. This is the
/// stable seam any future integration layer (HUD, ACP, MCP) plugs into.
pub fn assemble(
    root: PathBuf,
    git: GitSignals,
    touched_files: Vec<FileObservation>,
) -> Result<ContextSnapshot, String> {
    {
        let updated_at = timestamp(SystemTime::now())?;

        let now_files = filter_files_for_window(&touched_files, NOW_WINDOW.duration);
        let session_files = filter_files_for_window(&touched_files, SESSION_WINDOW.duration);
        let week_files = filter_files_for_window(&touched_files, WEEK_WINDOW.duration);

        let snapshot = ContextSnapshot {
            worktree_root: root.display().to_string(),
            branch: git.branch.clone(),
            updated_at,
            touched_files: touched_files
                .iter()
                .take(25)
                .map(|file| {
                    Ok(TouchedFile {
                        path: file.relative_path.clone(),
                        modified_at: timestamp(file.modified_at)?,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?,
            now: summarize_window(NOW_WINDOW.label, &git, &now_files, NOW_WINDOW.duration, true),
            session: summarize_window(SESSION_WINDOW.label, &git, &session_files, SESSION_WINDOW.duration, false),
            week: summarize_window(WEEK_WINDOW.label, &git, &week_files, WEEK_WINDOW.duration, false),
            assistant_memory: AssistantMemory {
                latest_summary: build_assistant_memory(&git, &session_files),
                thread_refs: Vec::new(),
            },
            usage: UsageSnapshot::default(),
        };

        Ok(snapshot)
    }
}

pub fn collect_files(root: &Path) -> Result<Vec<FileObservation>, String> {
    collect_file_observations(root)
}

pub fn render_window_markdown(snapshot: &ContextSnapshot, window: &str) -> String {
    let summary = match window {
        "now" => &snapshot.now,
        "session" => &snapshot.session,
        "week" => &snapshot.week,
        _ => &snapshot.now,
    };

    let mut lines = vec![
        format!("# {} brief", summary.label),
        String::new(),
        format!("- worktree: {}", snapshot.worktree_root),
        format!("- branch: {}", snapshot.branch),
        format!("- updated_at: {}", snapshot.updated_at),
        String::new(),
        "## Resume hint".to_string(),
        summary.resume_hint.clone(),
        String::new(),
    ];

    if !summary.top_files.is_empty() {
        lines.push("## Top files".to_string());
        lines.extend(summary.top_files.iter().map(|path| format!("- {path}")));
        lines.push(String::new());
    }

    if !summary.focus_areas.is_empty() {
        lines.push("## Focus areas".to_string());
        lines.extend(summary.focus_areas.iter().map(|path| format!("- {path}")));
        lines.push(String::new());
    }

    if !summary.themes.is_empty() {
        lines.push("## Themes".to_string());
        lines.extend(summary.themes.iter().map(|theme| format!("- {theme}")));
        lines.push(String::new());
    }

    if !summary.commit_refs.is_empty() {
        lines.push("## Recent commits".to_string());
        lines.extend(
            summary
                .commit_refs
                .iter()
                .map(|commit| format!("- {} {}", commit.sha, commit.subject)),
        );
        lines.push(String::new());
    }

    if !summary.change_summary.is_empty() {
        lines.push("## Local changes".to_string());
        lines.extend(
            summary
                .change_summary
                .iter()
                .map(|change| format!("- {} {}", change.code, change.path)),
        );
    }

    lines.join("\n").trim().to_string() + "\n"
}

fn summarize_window(
    label: &str,
    git: &GitSignals,
    files: &[FileObservation],
    window: std::time::Duration,
    include_local_changes: bool,
) -> WindowSummary {
    let top_files = files
        .iter()
        .take(6)
        .map(|file| file.relative_path.clone())
        .collect::<Vec<_>>();

    let windowed_commits = filter_commits_for_window(&git.recent_commits, window);
    let focus_areas = top_directories(files, 4);
    let themes = derive_themes(files, &windowed_commits, 4);
    let change_summary = if include_local_changes {
        combine_change_summary(git, 8)
    } else {
        Vec::new()
    };

    let resume_hint = match label {
        "now" => {
            if top_files.is_empty() {
                format!("No files changed in the last {} minutes.", NOW_WINDOW.duration.as_secs() / 60)
            } else {
                format!(
                    "Continue in {} on branch {}. Local changes are concentrated in {}.",
                    top_files[0],
                    git.branch,
                    focus_areas
                        .first()
                        .cloned()
                        .unwrap_or_else(|| "the worktree root".to_string())
                )
            }
        }
        "session" => format!(
            "Session focus is {} with {} recent file touches.",
            focus_areas
                .first()
                .cloned()
                .unwrap_or_else(|| "mixed project areas".to_string()),
            files.len()
        ),
        _ => format!(
            "Weekly pattern points to {} and {} recent commits on {}.",
            focus_areas
                .first()
                .cloned()
                .unwrap_or_else(|| "mixed project areas".to_string()),
            windowed_commits.len(),
            git.branch
        ),
    };

    WindowSummary {
        label: label.to_string(),
        top_files,
        focus_areas,
        themes,
        resume_hint,
        commit_refs: windowed_commits.into_iter().take(6).collect(),
        change_summary,
    }
}

fn filter_commits_for_window(
    commits: &[CommitSummary],
    window: std::time::Duration,
) -> Vec<CommitSummary> {
    let now = SystemTime::now();
    commits
        .iter()
        .filter(|commit| match commit.committed_at_system {
            Some(time) => now
                .duration_since(time)
                .map(|age| age <= window)
                .unwrap_or(true),
            // If timestamp is missing, fall back to inclusion only for the
            // widest window so older parsing paths still produce output.
            None => window >= WEEK_WINDOW.duration,
        })
        .cloned()
        .collect()
}

fn build_assistant_memory(git: &GitSignals, session_files: &[FileObservation]) -> String {
    let top_file = session_files
        .first()
        .map(|file| file.relative_path.as_str())
        .unwrap_or("no recent files");
    let commit = git
        .recent_commits
        .first()
        .map(|commit| commit.subject.as_str())
        .unwrap_or("no recent commits");

    format!(
        "Current branch is {}. Session focus is {}. Latest visible commit theme: {}.",
        git.branch, top_file, commit
    )
}

fn combine_change_summary(git: &GitSignals, limit: usize) -> Vec<ChangeSummary> {
    git.staged_changes
        .iter()
        .chain(git.unstaged_changes.iter())
        .take(limit)
        .cloned()
        .collect()
}

fn derive_themes(
    files: &[FileObservation],
    commits: &[CommitSummary],
    limit: usize,
) -> Vec<String> {
    let mut themes = Vec::new();

    for area in top_directories(files, limit) {
        if area != "." {
            themes.push(format!("focus on {area}"));
        }
    }

    for commit in commits.iter().take(limit) {
        if themes.len() >= limit {
            break;
        }
        themes.push(commit.subject.clone());
    }

    themes
}

fn top_directories(files: &[FileObservation], limit: usize) -> Vec<String> {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();

    for file in files {
        let area = Path::new(&file.relative_path)
            .parent()
            .map(|path| {
                let value = path.to_string_lossy().to_string();
                if value.is_empty() { ".".to_string() } else { value }
            })
            .unwrap_or_else(|| ".".to_string());
        if is_noise_area(&area) {
            continue;
        }
        *counts.entry(area).or_default() += 1;
    }

    let mut entries = counts.into_iter().collect::<Vec<_>>();
    entries.sort_by(|left, right| right.1.cmp(&left.1).then_with(|| left.0.cmp(&right.0)));

    entries.into_iter().take(limit).map(|(path, _)| path).collect()
}

fn is_noise_area(area: &str) -> bool {
    matches!(
        area,
        "." | ".git" | ".tmp" | ".context-hud" | "target" | "node_modules"
    )
}

fn filter_files_for_window(
    files: &[FileObservation],
    duration: std::time::Duration,
) -> Vec<FileObservation> {
    files.iter()
        .filter(|file| {
            SystemTime::now()
                .duration_since(file.modified_at)
                .map(|age| age <= duration)
                .unwrap_or(false)
        })
        .cloned()
        .collect()
}

fn collect_file_observations(root: &Path) -> Result<Vec<FileObservation>, String> {
    let mut observations = Vec::new();
    collect_dir(root, root, &mut observations)?;
    observations.sort_by(|left, right| right.modified_at.cmp(&left.modified_at));
    Ok(observations)
}

fn collect_dir(
    root: &Path,
    current: &Path,
    observations: &mut Vec<FileObservation>,
) -> Result<(), String> {
    for entry in fs::read_dir(current)
        .map_err(|error| format!("failed to read directory {}: {error}", current.display()))?
    {
        let entry = entry.map_err(|error| format!("failed to inspect directory entry: {error}"))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .map_err(|error| format!("failed to read file type for {}: {error}", path.display()))?;

        if file_type.is_symlink() {
            continue;
        }

        if file_type.is_dir() {
            if should_skip_dir(&path) {
                continue;
            }
            collect_dir(root, &path, observations)?;
            continue;
        }

        if !file_type.is_file() {
            continue;
        }

        if should_skip_file(&path) {
            continue;
        }

        let metadata = entry
            .metadata()
            .map_err(|error| format!("failed to read metadata for {}: {error}", path.display()))?;
        let modified_at = match metadata.modified() {
            Ok(modified_at) => modified_at,
            Err(_) => continue,
        };

        let relative_path = path
            .strip_prefix(root)
            .map_err(|error| format!("failed to compute relative path for {}: {error}", path.display()))?
            .to_string_lossy()
            .to_string();

        observations.push(FileObservation {
            relative_path,
            modified_at,
        });
    }

    Ok(())
}

fn should_skip_dir(path: &Path) -> bool {
    matches!(
        path.file_name().and_then(|value| value.to_str()),
        Some(".git" | "target" | ".context-hud" | "node_modules" | ".tmp")
    )
}

fn should_skip_file(path: &Path) -> bool {
    matches!(
        path.file_name().and_then(|value| value.to_str()),
        Some("extension.wasm" | "Cargo.lock")
    )
}

fn timestamp(time: SystemTime) -> Result<String, String> {
    let datetime = OffsetDateTime::from(time);
    datetime
        .format(&Rfc3339)
        .map_err(|error| format!("failed to format timestamp: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{CommitSummary, FileObservation, derive_themes, top_directories};
    use std::time::SystemTime;

    #[test]
    fn picks_top_directories_from_recent_files() {
        let files = vec![
            FileObservation {
                relative_path: "src/lib.rs".to_string(),
                modified_at: SystemTime::now(),
            },
            FileObservation {
                relative_path: "src/context_engine.rs".to_string(),
                modified_at: SystemTime::now(),
            },
            FileObservation {
                relative_path: "docs/02-architecture.md".to_string(),
                modified_at: SystemTime::now(),
            },
        ];

        let areas = top_directories(&files, 2);
        assert_eq!(areas, vec!["src".to_string(), "docs".to_string()]);
    }

    #[test]
    fn derives_themes_from_files_and_commits() {
        let files = vec![FileObservation {
            relative_path: "src/lib.rs".to_string(),
            modified_at: SystemTime::now(),
        }];
        let commits = vec![CommitSummary {
            sha: "abc1234".to_string(),
            subject: "Add context engine".to_string(),
            committed_at: None,
            committed_at_system: None,
        }];

        let themes = derive_themes(&files, &commits, 4);
        assert!(themes.iter().any(|theme| theme.contains("src")));
        assert!(themes.iter().any(|theme| theme.contains("Add context engine")));
    }
}
