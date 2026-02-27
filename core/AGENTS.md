# Core - Knowledge Base

**Location:** `core/`  
**Scope:** Foundational framework for all modules

## Overview

Core provides the foundational architecture:
- **EventBus** - Global event system (publish/subscribe)
- **GameState** - Single source of truth for game data
- **BaseModule** - Base class for all feature modules
- **ResponsiveUIManager** - UI adaptation utilities

## Where to Look

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| EventBus | `event_bus.gd` | ~50 | Event system with 17 event types |
| GameState | `game_state.gd` | ~130 | Global state management |
| BaseModule | `base_module.gd` | ~30 | Module base class |
| ResponsiveUI | `responsive_ui_manager.gd` | ~90 | Screen adaptation |

## Conventions (Core)

### EventBus Pattern
```gdscript
# Define event types as enum
enum EventType {
    GAME_STARTED,
    PLAYER_HURT,
    INVENTORY_CHANGED,
    # ... 17 total
}

# Subscribe to events
EventBus.subscribe(EventBus.EventType.PLAYER_HURT, _on_player_hurt)

# Emit events
EventBus.emit(EventBus.EventType.PLAYER_HURT, {"damage": 10, "source": "zombie"})

# Unsubscribe (in _exit_tree)
EventBus.unsubscribe(EventBus.EventType.PLAYER_HURT, _on_player_hurt)
```

### GameState Pattern
```gdscript
# Direct variable access (not getters/setters for simple cases)
GameState.player_hp -= damage

# Use helper methods for complex logic
GameState.damage_player(10)  # Emits event automatically
GameState.add_item("food", 2)  # Checks capacity, emits event

# NEVER modify from outside core - use methods
# BAD: GameState.inventory_items.append(item)
# GOOD: GameState.add_item(item_id, count)
```

### BaseModule Pattern
```gdscript
extends BaseModule
# No class_name - accessed by filename

func _ready():
    # Always call parent _ready if overriding
    super._ready()
    call_deferred("_initialize")

func _initialize():
    # Module-specific setup
    pass

func _validate_input(data: Dictionary, required: Array) -> bool:
    # Built-in validation
    for field in required:
        if not data.has(field):
            module_error.emit("Missing: " + field)
            return false
    return true
```

## Critical Rules

1. **EventBus is the ONLY communication channel** between modules
2. **GameState is single source of truth** - no module caches state
3. **BaseModule provides common functionality** - all modules extend it
4. **Core has no dependencies** on modules or systems

## Anti-Patterns (Core)

- **Never** create circular dependencies in EventBus handlers
- **Never** store references to GameState in long-lived variables (use get_node)
- **Never** modify GameState from UI code - emit events instead

## Event Type Reference

| Event | Data Payload | When Emitted |
|-------|--------------|--------------|
| `GAME_STARTED` | - | New game or load |
| `GAME_SAVED` | - | After save completes |
| `GAME_LOADED` | - | After load completes |
| `PLAYER_HURT` | `{"hp", "damage"}` | Player takes damage |
| `PLAYER_HEALED` | `{"hp", "amount"}` | Player healed |
| `INVENTORY_CHANGED` | - | Items added/removed |
| `LOCATION_CHANGED` | `{"location"}` | Player moved |
| `COMBAT_STARTED` | `{"enemy"}` | Combat begins |
| `COMBAT_ENDED` | `{"victory", "rewards"}` | Combat ends |

## See Also

- Parent: [`../AGENTS.md`](../AGENTS.md)
- Consumers: `modules/*` (all modules subscribe to events)
- Related: `systems/save_system.gd` (persists GameState)
