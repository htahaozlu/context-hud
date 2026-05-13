# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, adapted for the current release workflow.

## [0.1.9] - 2026-05-13

### Changed

- Brand icons now use dedicated agent CLI marks (Claude Code, Codex, Copilot, Gemini, DeepSeek, Qwen, MiniMax) instead of generic provider logos.

### Removed

- Dropped Ollama from the supported agent icon set and shell-history probe.

### Added

- Shell-history detection for DeepSeek, Qwen, and MiniMax CLIs.

## [0.1.8] - 2026-05-13

### Added

- Menubar app now ships bundled brand assets for supported agents, including Anthropic/Claude, OpenAI/Codex, Google Gemini, GitHub Copilot, and Ollama.

### Improved

- Settings preview, menubar title, dropdown rows, and native usage panel now render supported agents with their actual icons instead of plain names or placeholder glyphs.
- Menubar app packaging now copies bundled brand icon assets into `ContextHUD.app/Contents/Resources/brands` for release builds.

## [0.1.7] - 2026-05-13

### Fixed

- Local app builds under `dist/ContextHUD.app` now sync `CFBundleShortVersionString` and `CFBundleVersion` from the repository version instead of incorrectly showing the template `0.1.0 (1)`.

## [0.1.6] - 2026-05-13

### Improved

- In-app update flow now downloads the DMG in the background, stages the new app bundle, and prompts the user with a native "Restart to Update" action instead of sending them to GitHub or Downloads.
- Update UI now behaves like a first-party desktop app: progress is shown inline, release notes remain optional, and the primary path is a single update-confirm-restart flow.

## [0.1.5] - 2026-05-13

### Added

- `context-hud claude-statusline`, a Claude Code statusline sink that persists native context-window snapshots under `~/.context-hud/claude-statusline.json`.

### Improved

- Claude context percentage now prefers Claude Code's native `context_window.used_percentage` when available, which brings the HUD into parity with Claude Code statusline surfaces.
- Transcript fallback now recognizes 1M-context Claude models such as Sonnet 4.6 and Opus 4.6/4.7 instead of incorrectly forcing them into a 200k window.
- Turkish localization strings in the native macOS app now render proper characters in Settings and About surfaces.

## [0.1.4] - 2026-05-13

### Added

- In-app update check via GitHub Releases API with download/release-notes/later actions.
- Live menubar title preview in Settings → Menubar.
- Drag-and-drop reordering for title fields with explicit ⠿ handle and per-field show checkbox.

### Improved

- Apple-style Preferences UI: borderless grouped sections, sentence-case titles, right-aligned info values.
- About hero redesigned: 360×120 horizontal logo, centered app name, version, and description.
- Usage panel header now shows agent name (Claude vs Codex), model, and project explicitly.
- Replaced misleading "1.2M of 258.4k" context subtitle with model window size only.
- Removed redundant ContextHUD header block at the top of the menubar dropdown.
- README restructured: install section moved to the top; Zed extension references removed.

## [0.1.3] - 2026-05-13

### Added

- Homebrew Cask (`Casks/context-hud.rb`) and release-workflow automation that bumps version + sha256 on every tag.

### Improved

- Menubar dropdown header no longer shows the version line; version remains in Settings → About.
- Reset timers render `6d 3h` (or `6g 3sa` in Turkish) instead of `149h` for spans ≥ 24h.

## [0.1.0] - 2026-05-12

Initial ContextHUD release.

### Added

- Local-first repository context generation under `.context-hud/`
- Stable agent-facing outputs including `AGENT.md`, `CLAUDE.md`, and rolling markdown briefs
- CLI commands for `hud`, `snapshot`, `watch`, `global`, and `watch-global`
- Native macOS menubar companion app built with AppKit
- Native usage window for Claude Code and Codex with compact stats and rolling usage views
- Markdown and JSON artifacts for both human and tool consumption
- DMG packaging scripts for the macOS app
- GitHub Actions release workflow for tagged builds

### Improved

- Product naming and repository presentation aligned under `ContextHUD`
- README upgraded to a more product-oriented structure
- GitHub repository metadata updated for release distribution

### Notes

- The macOS companion app is optional; the CLI is the most reliable always-on surface today.
- Repository summaries are local-first and do not require a hosted backend.
