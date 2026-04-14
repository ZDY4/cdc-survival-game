# Tauri Editor

This directory hosts the new standalone content editor described in `doc/new_plan.md`.

## Goal

The editor is the third client in the long-term architecture:

- `Bevy` owns gameplay logic, state calculation, and runtime clients
- `Tauri 2 + Web` owns content authoring workflows

## Current scope

This project now includes:

- a reusable standalone editor shell
- shared field controls and validation panels
- a reusable `GraphKit` layer backed by `@xyflow/react`
- a working item editor backed by `data/items`
- a graph-based dialogue editor backed by `data/dialogues`

It now serves as the standalone replacement for the old in-engine editing flow.

Planned migration path:

1. Keep the standalone editor shell here as the primary content tool.
2. Move data loading, validation, and protocol-aware editing into shared Rust crates.
3. Migrate item, dialogue, quest, and map editing flows incrementally.
4. Expand review and authoring flows around the same standalone workspace.

## Layout

```text
tools/tauri_editor/
├── src/                  # Web UI
├── src-tauri/            # Tauri Rust host
├── index.html            # Vite entry
├── package.json
├── tsconfig.json
└── vite.config.ts
```

## Next steps

- Move more validation into shared runtime crates instead of Tauri-local helpers
- Reuse the same `GraphKit` base for quest flow editing
- Keep quest relationship graph as a separate follow-up surface
- Add layered map editors on top of the same shell
- Add IPC/TCP preview connection to `bevy_server`

## Narrative Chat Regression

NarrativeLab now includes a dedicated regression path for AI chat and document editing flows.

### What it covers

- conversation turn classification: `clarification`, `options`, `plan`, `final_answer`
- Markdown rendering in chat and document preview
- patch application and full-document apply
- pending action approval and rejection
- derived document creation and save
- provider error handling, stream fallback, and cancel-inflight

### Offline regression

Offline mode uses an isolated workspace seed plus a local OpenAI-compatible stub, so it does not depend on a real API.

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File tools/narrative_lab/scripts/run_narrative_chat_regression.ps1 -Mode offline
```

Or use the batch wrapper:

```bat
run_narrative_lab_regression.bat offline
```

### Online smoke

Online mode reuses the core scenario subset against the currently configured AI provider.

```powershell
pwsh -NoLogo -NoProfile -File tools/narrative_lab/scripts/run_narrative_chat_regression.ps1 -Mode online
```

You can also target a narrower smoke tier:

```powershell
pwsh -NoLogo -NoProfile -File tools/narrative_lab/scripts/run_narrative_chat_regression.ps1 -Mode online-core
pwsh -NoLogo -NoProfile -File tools/narrative_lab/scripts/run_narrative_chat_regression.ps1 -Mode online-structured
```

If the provider connection test fails because AI credentials or base URL are missing, the run is exported as skipped instead of being reported as passed.

### Reports and logs

Regression runs use isolated temporary workspaces:

- offline: `tmp/narrative_lab_regression_offline`
- online: `tmp/narrative_lab_regression_online`

Each run exports structured reports under:

- `exports/chat_regressions/*.json`
- `exports/chat_regressions/*.md`

The runner also preserves host logs for debugging:

- `app.stdout.log`
- `app.stderr.log`
- `stub.log` in offline mode
