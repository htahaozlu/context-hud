# ContextHUD

<p align="center">
  <img src="logo.png" alt="ContextHUD logo" width="560">
</p>

<p align="center">
  English | <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <strong>Local-first repository context and native macOS usage visibility for coding agents.</strong>
</p>

<p align="center">
  ContextHUD keeps agents grounded in the repository they are working on, writes stable agent-readable briefs, and gives Claude Code and Codex usage a native macOS surface.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-hud/releases/latest/download/ContextHUD.dmg">
    <img src="docs/images/download-macos-cta.svg" alt="Download app for macOS" width="300">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/downloads/htahaozlu/context-hud/total?style=flat-square&label=downloads" alt="Total Downloads">
  <img src="https://img.shields.io/github/stars/htahaozlu/context-hud?style=flat-square" alt="Stars">
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-hud/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/badge/release-v0.1.4-2F81F7">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-5DADE2">
  </a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-7DCEA0">
</p>

## Install

### Homebrew (recommended)

```bash
brew install --cask htahaozlu/context-hud/context-hud
```

`brew` auto-taps `htahaozlu/homebrew-context-hud` on first install. Upgrade later with `brew upgrade --cask context-hud`.

### macOS app (DMG)

1. Download `ContextHUD.dmg` from the [latest release](https://github.com/htahaozlu/context-hud/releases/latest) (universal: Apple Silicon + Intel).
2. Drag `ContextHUD.app` into `Applications`.
3. First launch: right-click `ContextHUD.app` → **Open** → **Open** again. The app is ad-hoc signed (not notarized).
4. Eject and delete the DMG.

If macOS reports the app as "damaged", remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/ContextHUD.app
```

### CLI

```bash
cargo install --path .
```

## Preview

<p align="center">
  <img src="docs/images/context-hud-screenshot.png" alt="ContextHUD native usage window" width="100%">
</p>

Native macOS usage window with rolling session visibility for Claude Code and Codex.

<p align="center">
  <img src="docs/images/context-hud-menubar.png" alt="ContextHUD menubar" width="400">
</p>

Compact menubar status item showing active agent, project, and context usage.

## What it does

ContextHUD solves two persistent problems in agent-driven development:

- repository context drifts faster than an agent brief can keep up
- usage and session state stay buried in terminal output and local transcripts

It addresses both through a local pipeline that continuously produces stable project summaries and a native macOS HUD for Claude Code and Codex activity.

### Core surfaces

- Repository snapshots under `.context-hud/`
- Stable `AGENT.md` and `CLAUDE.md`
- CLI for refresh, watch, and global views
- Native AppKit menubar companion
- Markdown and JSON artifacts for tooling

## Key capabilities

### Repository context generation

Each refresh writes agent-readable state into `.context-hud/`:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

For Claude Code compatibility, `CLAUDE.md` is mirrored at the repository root.

### CLI workflow

- `context-hud hud` refreshes the current repository and prints the HUD
- `context-hud snapshot` writes artifacts without printing the HUD
- `context-hud watch 30 .` keeps repository context fresh on an interval
- `context-hud global` builds a cross-project HUD under `~/.context-hud/`

### Native macOS companion

The companion app reads `~/.context-hud/hud.json` and provides:

- a compact menubar status view
- a native usage window for Claude Code and Codex
- settings for theme, language, and menubar title composition

The desktop UI is native AppKit. `detail.html` is an export artifact, not the primary app experience.

## Usage

### Refresh the current repository

```bash
context-hud hud
```

### Write artifacts without printing the HUD

```bash
context-hud snapshot
```

### Keep repository context fresh

```bash
context-hud watch 30 .
```

### Generate the global HUD

```bash
context-hud global
context-hud watch-global 30
```

The global HUD is written to `~/.context-hud/hud.md`.

## Artifact layout

Each refresh writes the following files atomically:

- `.context-hud/state.json`
- `.context-hud/brief-now.md`
- `.context-hud/brief-session.md`
- `.context-hud/brief-week.md`
- `.context-hud/AGENT.md`
- `.context-hud/hud.md`
- `CLAUDE.md`

Atomic writes ensure agents do not observe partial state during refresh.

## Data sources

ContextHUD combines:

- Git branch, recent commits, and worktree status
- file activity inferred from repository mtimes
- Claude Code usage from `~/.claude/projects/**/*.jsonl`
- Codex CLI usage from `~/.codex/sessions/**/*.jsonl`

No external service is required for the core repository summaries. Usage aggregation relies on locally available transcript data and `python3`.

## Packaging

The repository includes scripts for the macOS companion build:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

Artifacts:

- `dist/ContextHUD.app`
- `dist/ContextHUD.dmg`

## Repository layout

- `src/` core engine, artifact rendering, and usage aggregation
- `src/bin/context-hud.rs` standalone CLI entry point
- `menubar/context-hud.swift` macOS companion app
- `examples/snapshot.rs` native development harness

## Development

```bash
cargo check
cargo run --example snapshot
```

## Community

- Questions and usage help: GitHub Discussions
- Bugs and feature requests: GitHub Issues
- Contribution guide: `CONTRIBUTING.md`
- Security reporting: `SECURITY.md`

## License

Apache-2.0
