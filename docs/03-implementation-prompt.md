# Implementation Prompt For A Separate Session

Bu prompt, baska bir Codex/AI oturumunda implementasyonu ilerletmek icin tasarlandi. Amac, urun hedefini slash-command odakli degil, `always-on context HUD + automatic assistant context` odakli tutmak.

## Prompt

```text
You are implementing a Zed extension prototype called "Zed Context Pilot" in this repository.

Read these files first and treat them as the product spec:

- docs/01-research.md
- docs/02-architecture.md
- README.md

Current state:

- A minimal Zed extension scaffold already exists.
- `/hello` slash command exists only as API validation.
- This is not a slash-command-first product.

Product goal:

Build the foundation for an always-on context system inside Zed that gives Claude-HUD-like awareness:

1. visible context HUD
2. automatic assistant context
3. three time windows:
   - now: last 15 minutes
   - session: last 5 hours
   - week: last 7 days

Important constraints:

- Treat `/brief` or any manual slash command as fallback, not the main UX.
- Keep the implementation high-signal and scoped.
- Prefer a strong context engine and state model before overcommitting to uncertain Zed UI hooks.
- Do not invent unverified Zed APIs. If a Zed integration surface is unclear, isolate it behind a small interface and document the uncertainty.

Implementation priorities:

1. Build a `context engine` in Rust that can generate structured summaries for:
   - now
   - session
   - week

2. Use reliable data sources first:
   - git branch
   - recent commits
   - staged/unstaged changes
   - recently touched files

3. Write artifacts to a local project state area, for example:
   - .zed-context/state.json
   - .zed-context/brief-now.md
   - .zed-context/brief-session.md
   - .zed-context/brief-week.md

4. Keep the code modular. Suggested modules:
   - src/lib.rs
   - src/context_engine.rs
   - src/git_signal.rs
   - src/time_windows.rs
   - src/state_writer.rs
   - src/slash_commands.rs

5. If needed, keep `/hello` and add `/brief` only as debug/fallback surfaces.

6. Add focused documentation updates as the code evolves.

What I want from you:

- inspect the current repo
- design the next code structure
- implement the context engine foundation
- keep the extension compiling with `cargo check`
- explain any unverified Zed integration assumptions explicitly

Do not stop after planning. Make the code changes.
```

## Kullanım notu

Bu prompt tek basina yeterli, ama daha iyi sonuc icin su ek cumle de verilebilir:

```text
If Zed UI/HUD APIs are not clearly available, implement the engine and storage model first, and leave a narrow integration seam rather than guessing.
```
