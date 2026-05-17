# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, adapted for the current release workflow.

## [0.3.12] - 2026-05-17

### Fixed

- Widget extension now passes `chronod` enrolment on macOS 14+ (including macOS 26 Tahoe), which silently rejected the previous unsandboxed bundle. The `appex` now ships with `com.apple.security.app-sandbox=true` and the `DQJT5BCZCM.com.htahaozlu.contextbar` App Group entitlement, so users can add ContextBar from the system widget gallery without manual intervention.
- The host menubar app mirrors `~/.context-bar/hud.json` into the shared App Group container on launch and after every engine run, so the sandboxed widget can read the snapshot it could not access via `NSHomeDirectory()` before.

## [0.3.11] - 2026-05-17

### Added

- WidgetKit packaging now uses a checked-in Xcode subproject and `xcodebuild` when `WIDGET_BUILD=1`, producing and embedding `ContextBarWidget.appex` under `Contents/PlugIns` instead of the previous raw-`swiftc` bundle.
- DMG packaging enables the widget build by default so installed release artifacts expose ContextBar in the system widget gallery after first launch.

### Fixed

- Codex limit refresh now reads the live Codex app-server `account/rateLimits/read` state instead of relying only on the last transcript `rate_limits` event, so the 5h/7d HUD updates without waiting for a new Codex turn.
- Codex limit rows now display remaining quota text to match the official Codex balance wording, while preserving usage-based progress bars and threshold colors. Claude limit display is unchanged.

## [0.3.10] - 2026-05-17

### Fixed

- Dark-mode readability in menubar/popup surfaces now uses dynamic text colors for attributed strings and theme presets that previously could render too dark.
- The Parallel Sessions card is now hidden unless there is at least one actual background session after foreground-session filtering, preventing an empty card from appearing.
- Homebrew migration polish for the ContextBar rename: local docs use the fully qualified tap upgrade command, the cask follows current Homebrew style, and release tap sync now fails with a clearer token-permission error.
- Removed the remaining tracked `context-hud` ignore entry after the project rename.

## [0.3.9] - 2026-05-17

### Fixed

- Active-session context % no longer lags during a live conversation. The Rust snapshot cache now invalidates whenever any `~/.claude/projects/**/*.jsonl` or `~/.codex/sessions/**/*.jsonl` has been written since the cache file's mtime, so mid-stream assistant turns reach `hud.json` without the prior 300 s TTL gating fresh data.

### Changed

- Popover refresh button is now a full re-aggregate: deletes both `~/.context-bar/usage.cache.json` and `~/.context-bar/usage_api_cache.json`, then re-runs the engine. Double-clicks within 2 s are coalesced. Icon spins while the engine is running; settles automatically on the next rebuild.

## [0.3.8] - 2026-05-17

### Added

- Burn-rate forecast line in the hero card: when context usage trends predictively, shows "↗ on pace to fill in 1h 47m · window resets in 3h 12m" using a linear extrapolation from session start with a confidence gate (≥120s elapsed, non-zero rate).
- Upstream incident overlay: polls Anthropic and OpenAI status pages every 5 minutes; lights a colored dot in the menubar title and adds a clickable incident strip to the popover hero.
- Critical-background-session menubar indicator: when the foreground session is calm (<50%) and a parallel session exceeds 80%, appends a "⚠ <project> 88%" chip to the menubar title.
- Reset-time style toggle (Settings → Display): switch every reset countdown between relative ("in 1h 47m") and absolute clock time ("14:32").
- Threshold tick marks on context bars at 70% / 90%, toggleable from Settings → Display.
- Loading stripe placeholder for the popover hero card while the engine is producing the first `hud.json` — replaces the misleading "no agent data yet" empty state on first launch.
- Confetti burst on quota window resets (5h / 7d), gated per-agent and per-window so a single rollover only celebrates once. Respects reduce-motion.
- `PersonalInfoRedactor` (Settings → Privacy): masks `$HOME`, `/Users/<name>/...`, and email addresses in any text exported through the app. Off by default, live preview in the privacy pane.
- Settings panes split: new Display, Alerts, and Privacy tabs in the detail window.

### Changed

