//! HUD rendering.
//!
//! Produces `.zed-context/hud.md`, the always-visible surface that mirrors
//! claude-hud's session / week / context-percent panel for both Claude Code
//! and Codex CLI. The file is plain markdown so it renders in any Zed buffer
//! today; once a real status-bar extension API ships, the same fields will
//! drive it directly from `state.json`.

use crate::context_engine::ContextSnapshot;
use crate::usage_signal::{AgentUsage, UsageSnapshot};

pub fn render(snapshot: &ContextSnapshot, usage: &UsageSnapshot) -> String {
    let mut out = String::new();
    out.push_str("# Agent HUD\n\n");
    out.push_str(&format!(
        "_Updated: `{}` · Source: `{}`_\n\n",
        snapshot.updated_at, usage.source
    ));

    out.push_str("| Agent | Session (5h) | Week (7d) | Context | Model | Last turn |\n");
    out.push_str("|---|---:|---:|---:|---|---|\n");
    out.push_str(&format_row("Claude", &usage.claude));
    out.push_str(&format_row("Codex", &usage.codex));
    out.push('\n');

    if usage.source != "python3" {
        out.push_str(&format!(
            "> Usage data unavailable: {}\n> Falling back to git-only signals.\n\n",
            usage.source
        ));
    }

    out.push_str(&format!("## Worktree\n- `{}`\n- branch `{}`\n",
        snapshot.worktree_root, snapshot.branch));

    out
}

fn format_row(label: &str, usage: &AgentUsage) -> String {
    let ctx = match (usage.last_context_pct, usage.last_context_window) {
        (Some(pct), Some(window)) => format!("{pct:.1}% of {}", format_tokens(window)),
        (Some(pct), None) => format!("{pct:.1}%"),
        _ => "—".to_string(),
    };
    let model = usage.last_model.as_deref().unwrap_or("—");
    let last = usage.last_turn_at.as_deref().unwrap_or("—");
    format!(
        "| {label} | {} | {} | {ctx} | `{model}` | {last} |\n",
        format_tokens(usage.session_5h_tokens),
        format_tokens(usage.week_7d_tokens),
    )
}

fn format_tokens(value: u64) -> String {
    if value >= 1_000_000 {
        format!("{:.2}M", value as f64 / 1_000_000.0)
    } else if value >= 1_000 {
        format!("{:.1}k", value as f64 / 1_000.0)
    } else {
        value.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::format_tokens;

    #[test]
    fn token_formatting_uses_compact_units() {
        assert_eq!(format_tokens(42), "42");
        assert_eq!(format_tokens(1500), "1.5k");
        assert_eq!(format_tokens(2_500_000), "2.50M");
    }
}
