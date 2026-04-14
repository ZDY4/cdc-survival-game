# Rust Workspace

This directory contains the incremental Rust-side architecture for the project.

## Layout

- `crates/game_data`: shared data models
- `crates/game_protocol`: IPC protocol messages
- `crates/game_core`: reusable gameplay logic
- `crates/game_bevy`: shared Bevy runtime assembly
- `apps/bevy_server`: headless Bevy runtime
- `apps/bevy_debug_viewer`: windowed Bevy debug viewer

## Character Definition Authority

Character definitions now use Rust as the single source of truth:

- Schema: `rust/crates/game_data/src/character.rs`
- Content files: `data/characters/*.json`
- Runtime loading: `game_data::load_character_library`
- Bevy-side assembly: `rust/crates/game_bevy/src/lib.rs`

Legacy script-side `CharacterData.gd` / `NPCData.gd` models are no longer
authoritative and are not kept in sync with the Rust schema.

## Runtime Assembly Layers

- `game_data` owns content schema, loading, and validation.
- `game_core` owns engine-agnostic simulation/runtime rules.
- `game_bevy` owns shared Bevy app assembly, including definition-to-ECS and definition-to-runtime seed integration.
- `bevy_server` and `bevy_debug_viewer` only own app entrypoints, reporting, and presentation.

## Intended next steps

1. Install Rust and Cargo on the local machine.
2. Run `cargo check` inside `rust/`.
3. Expand `game_data` with real content schemas from `data/`.
4. Run `cargo run -p bevy_server` for the headless demo flow.
5. Run `cargo run -p bevy_debug_viewer` for the windowed logic viewer.
6. Add a transport layer in `game_protocol` or `bevy_server`.
7. Continue migrating remaining legacy systems into `game_core`.
