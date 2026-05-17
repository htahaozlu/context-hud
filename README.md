# ContextBar

<p align="center">
  <img src="logo.png" alt="ContextBar logo" width="560">
</p>

<p align="center">
  English | <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <strong>Local-first repository context and native macOS usage visibility for coding agents.</strong>
</p>

<p align="center">
  ContextBar keeps agents grounded in the repository they are working on, writes stable agent-readable briefs, and gives Claude Code and Codex usage a native macOS surface.
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest/download/ContextBar.dmg">
    <img src="docs/images/download-macos-cta.svg" alt="Download app for macOS" width="300">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/downloads/htahaozlu/context-bar/total?style=flat-square&label=downloads" alt="Total Downloads">
  <img src="https://img.shields.io/github/stars/htahaozlu/context-bar?style=flat-square" alt="Stars">
</p>

<p align="center">
  <a href="https://github.com/htahaozlu/context-bar/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/htahaozlu/context-bar?style=flat-square&label=release&color=2F81F7">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-5DADE2">
  </a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-7DCEA0">
</p>

## Live demo

<p align="center">
  <img src="docs/images/context-bar-demo.gif" alt="ContextBar demo showing Claude Code and Codex usage updating live on macOS" width="100%">
</p>

ContextBar gives Claude Code and Codex a native macOS surface, so context drift and rolling usage stay visible while you work.

## Install

### Homebrew (recommended)

```bash
brew install --cask htahaozlu/context-bar/context-bar
```

`brew` auto-taps `htahaozlu/homebrew-context-bar` on first install. Upgrade later with `brew update && brew upgrade --cask htahaozlu/context-bar/context-bar`.

### macOS app (DMG)

