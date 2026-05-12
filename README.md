# ContextHUD

<p align="left">
  <a href="https://github.com/htahaozlu/context-hud/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/htahaozlu/context-hud?display_name=tag&label=version">
  </a>
  <a href="https://github.com/htahaozlu/context-hud/releases/latest/download/ContextHUD.dmg">
    <img alt="Download for macOS" src="https://img.shields.io/badge/Download-macOS%20DMG-black?logo=apple">
  </a>
</p>

ContextHUD generates persistent repository context for coding agents and exposes a lightweight usage HUD for Claude Code and Codex CLI. It started as a Zed extension experiment, but the current product surface is broader: a reusable context engine, a CLI, agent-readable artifacts, and an optional macOS companion app.

## Download for macOS

1. Open the latest release from the button above.
2. Download `ContextHUD.dmg`.
3. Drag `ContextHUD.app` into `Applications`.
4. Launch the app once from `Applications`.
5. Eject and delete the DMG. It is not needed after installation.

## What it does

- Writes project artifacts under `.context-hud/`
- Produces a stable `AGENT.md` brief for local coding agents
- Mirrors the same brief to `CLAUDE.md` for Claude Code compatibility
- Summarizes repository activity across `now`, `session`, and `week` windows
- Builds a usage HUD from local Claude Code and Codex CLI transcripts
- Works through both a Zed extension surface and a standalone CLI

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
