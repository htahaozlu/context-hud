use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::agent_context;
use crate::context_engine::{ContextSnapshot, render_window_markdown};
use crate::hud;

#[cfg(target_arch = "wasm32")]
use zed_extension_api::serde_json;

#[derive(Clone, Debug)]
pub struct StateWriteResult {
    pub state_path: PathBuf,
    pub now_brief_path: PathBuf,
    pub session_brief_path: PathBuf,
    pub week_brief_path: PathBuf,
    pub agent_brief_path: PathBuf,
    pub claude_brief_path: PathBuf,
    pub hud_path: PathBuf,
}

/// Write all artifacts. Each file is staged to a sibling `*.tmp` path then
/// renamed into place, so an agent reading `.zed-context/AGENT.md` (or any
/// brief) never observes a truncated mid-write file. Renames on the same
/// filesystem are atomic on POSIX and Windows ReplaceFileW.
pub fn write(root: &Path, snapshot: &ContextSnapshot) -> Result<StateWriteResult, String> {
    let state_dir = root.join(".zed-context");
    fs::create_dir_all(&state_dir)
        .map_err(|error| format!("failed to create {}: {error}", state_dir.display()))?;

    let state_path = state_dir.join("state.json");
    let now_brief_path = state_dir.join("brief-now.md");
    let session_brief_path = state_dir.join("brief-session.md");
    let week_brief_path = state_dir.join("brief-week.md");
    let agent_brief_path = state_dir.join("AGENT.md");
    let claude_brief_path = root.join("CLAUDE.md");
    let hud_path = state_dir.join("hud.md");

    let json = serde_json::to_string_pretty(snapshot)
        .map_err(|error| format!("failed to serialize state.json: {error}"))?;

    atomic_write(&state_path, json.as_bytes())?;
    atomic_write(
        &now_brief_path,
        render_window_markdown(snapshot, "now").as_bytes(),
    )?;
    atomic_write(
        &session_brief_path,
        render_window_markdown(snapshot, "session").as_bytes(),
    )?;
    atomic_write(
        &week_brief_path,
        render_window_markdown(snapshot, "week").as_bytes(),
    )?;
    atomic_write(&agent_brief_path, agent_context::render(snapshot).as_bytes())?;
    atomic_write(&claude_brief_path, agent_context::render(snapshot).as_bytes())?;
    atomic_write(&hud_path, hud::render(snapshot, &snapshot.usage).as_bytes())?;

    Ok(StateWriteResult {
        state_path,
        now_brief_path,
        session_brief_path,
        week_brief_path,
        agent_brief_path,
        claude_brief_path,
        hud_path,
    })
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let tmp = path.with_extension(format!(
        "{}.tmp",
        path.extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
    ));
    fs::write(&tmp, bytes)
        .map_err(|error| format!("failed to write {}: {error}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|error| {
        let _ = fs::remove_file(&tmp);
        format!("failed to rename {} -> {}: {error}", tmp.display(), path.display())
    })
}
