# Systems - Knowledge Base

**Location:** `systems/`  
**Scope:** Cross-cutting game systems (equipment incl. weapons, time, save)

## Overview

This directory contains high-complexity systems that manage game-wide mechanics:
- **Equipment System** (874 lines) - Unified equipment management (角色挂载)
- **Weapon Logic** (merged) - now inside Equipment System
- **Time Manager** (282 lines) - Day/night cycle, game time
- **Save System** - JSON serialization

## Where to Look

| System | File | Complexity | Purpose |
|--------|------|------------|---------|
| Equipment | `equipment_system.gd` | HIGH | Gear slots, stats, encumbrance |
| Weapons (merged) | `equipment_system.gd` | HIGH | Firearms, melee, ammo, durability |
| Time | `time_manager.gd` | MEDIUM | Time progression, schedules |
| Save | `save_system.gd` | LOW | JSON save/load |

## Conventions (Systems)

### System Pattern
```gdscript
extends Node
# Systems extend Node (not BaseModule) - they can be instanced

# Cache GameState reference
var _game_state: Node

func _ready():
    _game_state = get_node("/root/GameState")
    if not _game_state:
        push_error("[SystemName] GameState not found")
        return
```

### Large File Organization (>500 lines)

**equipment_system.gd structure:**
```
# 1. Constants & Enums
# 2. Public API (high-level methods)
# 3. Equipment Slots Management
# 4. Stats Calculation
# 5. Encumbrance Logic
# 6. Private Helpers
```

## Critical Patterns

### Equipment System
```gdscript
# Get equipped item in slot
func get_equipped(slot: String) -> Dictionary:
    return _equipment_slots.get(slot, {})

# Equip item with validation
func equip_item(item: Dictionary) -> bool:
    if not _can_equip(item):
        return false
    # ... equip logic
    _recalculate_stats()
    return true
```

### Weapon (Merged into Equipment System)
```gdscript
var equip_system = GameState.get_equipment_system()
if equip_system:
    var result = equip_system.perform_attack()
    if not result.success:
        return
```

## Anti-Patterns (Systems)

- **Don't** access systems directly from modules - use EventBus
- **Don't** modify GameState directly - use exposed methods
- **Don't** create circular dependencies between systems

## Integration Points

| System | Consumes | Emits |
|--------|----------|-------|
| Equipment | `INVENTORY_CHANGED` | `EQUIPMENT_CHANGED`, `STATS_CHANGED` |
| Time | - | `TIME_ADVANCED`, `DAY_NIGHT_CHANGED` |
| Save | `GAME_SAVED` | `GAME_LOADED` |

## Performance Notes

- Equipment system caches calculated stats
- Time manager uses Timer nodes, not _process delta

## See Also

- Parent: [`../AGENTS.md`](../AGENTS.md)
- Related: `core/game_state.gd` (data storage)
- Related: `modules/inventory/` (item source)