- Status item hardened against display reconfigure and wake-from-sleep: listens to `didChangeScreenParametersNotification` and `NSWorkspace.didWakeNotification`, recreates the `NSStatusItem` when its button window goes nil.
- Engine reentrancy: 10 s timer, FSEvents bursts, wake-from-sleep refresh, and manual refresh now coalesce through `engineRunning` / `enginePending` flags so overlapping engine processes can no longer race.
- FSEvents watcher rescans every tick — `~/.claude/projects` or `~/.codex/sessions` materializing after launch is now picked up without restart.
- `LoadingStripeView` CVDisplayLink callback throttled to ~30 fps to keep the main queue clean while the placeholder is on screen.
- Defensive JSON parsing in `Hud.parse()` — `u64` / `u64Opt` / `dbl` helpers handle integer-vs-double percentages and very large token counts that `JSONSerialization` returns as `Double`.
- Rust `AgentUsage` struct now mirrors every field emitted by the Python ingest (`cache_read_tokens_*`, `ActiveSession.context_pct`, `context_window`, `last_input_tokens`) so per-session fields stop silently dropping on the menubar side.

### Fixed

- Celebration cross-agent key collision: Claude and Codex hitting the same window boundary inside 60 s no longer suppress each other's confetti.
- Turkish strings: missing diacritics on the Appearance pane subtitle and the empty "X running" suffix in the popover meta row.
- Menubar "no agent" fallback text now uses `menuBarFont` instead of the system default.
- Footer icon buttons in the popover now expose VoiceOver labels.

## [0.3.7] - 2026-05-16

### Changed

- WidgetKit extension is no longer built by default. Source remains in `menubar/widget/Widget.swift` and the appex is wired into the build script behind `WIDGET_BUILD=1`, but `.appex` bundles produced by raw `swiftc` are silently refused by pluginkit even when Info.plist, embedded `__TEXT,__info_plist`, codesign, and notarization all match a working reference widget. The proper hand-off needs an Xcode subproject driven via `xcodebuild` so WidgetKit's hidden build-system requirements (auto-injected Swift stdlib, entitlements, plist embedding) are honored; tracked as the next milestone for the macOS companion.
- README + README.tr updated to reflect the widget status accurately.

## [0.3.6] - 2026-05-16

### Added

- WidgetKit extension (`ContextBarWidget.appex`) bundled under `Contents/PlugIns`. Three sizes (small / medium / large) showing the active agent, project, context ring, and rolling 5h/7d limit bars. Reads the same `~/.context-bar/hud.json` snapshot as the menubar; the menubar app calls `WidgetCenter.shared.reloadAllTimelines()` on every regeneration so the widget never lags behind the 60s timeline floor.
- Finder / Spotlight relaunch fallback: `applicationShouldHandleReopen` + `application(_:open:)` open the Settings window when the menubar icon is hidden by overflow / Bartender / Hidden Bar, and toggle the popover otherwise. New `--settings` / `--open` CLI args trigger the detail window on first launch.

### Fixed

- Menubar title now reflects the most recently active project across parallel Claude / Codex sessions even when the popover and detail window are both closed. The 10s tick used to skip regeneration when nothing was visible, leaving the title stuck on the previous project.
- Native popover / detail capture switched from the `screencapture` CLI to `CGWindowListCreateImage`. The CLI silently failed (`could not create image from window`) on freshly-signed builds and on launches inheriting a shell without Screen Recording TCC consent; capturing own-process windows via Core Graphics requires no permission and works headlessly.

## [0.3.5] - 2026-05-16

### Fixed

- Hero card vertical alignment: dot, project name, and pct now sit on the same optical line. Dot is drawn as an inline "●" glyph inside the project label's attributed string (same font, same baseline) instead of a separate `ActivityDotView` that needed cap-height / x-height Auto Layout math. Project and pct labels use the IDENTICAL font (system 22pt semibold) — previously pct used `monospacedDigitSystemFont` which has different cap/x-height metrics than `systemFont` at the same point size, so even baseline-aligned the two text rows looked off.
- Brand icon moved from the title row to the meta row prefix (next to "Claude · model · …"). Title row now only contains the dot+project+pct trio, so vertical centering has fewer competing baselines.
- Menubar status item agent icon: switched to cap-height-sized image with zero baseline offset so the inline icon sits at the same vertical band as the surrounding text glyphs.

