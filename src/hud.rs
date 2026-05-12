//! HUD rendering.
//!
//! Produces `.context-hud/hud.md`, the always-visible surface that mirrors
//! claude-hud's session / week / context-percent panel for both Claude Code
//! and Codex CLI. The file is plain markdown so it renders in any Zed buffer
//! today; once a real status-bar extension API ships, the same fields will
//! drive it directly from `state.json`.

use crate::context_engine::ContextSnapshot;
use crate::usage_signal::{AccountInfo, AgentUsage, UsageSnapshot};

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

    let active = usage.accounts.iter().find(|a| a.is_active)
        .or_else(|| usage.accounts.first());
    if let Some(a) = active {
        out.push_str("## Limits\n\n");
        out.push_str("| | 5h session | 7d week |\n");
        out.push_str("|---|---|---|\n");
        out.push_str(&format_limit_row(a, &usage.claude));
        out.push('\n');
    }

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

fn format_limit_row(a: &AccountInfo, claude: &AgentUsage) -> String {
    let plan = match a.subscription_type.as_str() {
        "pro" => "Pro",
        "max" => {
            if a.rate_limit_tier.contains("20x") { "Max 20×" }
            else if a.rate_limit_tier.contains("5x") { "Max 5×" }
            else { "Max" }
        }
        _ => &a.subscription_type,
    };
    let cell5h = format_pct_cell(claude.session_5h_percent, a.limit_5h_messages);
    let cell7d = format_pct_cell(claude.week_7d_percent, a.limit_7d_messages);
    format!("| {} {} | {} | {} |\n", a.name, plan, cell5h, cell7d)
}

fn format_pct_cell(pct: Option<f64>, total: u32) -> String {
    match pct {
        Some(p) => {
            let bar = ascii_bar(p, 10);
            let used = ((p / 100.0) * total as f64).round() as u32;
            format!("{bar} **{p:.0}%** ({used}/{total})")
        }
        None => {
            if total > 0 { format!("— / {total} msgs") } else { "—".to_string() }
        }
    }
}

fn ascii_bar(pct: f64, width: usize) -> String {
    let filled = ((pct / 100.0) * width as f64).round() as usize;
    let filled = filled.min(width);
    format!("{}{}", "█".repeat(filled), "░".repeat(width - filled))
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
