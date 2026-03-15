# Core - Agent Notes

## Scope

- Applies to files under `core/`.
- This directory contains shared foundations such as `EventBus`, `GameState`, `BaseModule`, and input/UI helpers.

## Source Of Truth

- Read the target file before relying on assumptions. Core APIs evolve and this document is intentionally minimal.
- `project.godot` is the source of truth for which scripts are autoloaded.

## Working Rules

- `GameState` is the main shared player/world state container. Prefer existing methods when state changes also need side effects or events.
- `EventBus` is the preferred decoupling mechanism for broadcast-style gameplay events, but it is not the only valid integration path in the repo.
- `BaseModule` is the common base for module-style autoload scripts. If a module extends `BaseModule`, follow the existing autoload pattern and avoid `class_name`.
- Keep core code free of feature-specific assumptions from individual modules whenever possible.
- If you change a core API, search for all consumers before finalizing.

## Files To Check First

- `core/event_bus.gd`
- `core/game_state.gd`
- `core/base_module.gd`
- `core/input_actions.gd`
- `core/responsive_ui_manager.gd`