### Changed

- Popover card order: hero (active session) → parallel sessions → per-agent limits (each with brand icon header) → other tools → footer. Limits are now shown for every agent with data, so Codex's 5h/7d numbers are visible while Claude is the foreground hero (and vice-versa).
- Removed the standalone "Claude limits" card; both Claude and Codex now share the same `buildAgentLimits()` layout with an icon + name + last-turn header.

## [0.3.4] - 2026-05-16

### Fixed

- Stats `total tokens` aligned with Claude's `/usage` "Total tokens" display. Previous formula summed `fresh_in + cache_create + outp` which inflated the all-time number ~2.6× over what users see in their Anthropic UI (e.g. 415M vs ~160M). New formula: `total = fresh_in + outp`. `cache_read_tokens_*` and per-bucket `cache_read` still emitted separately so a future cost view can multiply by the 0.1× rate.
- Hero context meter and detail line now always render even when `last_context_pct` / `last_context_window` is unknown (bar shows 0, detail shows "context unknown" or session-tokens-only). Previously the entire context row disappeared so users thought the feature broke.
- Popover footer "Theme" caption pinned single-line with the popup absorbing the squeeze — fixes the "Them\nE" two-line wrap. Footer container insets symmetric (leading/trailing 0, vertical 8pt) and outer stack bottom inset reduced to 8pt so the gap below the footer matches the side rhythm.

### Added

- Stats pane: Claude / Codex provider segmented control. Each provider scanned from its own transcripts.
- `max_session_minutes` field on each `AgentUsage` block — longest single session across the whole scanned history, no longer capped to the 20-row `recent_sessions` tail. Surfaced as the "longest session" tile in stats.

## [0.3.3] - 2026-05-16

### Fixed

- Popover no longer flickers on the 10s refresh when active sessions change. `rebuild()` now fingerprints every rendered field (agent, active sessions, tools, theme, language) and bails early when the snapshot is byte-identical to the last render. When data does change, the rebuild is wrapped in `CATransaction.setDisableActions(true)` to suppress implicit sublayer animations.
- Card content edges (leading/trailing) bumped from 12pt to 16pt so all four sides match — removes the top/right whitespace asymmetry users reported.

### Added

- New "Parallel sessions" card in the popover. Shows each concurrent Claude Code session with project name, model, last-turn relative time, and a 4pt capsule context bar with percent text. Foreground session is filtered out by `cwd` match; card hides entirely when only one session is active; capped at 5 rows with a "+N more" overflow line.

## [0.3.2] - 2026-05-16

### Fixed

- Claude context-window detection: Claude Code ships Opus 4.6/4.7, Sonnet 4.5/4.6/4.7 and Mythos as the 1M-context variant by default, but the transcript JSONL records the model id without the `[1m]` suffix. v0.3.0 had stripped these defaults, so users on the 1M variant saw their context percentage jump 5× (e.g. 12% → 60%). Restored the family-level defaults; Haiku stays at 200K; the `[1m]`/`-1m` tag and the recorded `context-1m-*` beta header still force 1M; observed turn-token max above 200K snaps to 1M adaptively. Env override `CONTEXTBAR_CONTEXT_WINDOW` honored.

## [0.3.1] - 2026-05-16

### Fixed

- Stats totals reverted to the ccusage fresh-work view (`input + cache_create + output`, plus thinking tokens). v0.3.0's billed-tokens formula multiplied `cache_read` across every turn — a 100-turn session re-reading a 100K cached prefix produced ~10M `cache_read` even though only 100K unique tokens were ever cached, so session totals showed millions and all-time showed ~1.5T. Realistic numbers restored.
- `cache_read_tokens_{5h,7d,30d}` and per-bucket `cache_read` are now emitted as separate fields so a future cost view can multiply by the 0.1× rate without polluting human-readable totals.

### Changed

