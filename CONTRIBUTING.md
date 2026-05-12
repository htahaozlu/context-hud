# Contributing to ContextHUD

Thanks for contributing.

## Scope

ContextHUD is a local-first developer tool. Contributions should preserve these principles:

- repository context remains local-first
- outputs stay useful for both humans and coding agents
- product naming stays consistent as `ContextHUD`
- the macOS app remains native in feel and restrained in UI complexity

## Before opening an issue

- use Discussions for questions, setup help, and open-ended product conversation
- use Issues for confirmed bugs, concrete feature requests, and actionable tasks
- search existing issues and discussions first

## Development setup

### CLI and core

```bash
cargo check
cargo run --example snapshot
```

### macOS packaging

```bash
scripts/build-menubar-app.sh
scripts/create-macos-dmg.sh
```

## Pull request expectations

Keep changes focused and explain the user-facing effect clearly.

For most pull requests:

- describe the problem being solved
- describe the behavioral change
- include verification steps
- update documentation when commands, outputs, or workflows change

## Naming and positioning

- use `ContextHUD` as the product name
- do not reintroduce old repository naming such as `zed-context`
- describe the product as local-first repository context plus a native macOS HUD for coding agents

## Reporting security issues

Do not open public issues for security-sensitive findings. Use GitHub Security Advisories instead.

