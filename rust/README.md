# Rust Workspace

This directory contains the incremental Rust-side architecture for the project.

## Layout

- `crates/game_data`: shared data models
- `crates/game_protocol`: IPC protocol messages
- `crates/game_core`: reusable gameplay logic
- `apps/bevy_server`: headless Bevy runtime
- `apps/bevy_debug_viewer`: windowed Bevy debug viewer

## Intended next steps

1. Install Rust and Cargo on the local machine.
2. Run `cargo check` inside `rust/`.
3. Expand `game_data` with real content schemas from `data/`.
4. Run `cargo run -p bevy_server` for the headless demo flow.
5. Run `cargo run -p bevy_debug_viewer` for the windowed logic viewer.
6. Add a transport layer in `game_protocol` or `bevy_server`.
7. Migrate suitable systems from Godot into `game_core`.
