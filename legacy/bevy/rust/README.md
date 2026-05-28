# Legacy Rust Workspace

This archived workspace keeps the old Rust/Bevy implementation for historical behavior comparison during the Godot migration.

Default development should use the Godot project and tools at the repository root. Run this workspace only through `legacy/bevy/` launchers or explicit legacy comparison commands.

## Layout

- `crates/game_data`: shared data models
- `crates/game_protocol`: IPC protocol messages
- `crates/game_core`: reusable gameplay logic
- `crates/game_bevy`: shared Bevy runtime assembly
- `apps/bevy_server`: headless Bevy runtime
- `apps/bevy_debug_viewer`: windowed Bevy game client

## Character Definition Authority

Character definitions were previously loaded through Rust:

- Schema: `legacy/bevy/rust/crates/game_data/src/character.rs`
- Content files: `data/characters/*.json`
- Runtime loading: `game_data::load_character_library`
- Bevy-side assembly: `legacy/bevy/rust/crates/game_bevy/src/lib.rs`

Legacy script-side character models are no longer authoritative and are not
kept in sync with the Rust schema.

## Runtime Assembly Layers

- `game_data` owns content schema, loading, and validation.
- `game_core` owns engine-agnostic simulation/runtime rules.
- `game_bevy` owns shared Bevy app assembly, including definition-to-ECS and definition-to-runtime seed integration.
- `bevy_server` and the Bevy game client only own app entrypoints, reporting, and presentation.

## Legacy Use

1. Install Rust and Cargo on the local machine.
2. Run `cargo check` inside `legacy/bevy/rust/` only for legacy behavior comparison.
3. Run `legacy/bevy/run_bevy_game.bat` only when old Bevy behavior comparison is required.

The migration default is the repository root `run_godot_game.bat`.
