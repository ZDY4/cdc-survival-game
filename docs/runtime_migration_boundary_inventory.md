# Godot / Rust Runtime Boundary Inventory

This document freezes the intended migration boundary while the project moves
from a Godot-heavy runtime toward the shared Rust + Bevy authority described in
[AGENTS.md](/D:/Projects/cdc-survival-game/AGENTS.md).

## Migration Targets

- `core/game_state.gd`
  - Current Godot-side authority container for player/world/runtime state.
  - Long-term target: split into shared Rust runtime state plus Godot read-only UI/view caches.
- `core/data_manager.gd`
  - Current mixed loader/migrator for content data.
  - Long-term target: Rust `game_data` as the only schema, load, and validation authority.
- `systems/turn_system.gd`
  - Current local AP/turn authority.
  - Long-term target: `game_core` turn runtime.
- `systems/combat_system.gd`
  - Current local combat execution and result assembly.
  - Long-term target: Rust combat rules with Godot-only presentation hooks.
- `systems/interaction_system.gd` and `modules/interaction/*`
  - Current local interaction authority and option execution path.
  - Long-term target: protocol client only; authoritative interaction runs in Rust.
- `modules/map/map_module.gd`
  - Current mixed map travel rules plus scene transition orchestration.
  - Long-term target: Rust owns travel/context rules; Godot owns scene loading/presentation.
- `systems/ai/ai_manager.gd`
  - Current mixed visual spawn path plus behavior/runtime assembly.
  - Long-term target: Rust owns decision/state; Godot owns actor visualization and input hit mapping.

## Godot Frontend Shell

- Scene loading and scene tree orchestration
- Camera, audio, VFX, hit reactions, hover/highlight, path preview
- Input collection and click detection
- UI rendering for inventory, combat, dialog, status, debug overlays
- Visual actor spawn/despawn and animation playback

## Keep In Godot

- `addons/cdc_procedural_builder`
- Godot Inspector / Dock integrations
- Other editor-only tools that fundamentally depend on the Godot editor or scene tree

## Guardrails

- Do not add new long-term gameplay rules to the marked migration targets.
- When a change is required in those files, prefer:
  - protocol client glue
  - temporary compatibility shims
  - presentation-only behavior
- Delete Godot authority code only after:
  - the Rust authority exists
  - protocol coverage exists
  - Godot read-only integration exists
  - regression checks pass