- Premium UI pass across every pane (popover, usage, stats, appearance, about):
  - New `DesignTokens.swift` with a single spacing scale (4/8/12/16/20/24/32), continuous-curve corner radii (8/12/16/20), typography ladder (28 display / 15 title / 12 body / 10 caption with proper kerning), and a unified `Surface.applyCard` recipe — removes the five different stroke/fill treatments that previously drifted between panes.
  - Hero card: gradient overlay (theme accent 10%→2%), 28pt tabular-figures percent, 4pt gradient context capsule with soft outer glow above 75%, project-first meta with tail truncation.
  - Sparkline: gradient-filled area + 1.5pt line + endpoint dot with accent-glow ring (replaces the previous bar chart).
  - Heatmap: squircle cells with continuous corner curve, smooth alpha ramp on theme accent (no more `systemOrange` regardless of theme).
  - Detail window now uses an `.underWindowBackground` `NSVisualEffectView` frost.
  - `ActivityDotView` pulse, refresh fade, and other animations honor `accessibilityDisplayShouldReduceMotion`.
  - Numbers everywhere use `monospacedDigitSystemFont` so values don't jitter horizontally on refresh.
  - Accessibility labels and values added on every custom NSView (ProgressBarView, SparklineView, HeatmapView, ActivityDotView, StatTileView, DualStatTileView).

## [0.3.0] - 2026-05-16

### Fixed

- Token math now follows Anthropic's billed-tokens view: `input + cache_create + cache_read + output`. Previous formula omitted `cache_read`, undercounting cache-heavy sessions by 10–100× versus the Anthropic console / `/cost`.
- 5-hour session split resets from session-start (matches Anthropic), not from the previous turn — long sessions no longer merge across resets.
- Context-window table corrected: default 200K; 1M only when the model tag literally contains `[1m]`/`-1m`. Stale name-based 1M guesses (sonnet-4-6, opus-4-7, mythos) removed; percentages no longer report fake-low.
- `last_context_pct` now ignores subagent transcripts (no `parentUuid`) and prefers the cwd-matched foreground session, so the foreground context % isn't inflated by Task / Agent tool calls.
- Claude path now counts extended-thinking / reasoning output tokens (parity with the Codex path).
- Dark Mode: stat tiles, chip cards, title preview, and theme cards refresh layer colors on `viewDidChangeEffectiveAppearance` — no more cards stuck in the previous appearance after toggling Light/Dark while the app runs.
- Heatmap and sparkline now follow the active theme palette (no more `systemOrange` drift in Neon/Terminal themes).
- Usage view preserves scroll position across 10-second refreshes.
- Popover hero meta truncates from the tail and prioritizes the project name; long model names like `claude-opus-4-7[1m]` no longer push the project off-screen.
- Theme card preview shows real `pctLow` / `pctMid` / `pctHigh` swatches at 12% / 42% / 85% instead of always 85% in `pctHigh`.
- `currentStreak` skips at most one leading empty day, then breaks on the next zero — a real gap correctly ends the streak.
- Background battery cost: the 10s timer no longer respawns the engine when both popover and detail window are hidden. FSEvents still drive on-demand refresh.
- Rust state writes are durable: `state_writer::atomic_write` now `fsync`s before rename and uses unique tmp suffixes (`pid.nanos.tmp`) so concurrent writers and `watch` daemons can't race the same temp file. `claude_statusline` writes through the same helper.
- Watch daemons honor SIGINT/SIGTERM cleanly and back off exponentially (1→60s) on consecutive errors instead of spinning at 30s on failures.
- `collect_dir` walks bound to depth 12 — pathological symlink loops and very deep repos no longer stall the engine.

### Added

- Update integrity: `UpdateManager` now fetches the published `.sha256` sibling asset, stream-hashes the downloaded DMG, and aborts on mismatch or fetch failure (no silent skip). Defense-in-depth on top of notarization.
- Popover material switched from `.menu` to `.popover` for proper native chrome.
- Localized strings for previously hardcoded English fragments (`context` caption, Quit menu, settings preview placeholder).

### Changed

- Daemon perf: `usage_signal.rs` now reuses `~/.context-bar/usage.cache.json` for up to 300s instead of spawning `python3 src/usage_signal.py` on every 30s watch tick.
- Release profile: `lto = "thin"`, `strip = "symbols"`, `codegen-units = 1` — smaller, faster engine binary.
- Logos compressed (`app_logo.png` 4.8M → 2.4M; `logo.png` 1.6M → 1.4M) via `oxipng -o max`.

### Removed

