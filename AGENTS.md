# CDC Survival Game - Agent Guide

Godot 4.6 + GDScript project.

## Scope

- This file covers repo-wide conventions.
- More specific guidance lives in [core/AGENTS.md](G:\Projects\cdc_survival_game\core\AGENTS.md), [systems/AGENTS.md](G:\Projects\cdc_survival_game\systems\AGENTS.md), and [tests/AGENTS.md](G:\Projects\cdc_survival_game\tests\AGENTS.md).

## Current Entrypoints

```bash
# Run the main menu when Godot is available in PATH
godot --path . --scene scenes/ui/main_menu.tscn

# API smoke test
python tests/test_via_api.py

# Agent smoke test
python tests/agent_test_runner.py
```

## Project Rules

- Treat `project.godot` as the source of truth for autoloads and project entrypoints.
- Use typed GDScript for exported values, public state, and function signatures.
- Prefer `get_node_or_null()` over unchecked `get_node()`.
- If UI is added to the scene tree from an autoload or module, prefer `call_deferred()` before `add_child()`.
- For autoload modules that extend `BaseModule`, do not add `class_name`.
- Keep module coupling low. Use `EventBus`, `GameState`, or existing service APIs instead of inventing new cross-module references.
- Before trusting any hardcoded example, verify the current implementation in code.

## Directory Map

- `core/`: shared framework, autoload foundations, global state, input helpers
- `modules/`: feature-specific gameplay and UI modules
- `systems/`: game-wide services such as time, combat, save/load, progression
- `scenes/`: scene entrypoints and location/UI scenes
- `tests/`: API smoke tests, GDScript sanity/functional tests, test utilities

## References

- [project.godot](G:\Projects\cdc_survival_game\project.godot)
- [tests/README.md](G:\Projects\cdc_survival_game\tests\README.md)
- [tests/TEST_FRAMEWORK.md](G:\Projects\cdc_survival_game\tests\TEST_FRAMEWORK.md)
