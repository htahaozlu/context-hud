use std::path::PathBuf;

use zed_extension_api::{self as zed, Result};

use crate::{context_engine::ContextEngine, hud, state_writer};

pub fn run(
    command: zed::SlashCommand,
    worktree: Option<&zed::Worktree>,
) -> Result<zed::SlashCommandOutput> {
    match command.name.as_str() {
        "hello" => run_hello(worktree),
        "brief" => run_brief(worktree),
        "hud" => run_hud(worktree),
        "doctor" => run_doctor(worktree),
        _ => Err(format!("unknown slash command: {}", command.name)),
    }
}

fn run_hello(worktree: Option<&zed::Worktree>) -> Result<zed::SlashCommandOutput> {
    let text = match worktree {
        Some(worktree) => {
            let root = worktree.root_path();
            format!(
                "Worktree `{root}` is connected. Context engine is available through `/brief`."
            )
        }
        None => "No worktree is attached. Run `/hello` inside a project.".to_string(),
    };

    Ok(zed::SlashCommandOutput {
        text,
        sections: vec![],
    })
}

fn run_brief(worktree: Option<&zed::Worktree>) -> Result<zed::SlashCommandOutput> {
    let worktree = worktree.ok_or_else(|| {
        "No worktree is attached. Run `/brief` inside a project-backed assistant thread."
            .to_string()
    })?;

    let snapshot = ContextEngine::generate(worktree)?;
    let root = PathBuf::from(worktree.root_path());

    let write_note = match state_writer::write(&root, &snapshot) {
        Ok(paths) => format!(
            "Artifacts updated under `{}` (`{}`, `{}`, `{}`, `{}`, `{}`). \
             Agents can read `AGENT.md` directly.",
            root.join(".context-hud").display(),
            paths.state_path.display(),
            paths.now_brief_path.display(),
            paths.session_brief_path.display(),
            paths.week_brief_path.display(),
            paths.agent_brief_path.display()
        ),
        Err(error) => format!(
            "Artifact write skipped: {error}. This prototype assumes Zed's extension runtime can write into the worktree, which is not verified yet."
        ),
    };

    let text = format!(
        concat!(
            "## ContextHUD Brief\n\n",
            "- Branch: `{}`\n",
            "- Updated: `{}`\n",
            "- {}\n\n",
            "### Now\n",
            "{}\n\n",
            "Top files: {}\n\n",
            "### Session\n",
            "{}\n\n",
            "Focus areas: {}\n\n",
            "### Week\n",
            "{}\n\n",
            "Themes: {}\n\n",
            "### Assistant Memory\n",
            "{}\n"
        ),
        snapshot.branch,
        snapshot.updated_at,
        write_note,
        snapshot.now.resume_hint,
        format_list(&snapshot.now.top_files),
        snapshot.session.resume_hint,
        format_list(&snapshot.session.focus_areas),
        snapshot.week.resume_hint,
        format_list(&snapshot.week.themes),
        snapshot.assistant_memory.latest_summary
    );

    Ok(zed::SlashCommandOutput {
        text,
        sections: vec![],
    })
}

fn run_hud(worktree: Option<&zed::Worktree>) -> Result<zed::SlashCommandOutput> {
    let worktree = worktree.ok_or_else(|| {
        "No worktree is attached. Run `/hud` inside a project-backed assistant thread.".to_string()
    })?;

    let snapshot = ContextEngine::generate(worktree)?;
    let root = PathBuf::from(worktree.root_path());

    let footer = match state_writer::write(&root, &snapshot) {
        Ok(paths) => format!(
            "\n_HUD persisted to `{}` (auto-refreshes on every extension interaction)._\n",
            paths.hud_path.display()
        ),
        Err(error) => format!("\n_HUD write skipped: {error}._\n"),
    };

    let text = format!("{}{}", hud::render(&snapshot, &snapshot.usage), footer);

    Ok(zed::SlashCommandOutput {
        text,
        sections: vec![],
    })
}

fn run_doctor(worktree: Option<&zed::Worktree>) -> Result<zed::SlashCommandOutput> {
    let Some(worktree) = worktree else {
        return Ok(zed::SlashCommandOutput {
            text: concat!(
                "## ContextHUD Doctor\n\n",
                "- worktree: missing\n",
                "- git binary: unknown\n",
                "- process exec: unknown\n",
                "- state write: unknown\n\n",
                "Run `/doctor` inside a project-backed assistant thread.\n"
            )
            .to_string(),
            sections: vec![],
        });
    };

    let root = PathBuf::from(worktree.root_path());
    let git_binary = worktree.which("git");
    let git_binary_line = match &git_binary {
        Some(path) => format!("- git binary: ok (`{path}`)"),
        None => "- git binary: missing from worktree PATH".to_string(),
    };

    let snapshot_result = ContextEngine::generate(worktree);
    let process_exec_line = match &snapshot_result {
        Ok(snapshot) => format!("- process exec: ok (branch `{}`)", snapshot.branch),
        Err(error) => format!("- process exec: failed ({error})"),
    };

    let state_write_line = match &snapshot_result {
        Ok(snapshot) => match state_writer::write(&root, snapshot) {
            Ok(paths) => format!("- state write: ok (`{}`)", paths.state_path.display()),
            Err(error) => format!("- state write: failed ({error})"),
        },
        Err(_) => "- state write: skipped because snapshot generation failed".to_string(),
    };

    let next_step = if snapshot_result.is_ok() {
        "Runtime basics look healthy. Next step: run `/brief` and inspect `.context-hud/` artifacts."
    } else {
        "If `process exec` failed, check Zed's `granted_extension_capabilities` for `process:exec` and review `Zed.log`."
    };

    let text = format!(
        concat!(
            "## ContextHUD Doctor\n\n",
            "- worktree: ok (`{}`)\n",
            "{}\n",
            "{}\n",
            "{}\n\n",
            "{}\n"
        ),
        root.display(),
        git_binary_line,
        process_exec_line,
        state_write_line,
        next_step
    );

    Ok(zed::SlashCommandOutput {
        text,
        sections: vec![],
    })
}

fn format_list(items: &[String]) -> String {
    if items.is_empty() {
        "none".to_string()
    } else {
        items.join(", ")
    }
}
