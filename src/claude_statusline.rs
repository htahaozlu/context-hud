use serde::{Deserialize, Serialize};
use std::io::Read;
use std::path::PathBuf;

const DEFAULT_RELATIVE_PATH: &str = ".context-hud/claude-statusline.json";

#[derive(Debug, Deserialize)]
struct StatuslineInput {
    #[serde(default)]
    model: ModelInfo,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    workspace: WorkspaceInfo,
    #[serde(default)]
    context_window: ContextWindowInfo,
    #[serde(default)]
    rate_limits: serde_json::Value,
}

#[derive(Debug, Default, Deserialize)]
struct ModelInfo {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    display_name: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct WorkspaceInfo {
    #[serde(default)]
    current_dir: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct ContextWindowInfo {
    #[serde(default)]
    used_percentage: Option<f64>,
    #[serde(default)]
    context_window_size: Option<u64>,
    #[serde(default)]
    total_input_tokens: Option<u64>,
    #[serde(default)]
    total_output_tokens: Option<u64>,
    #[serde(default)]
    current_usage: CurrentUsage,
}

#[derive(Debug, Default, Deserialize, Serialize)]
struct CurrentUsage {
    #[serde(default)]
    input_tokens: Option<u64>,
    #[serde(default)]
    output_tokens: Option<u64>,
    #[serde(default)]
    cache_creation_input_tokens: Option<u64>,
    #[serde(default)]
    cache_read_input_tokens: Option<u64>,
}

#[derive(Debug, Serialize)]
struct StatuslineSnapshot {
    updated_at: String,
    model: SnapshotModel,
    cwd: Option<String>,
    workspace: SnapshotWorkspace,
    context_window: SnapshotContextWindow,
    #[serde(skip_serializing_if = "serde_json::Value::is_null")]
    rate_limits: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct SnapshotModel {
    id: Option<String>,
    display_name: Option<String>,
}

#[derive(Debug, Serialize)]
struct SnapshotWorkspace {
    current_dir: Option<String>,
}

#[derive(Debug, Serialize)]
struct SnapshotContextWindow {
    #[serde(skip_serializing_if = "Option::is_none")]
    used_percentage: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    context_window_size: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    total_input_tokens: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    total_output_tokens: Option<u64>,
    current_usage: CurrentUsage,
}

pub fn default_snapshot_path() -> PathBuf {
    if let Ok(override_path) = std::env::var("CONTEXTHUD_CLAUDE_STATUSLINE_PATH") {
        return PathBuf::from(override_path);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(DEFAULT_RELATIVE_PATH)
}

pub fn write_snapshot_from_stdin(path: Option<PathBuf>) -> Result<String, String> {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .map_err(|error| format!("read stdin failed: {error}"))?;

    let parsed: StatuslineInput = serde_json::from_str(&input)
        .map_err(|error| format!("parse statusline JSON failed: {error}"))?;

    let now = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "unknown".to_string());

    let line = render_statusline(&parsed);
    let cwd = parsed.workspace.current_dir.clone().or(parsed.cwd.clone());
    let snapshot = StatuslineSnapshot {
        updated_at: now,
        model: SnapshotModel {
            id: parsed.model.id.clone(),
            display_name: parsed.model.display_name.clone(),
        },
        cwd,
        workspace: SnapshotWorkspace {
            current_dir: parsed.workspace.current_dir.clone(),
        },
        context_window: SnapshotContextWindow {
            used_percentage: parsed.context_window.used_percentage,
            context_window_size: parsed.context_window.context_window_size,
            total_input_tokens: parsed.context_window.total_input_tokens,
            total_output_tokens: parsed.context_window.total_output_tokens,
            current_usage: parsed.context_window.current_usage,
        },
        rate_limits: parsed.rate_limits,
    };

    let output_path = path.unwrap_or_else(default_snapshot_path);
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("mkdir {} failed: {error}", parent.display()))?;
    }
    let body = serde_json::to_vec_pretty(&snapshot)
        .map_err(|error| format!("serialize statusline snapshot failed: {error}"))?;
    crate::state_writer::atomic_write(&output_path, &body)?;

    Ok(line)
}

fn render_statusline(input: &StatuslineInput) -> String {
    let model = input
        .model
        .display_name
        .as_deref()
        .or(input.model.id.as_deref())
        .unwrap_or("Claude");
    let pct = input.context_window.used_percentage.unwrap_or(0.0);
    format!("[{model}] {pct:.0}% ctx")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_compact_statusline() {
        let parsed = StatuslineInput {
            model: ModelInfo {
                id: Some("claude-sonnet-4-6".to_string()),
                display_name: Some("Sonnet 4.6".to_string()),
            },
            cwd: None,
            workspace: WorkspaceInfo {
                current_dir: Some("/tmp/demo".to_string()),
            },
            context_window: ContextWindowInfo {
                used_percentage: Some(6.2),
                ..Default::default()
            },
            rate_limits: serde_json::Value::Null,
        };
        assert_eq!(render_statusline(&parsed), "[Sonnet 4.6] 6% ctx");
    }

    #[test]
    fn default_path_uses_home() {
        let path = default_snapshot_path();
        assert!(path.ends_with(".context-hud/claude-statusline.json"));
    }
}
