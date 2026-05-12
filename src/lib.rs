//! ContextHUD extension entry point.
//!
//! The product surface is an always-on context system, not slash commands.
//! Slash commands are kept only as debug/fallback surfaces. Modules below are
//! intentionally `pub` so a future integration layer (Zed HUD primitive when
//! one ships, an ACP bridge, or an MCP server) can drive the engine without
//! redesigning anything.
//!
//! ## Verified
//! - Extension loads in Zed Preview.
//! - `process:exec` can shell out to `git` inside the worktree.
//! - Engine writes `.context-hud/{state.json,brief-*.md,AGENT.md}` artifacts.
//! - `run_slash_command` receives a `Worktree` and is the strongest verified
//!   hook to wire automatic refresh into.
//!
//! ## Unverified / explicitly isolated behind seams
//! - Zed has no public always-on HUD primitive yet. The HUD layer is expected
//!   to consume `state.json` directly when a hook exists.
//! - `zed_extension_api` 0.7 exposes no load-time or worktree-open hook, so
//!   the first refresh fires on the first agent interaction that reaches the
//!   extension (any slash command). After that, [`auto_refresh::refresh`]
//!   keeps the surface fresh idempotently. Once a real load hook ships, the
//!   call site moves; the function does not.
//! - Codex ACP threads in Zed Preview do not currently invoke extension slash
//!   commands. Agents are therefore expected to read `.context-hud/AGENT.md`
//!   from the filesystem (Codex/Claude conventions) until a richer
//!   automatic-context hook is verified.
//! - The seam for both cases is [`context_engine::assemble`], which takes
//!   pre-collected signals and is decoupled from `zed::Worktree`.

pub mod agent_context;
pub mod context_engine;
pub mod detail_html;
pub mod git_signal;
pub mod hud;
pub mod state_writer;
pub mod time_windows;
pub mod usage_signal;

#[cfg(target_arch = "wasm32")]
pub mod auto_refresh;

#[cfg(target_arch = "wasm32")]
mod slash_commands;

#[cfg(target_arch = "wasm32")]
mod extension {
    use super::{auto_refresh, slash_commands};
    use zed_extension_api::{self as zed, Result};

    struct ContextHud;

    impl zed::Extension for ContextHud {
        fn new() -> Self {
            Self
        }

        fn run_slash_command(
            &self,
            command: zed::SlashCommand,
            _args: Vec<String>,
            worktree: Option<&zed::Worktree>,
        ) -> Result<zed::SlashCommandOutput> {
            // Auto-refresh runs as a side effect of any worktree-bearing
            // entry point so the agent-visible artifacts stay current without
            // the user explicitly invoking a command. Idempotent and cheap.
            if let Some(worktree) = worktree {
                auto_refresh::refresh(worktree);
            }
            slash_commands::run(command, worktree)
        }
    }

    zed::register_extension!(ContextHud);
}