1. Download `ContextBar.dmg` from the [latest release](https://github.com/htahaozlu/context-bar/releases/latest) (universal: Apple Silicon + Intel).
2. Drag `ContextBar.app` into `Applications`.
3. First launch: right-click `ContextBar.app` → **Open** → **Open** again. The app is ad-hoc signed (not notarized).
4. Eject and delete the DMG.

If macOS reports the app as "damaged", remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/ContextBar.app
```

### CLI

```bash
cargo install --path .
```

## Preview

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar native usage window" width="100%">
</p>

Native macOS usage window with rolling session visibility for Claude Code and Codex.

<p align="center">
  <img src="docs/images/context-bar-menubar.png" alt="ContextBar menubar" width="400">
</p>

Compact menubar status item showing active agent, project, and context usage. Clicking it opens a native popover with the active session, context window, rolling 5h/7d limits, parallel sessions, and a live theme picker.

## What it does

ContextBar solves two persistent problems in agent-driven development:

- repository context drifts faster than an agent brief can keep up
- usage and session state stay buried in terminal output and local transcripts

It addresses both through a local pipeline that continuously produces stable project summaries and a native macOS HUD for Claude Code and Codex activity.

### Core surfaces

- Repository snapshots under `.context-bar/`
- Stable `AGENT.md` and `CLAUDE.md`
- CLI for refresh, watch, and global views
- Native AppKit menubar companion
- Markdown and JSON artifacts for tooling

## Key capabilities

### Repository context generation

Each refresh writes agent-readable state into `.context-bar/`:

- `state.json`
- `brief-now.md`
- `brief-session.md`
- `brief-week.md`
- `AGENT.md`
- `hud.md`

For Claude Code compatibility, `CLAUDE.md` is mirrored at the repository root.

### CLI workflow

- `context-bar hud` refreshes the current repository and prints the HUD
- `context-bar snapshot` writes artifacts without printing the HUD
- `context-bar watch 30 .` keeps repository context fresh on an interval
- `context-bar global` builds a cross-project HUD under `~/.context-bar/`

### Native macOS companion

The companion app reads `~/.context-bar/hud.json` and provides:

- a compact menubar status item (active agent + project + context %)
- a modern AppKit popover with cards for the active agent, context window,
  rolling 5h/7d limits with progress bars, parallel sessions, and other
  detected AI tools
- a theme picker with inline color swatches and live preview — hover a
  theme and the menubar title repaints in that palette before you commit
- a full Settings window with Usage, Appearance, Menubar, and About tabs
- per-session context percentage for parallel Claude / Codex sessions

### Desktop & Notification Center widget

ContextBar ships with a native WidgetKit extension in three sizes —
`systemSmall`, `systemMedium`, and `systemLarge`. The widget reads the same
`hud.json` as the menubar via a shared App Group container
(`DQJT5BCZCM.com.htahaozlu.contextbar`), so it always reflects the active
agent, project, model, context %, rolling 5h/7d limits, and a per-agent
breakdown without any extra daemon.

<p align="center">
  <img src="docs/images/context-bar-screenshot.png" alt="ContextBar widget preview placeholder" width="100%">
</p>

To add it:

1. Install ContextBar 0.3.12 or later and launch it once so macOS indexes
   the extension (`pluginkit -m -v -i com.htahaozlu.contextbar.widget`
   should list it).
2. Open Notification Center (click the clock) → **Edit Widgets**, or
   right-click the desktop → **Edit Widgets**.
3. Search for **ContextBar**, then drop the small / medium / large variant
   wherever you want.

The widget extension is sandboxed and signed with the App Group entitlement,
which is required by `chronod` on macOS 14+ (the previous unsandboxed bundle
was silently rejected with `Ignoring restricted or unknown extension`).
The host menubar app mirrors `~/.context-bar/hud.json` into the App Group
container on every refresh so the sandboxed widget can read it.

### Share Today's HUD

The popover footer has a **Share** button (`square.and.arrow.up`) that
renders the current HUD as a PNG share card — active agent, model, context
%, 5h/7d usage, and other detected tools — masked by default so project
names are not leaked. The image is saved to a temporary path and opened in
Preview / a save dialog so you can drop it into Slack, X, or a status
thread without screenshotting and cropping.

<p align="center">
  <img src="docs/images/context-bar-screenshot-full.png" alt="ContextBar share card preview" width="100%">
</p>

Headless render (no UI) for automation:

```bash
CONTEXTBAR_SHARE_RENDER_PATH=/tmp/hud.png \
CONTEXTBAR_SHARE_MASK=1 \
/Applications/ContextBar.app/Contents/MacOS/context-bar
```

Set `CONTEXTBAR_SHARE_MASK=0` to keep real project names in the card.

If the menubar icon is hidden by overflow (Bartender, Hidden Bar, or a
crowded menubar), launching ContextBar again from Finder / Spotlight opens
the Settings window directly so you can still reach preferences.

The desktop UI is native AppKit (NSPopover + NSVisualEffectView, continuous
corner curves, SF Symbol toolbar). `detail.html` is an export artifact, not
the primary app experience.

## Usage

### Refresh the current repository

```bash
context-bar hud
```

### Write artifacts without printing the HUD

```bash
context-bar snapshot
```

### Keep repository context fresh

```bash
context-bar watch 30 .
```

### Generate the global HUD

```bash
context-bar global
context-bar watch-global 30
```

The global HUD is written to `~/.context-bar/hud.md`.

## Artifact layout

Each refresh writes the following files atomically:

- `.context-bar/state.json`
- `.context-bar/brief-now.md`
- `.context-bar/brief-session.md`
- `.context-bar/brief-week.md`
- `.context-bar/AGENT.md`
- `.context-bar/hud.md`
- `CLAUDE.md`

Atomic writes ensure agents do not observe partial state during refresh.

## Data sources

ContextBar combines:

- Git branch, recent commits, and worktree status
- file activity inferred from repository mtimes
- optional Claude Code statusline snapshot from `~/.context-bar/claude-statusline.json`
- Claude Code usage from `~/.claude/projects/**/*.jsonl`
- Codex CLI usage from `~/.codex/sessions/**/*.jsonl`

No external service is required for the core repository summaries. Usage aggregation relies on locally available transcripts, optional native Claude Code statusline data, and `python3`.

### Claude Code parity

For Claude context percentage, the best source is Claude Code's native statusline payload. ContextBar can persist that payload locally:

```json
{
  "statusLine": {
    "type": "command",
    "command": "context-bar claude-statusline"
  }
}
```

This writes `~/.context-bar/claude-statusline.json`, which ContextBar reads as the primary Claude context source. If the snapshot is missing or stale, ContextBar falls back to transcript-based estimation.

## Packaging

The repository includes scripts for the macOS companion build:

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

To include the WidgetKit extension in a direct app build:

```bash
WIDGET_BUILD=1 scripts/build-menubar-app.sh
```

`scripts/create-macos-dmg.sh` enables the widget build by default.

Artifacts:

- `dist/ContextBar.app`
- `dist/ContextBar.dmg`

## Repository layout

- `src/` core engine, artifact rendering, and usage aggregation
- `src/bin/context-bar.rs` standalone CLI entry point
- `menubar/context-bar.swift` macOS companion app
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