- ~150 lines of `_legacy_unused` AppKit menu code in `AppDelegate.swift`; dead views `LimitRowView`, `MenuHeaderView`, `DisplayTableController`, `buildContextRow`.

## [0.2.2] - 2026-05-15

### Fixed

- Popover stretched to full screen height. Now sizes to its content via
  `preferredContentSize` after each rebuild, and cards hug vertically so
  the hero section no longer absorbs the extra space.

## [0.2.1] - 2026-05-15

### Fixed

- Re-cut release; v0.2.0 CI run never picked up a macOS runner. No code changes.

## [0.2.0] - 2026-05-15

### Changed

- Replaced the legacy NSMenu dropdown with a native NSPopover panel (vibrant
  `.menu` material, continuous corner curves, SF Symbol toolbar). Settings,
  refresh, quit, and theme picker now live inside the popover footer.
- Theme picker shows live color swatches next to each option and previews
  the menubar title in the hovered theme's palette before commit.
- Settings window adopts a modern card style with uppercase section headers,
  hairline borders, adaptive light/dark backgrounds, and a transparent
  titlebar (`fullSizeContentView`).
- Session-duration formatting now switches to days past 24h (e.g. `7d 11h`
  instead of `179h 30m`).

### Added

- Per-session context percentage in parallel-session rows. The engine now
  records `last_input_tokens` and `context_window` per active session and
  exposes `context_pct` in `hud.json`.
- Limit rows (5h/7d) render an inline progress bar with threshold-colored
  fill so usage is readable at a glance instead of as a bare percentage.

### Fixed

- Menubar agent icons are now optically centered on the font's x-height with
  a small downward nudge so they sit on the same visual baseline as the
  surrounding title text.
- Popover footer buttons no longer require a focus click — the app activates
  before the popover is shown so the first click registers.
- Modern card layout: cards now span the full popover width regardless of
  intrinsic content (e.g. Parallel sessions / Other tools no longer collapse
  to the right of the panel).

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
- Menubar app packaging now copies bundled brand icon assets into `ContextBar.app/Contents/Resources/brands` for release builds.

## [0.1.7] - 2026-05-13

### Fixed

- Local app builds under `dist/ContextBar.app` now sync `CFBundleShortVersionString` and `CFBundleVersion` from the repository version instead of incorrectly showing the template `0.1.0 (1)`.

## [0.1.6] - 2026-05-13

### Improved

- In-app update flow now downloads the DMG in the background, stages the new app bundle, and prompts the user with a native "Restart to Update" action instead of sending them to GitHub or Downloads.
- Update UI now behaves like a first-party desktop app: progress is shown inline, release notes remain optional, and the primary path is a single update-confirm-restart flow.

## [0.1.5] - 2026-05-13

### Added

- `context-bar claude-statusline`, a Claude Code statusline sink that persists native context-window snapshots under `~/.context-bar/claude-statusline.json`.

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
- Removed redundant ContextBar header block at the top of the menubar dropdown.
- README restructured: install section moved to the top; Zed extension references removed.

## [0.1.3] - 2026-05-13

### Added

- Homebrew Cask (`Casks/context-bar.rb`) and release-workflow automation that bumps version + sha256 on every tag.

### Improved

- Menubar dropdown header no longer shows the version line; version remains in Settings → About.
- Reset timers render `6d 3h` (or `6g 3sa` in Turkish) instead of `149h` for spans ≥ 24h.

## [0.1.0] - 2026-05-12

Initial ContextBar release.

### Added

- Local-first repository context generation under `.context-bar/`
- Stable agent-facing outputs including `AGENT.md`, `CLAUDE.md`, and rolling markdown briefs
- CLI commands for `hud`, `snapshot`, `watch`, `global`, and `watch-global`
- Native macOS menubar companion app built with AppKit
- Native usage window for Claude Code and Codex with compact stats and rolling usage views
- Markdown and JSON artifacts for both human and tool consumption
- DMG packaging scripts for the macOS app
- GitHub Actions release workflow for tagged builds

### Improved

- Product naming and repository presentation aligned under `ContextBar`
- README upgraded to a more product-oriented structure
- GitHub repository metadata updated for release distribution

### Notes

- The macOS companion app is optional; the CLI is the most reliable always-on surface today.
- Repository summaries are local-first and do not require a hosted backend.
