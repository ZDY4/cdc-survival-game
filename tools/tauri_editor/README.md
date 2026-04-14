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
3. Migrate item, dialogue, and quest editing flows incrementally.
4. Add IPC/TCP-backed preview and authoring surfaces around `bevy_server`.

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
- Add IPC/TCP preview connection to `bevy_server`
