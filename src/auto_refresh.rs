//! Automatic context refresh.
//!
//! Product goal: user installs the extension, opens Zed on a repo, and
//! `.context-hud/AGENT.md` plus `state.json` appear without them running a
//! command.
//!
//! Verified limit: as of `zed_extension_api` 0.7, no public extension hook
//! fires "on worktree open" with a `Worktree` handle. The only verified
//! entry points that receive a worktree are slash-command callbacks. So the
//! refresh is wired into every such entry point as a side effect. Once Zed
//! ships a load-time hook, the call site changes but [`refresh`] does not.
//!
//! Idempotency: a fresh `.context-hud/state.json` (younger than
//! [`MIN_REFRESH_INTERVAL`]) short-circuits the work. This keeps repeat
//! invocations cheap and avoids noisy churn when nothing meaningful changed.

#[cfg(target_arch = "wasm32")]
use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

#[cfg(target_arch = "wasm32")]
use zed_extension_api as zed;

#[cfg(target_arch = "wasm32")]
use crate::{context_engine::ContextEngine, state_writer};

#[cfg(target_arch = "wasm32")]
const MIN_REFRESH_INTERVAL: Duration = Duration::from_secs(20);

/// Best-effort, idempotent context refresh.
///
/// Errors are intentionally swallowed. The artifacts are advisory; callers
/// must not depend on them succeeding, and any later explicit invocation
/// (e.g. the `/doctor` slash command) will surface the real error.
#[cfg(target_arch = "wasm32")]
pub fn refresh(worktree: &zed::Worktree) {
    let _ = try_refresh(worktree);
}

#[cfg(target_arch = "wasm32")]
fn try_refresh(worktree: &zed::Worktree) -> Result<(), String> {
    let root = PathBuf::from(worktree.root_path());
    let state_path = root.join(".context-hud").join("state.json");
    if is_fresh(&state_path) {
        return Ok(());
    }
    let snapshot = ContextEngine::generate(worktree)?;
    state_writer::write(&root, &snapshot)?;
    Ok(())
}

#[cfg(target_arch = "wasm32")]
fn is_fresh(state_path: &Path) -> bool {
    let Ok(metadata) = fs::metadata(state_path) else {
        return false;
    };
    let Ok(modified) = metadata.modified() else {
        return false;
    };
    SystemTime::now()
        .duration_since(modified)
        .map(|age| age < MIN_REFRESH_INTERVAL)
        .unwrap_or(false)
}
