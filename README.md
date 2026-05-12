# ContextHUD

<p align="left">
  <a href="https://github.com/htahaozlu/context-hud/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/htahaozlu/context-hud?display_name=tag&label=version">
  </a>
  <a href="https://github.com/htahaozlu/context-hud/releases/latest/download/ContextHUD.dmg">
    <img alt="Download for macOS" src="https://img.shields.io/badge/Download-macOS%20DMG-black?logo=apple">
  </a>
</p>

ContextHUD keeps local coding agents grounded in the repository they are working on and gives you a native macOS view into Claude Code and Codex usage. It started as a Zed extension experiment, but the product is now broader: a reusable context engine, a CLI, agent-readable artifacts, and a menubar companion app.

## Why it exists

Modern agent workflows lose state in two places:

- the repository changes faster than the agent brief
- token/session usage lives in terminal output and scattered local transcripts

ContextHUD fixes both with a local-first pipeline:

- repository context is refreshed into stable files under `.context-hud/`
- agents can read the same concise brief every time through `AGENT.md` or `CLAUDE.md`
- Claude Code and Codex usage is summarized into a native macOS window and a compact menubar HUD

## Highlights

- Local-first. No hosted service is required for repository summaries.
- Persistent agent brief. Writes a stable `AGENT.md` plus `CLAUDE.md` compatibility output.
- Useful time windows. Tracks `now`, `session`, and `week` repository views.
- Native macOS companion. Menubar HUD plus a native AppKit usage window for Claude and Codex.
- Structured artifacts. Emits both markdown and JSON so other tools can consume the same state.

## Download for macOS

1. Open the latest release from the button above.
2. Download `ContextHUD.dmg`.
3. Drag `ContextHUD.app` into `Applications`.
4. Launch the app once from `Applications`.
5. Eject and delete the DMG. It is not needed after installation.

## Product surfaces

### Repository context

Each refresh writes agent-readable project state under `.context-hud/`:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

`CLAUDE.md` is mirrored at the repository root for Claude Code compatibility.

### CLI

The CLI is the reliable always-on surface today:

- `context-hud hud` refreshes the current repository and prints the HUD
- `context-hud snapshot` writes artifacts without printing the HUD
- `context-hud watch 30 .` keeps a repository fresh on an interval
- `context-hud global` builds a cross-project HUD under `~/.context-hud/`

### Native macOS app

The companion app reads `~/.context-hud/hud.json` and shows:

- a compact menubar status view
- a native usage window for Claude and Codex
- settings for theme, language, and menubar title composition

The primary desktop UI is native AppKit. `detail.html` is only a standalone export artifact, not the main app experience.

## Installation

### CLI

```bash
cargo install --path .
```

### Zed dev extension

1. Open the Extensions view in Zed.
2. Choose `Install Dev Extension`.
3. Select this repository.
4. If needed, grant `process:exec` under `granted_extension_capabilities`.

## Usage

### Refresh the current repository

```bash
context-hud hud
```

### Write all artifacts without printing the HUD

```bash
context-hud snapshot
```

### Keep repository artifacts fresh

```bash
context-hud watch 30 .
```

### Generate the global HUD

```bash
context-hud global
context-hud watch-global 30
```

The global HUD is written to `~/.context-hud/hud.md`. Pin that file in Zed if you want a persistent cross-project tab.

## Artifact layout

Each refresh writes the following files:

- `.context-hud/state.json`
- `.context-hud/brief-now.md`
- `.context-hud/brief-session.md`
- `.context-hud/brief-week.md`
- `.context-hud/AGENT.md`
- `.context-hud/hud.md`
- `CLAUDE.md`

Writes are atomic, so agents do not observe partial files mid-refresh.

## macOS app and DMG

The repository includes packaging scripts for the optional companion app:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

This produces:

- `dist/ContextHUD.app`
- `dist/ContextHUD.dmg`

The DMG includes a short install note that tells users to drag the app into `Applications`, launch it once, then eject and delete the DMG.

## How the data is collected

ContextHUD combines:

- Git branch, recent commits, and worktree status
- File activity inferred from repository mtimes
- Claude Code usage from `~/.claude/projects/**/*.jsonl`
- Codex CLI usage from `~/.codex/sessions/**/*.jsonl`

No external service is required for the core repository summaries. Usage aggregation relies on locally available transcript data and `python3`.

## Current constraints

- Zed `extension_api` `0.7` does not expose a load-time worktree hook.
- Zed does not yet expose a persistent HUD primitive for extensions.
- Agent auto-injection is file-based today; agents read `.context-hud/AGENT.md` or `CLAUDE.md`.

Because of those limits, the CLI is the most reliable always-on surface today.

## Repository layout

- `src/` core engine, artifact rendering, Zed integration, and usage aggregation
- `src/bin/context-hud.rs` standalone CLI entry point
- `menubar/context-hud.swift` optional macOS companion app
- `examples/snapshot.rs` native development harness

## Development

```bash
cargo check
cargo run --example snapshot
```

## License

Apache-2.0
