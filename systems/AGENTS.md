# Systems - Agent Notes

## Scope

- Applies to files under `systems/`.
- Systems are game-wide services such as combat, time, save/load, progression, movement, and world simulation.

## Working Rules

- Do not assume every system follows the same pattern. Some are long-lived services, some are helper components, and some expose signals instead of EventBus events.
- Check `project.godot` before assuming a system is autoloaded.
- Prefer extending existing system APIs over duplicating logic in modules or UI scripts.
- When changing a system, search for direct consumers in `modules/`, `scripts/`, and `ui/`.
- Keep documentation and code comments focused on real integration points, not file-length or complexity trivia.

## Files Commonly Worth Checking

- `systems/time_manager.gd`
- `systems/save_system.gd`
- `systems/combat_system.gd`
- `systems/equipment_system.gd`
- `systems/interaction_system.gd`

## Notes

- `TimeManager` exposes its own signals such as `time_advanced`; not all cross-system communication goes through `EventBus`.
- Save/load behavior and platform-specific persistence details live in `save_system.gd`.
