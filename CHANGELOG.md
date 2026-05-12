# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, adapted for the current release workflow.

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

