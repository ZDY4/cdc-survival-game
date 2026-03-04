# CDC Survival Game - Agent Guide

**Godot 4.6 + GDScript | Modular Survival Game**

## Quick Commands

```bash
# Run game
godot --path . --scene scenes/ui/main_menu.tscn

# Run tests via Python runner
python tests/agent_test_runner.py --all
python tests/agent_test_runner.py --sanity        # 30s - file integrity
python tests/agent_test_runner.py --functional    # 5min - unit tests
python tests/agent_test_runner.py --agent         # 30min+ - AI exploration

# Run single test (requires game running on port 8080)
curl -X POST http://localhost:8080/execute \
  -H "Content-Type: application/json" \
  -d '{"action": "test", "parameters": {"test_name": "event_bus"}}'

# Run GDScript test directly
godot --path . --script tests/functional/unit/test_event_bus.gd

# Check game health
curl http://localhost:8080/health
```

## Project Structure

| Directory | Purpose | Key Files |
|-----------|---------|-----------|
| `core/` | Framework | EventBus, GameState, BaseModule |
| `modules/` | Features | dialog/, combat/, inventory/, map/ |
| `systems/` | Game systems | save_system.gd, weapon_system.gd |
| `scenes/` | Locations | safehouse.tscn, street_a.tscn |
| `scripts/ui/` | UI scripts | inventory_ui.gd, crafting_ui.gd |
| `tests/` | Tests | sanity/, functional/, agent/ |

## Code Style

### Naming Conventions
- **Classes**: `PascalCase` (`DialogModule`)
- **Files**: `snake_case` (`dialog_module.gd`)
- **Functions/Variables**: `snake_case` (`show_dialog`)
- **Constants**: `UPPER_SNAKE_CASE` (`MAX_HEALTH`)
- **Private**: `_underscore` (`_internal_state`)
- **Signals**: `snake_case` (`dialog_finished`)

### File Organization
```gdscript
extends Node
## Brief description

# 1. Constants
const MAX_HP := 100

# 2. Exports
@export var health: int = MAX_HP

# 3. Public variables
var is_alive: bool = true

# 4. Private variables
var _cache: Dictionary = {}

# 5. Signals
signal health_changed(new_hp: int)

# 6. Public methods
func take_damage(amount: int) -> void:
    pass

# 7. Private methods
func _update_ui() -> void:
    pass
```

### Type Annotations (Required)
```gdscript
var name: String = ""
var health: int = 100
var speed: float = 5.0
var items: Array[Dictionary] = []

func calculate(base: int, mult: float) -> int:
    return int(base * mult)
```

### Error Handling
```gdscript
# Safe node access
var btn := get_node_or_null("Panel/Button")
if not btn:
    push_error("Button not found")
    return

# Input validation
func show_dialog(text: String) -> void:
    assert(not text.is_empty(), "Text required")

# Autoload Pattern - NO class_name for autoloads
extends BaseModule

func _ready():
    call_deferred("_setup_ui")  # ALWAYS use call_deferred for add_child

func _setup_ui() -> void:
    var ui = load("res://path.tscn").instantiate()
    get_tree().root.add_child(ui)
```

## Critical Patterns

```gdscript
# EventBus Communication
EventBus.subscribe(EventBus.EventType.PLAYER_HURT, _on_hurt)
EventBus.emit(EventBus.EventType.PLAYER_HURT, {"damage": 10})
EventBus.unsubscribe(EventBus.EventType.PLAYER_HURT, _on_hurt)  # in _exit_tree

# State Updates
GameState.player_hp -= damage  # Direct for simple cases
GameState.damage_player(10)    # Methods for complex (emits events)
```

## Anti-Patterns

Never: `add_child()` in `_ready()` without `call_deferred` • `get_node()` without null check (use `get_node_or_null`) • `class_name` in autoloads • Direct module dependencies (use EventBus) • Suppress type errors (`as any`, `@ts-ignore`)

## Testing

| Priority | Description | Pass Rate |
|----------|-------------|-----------|
| **P0_CRITICAL** | Core features | 100% |
| **P1_MAJOR** | Important features | >95% |
| **P2_MINOR** | Nice-to-have | >80% |

### Writing Tests
```gdscript
# tests/functional/unit/test_example.gd
static func run_tests(runner: TestRunner) -> void:
    runner.register_test(
        "test_name",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P1_MAJOR,
        _test_func
    )

static func _test_func() -> void:
    assert(condition, "Error message")
```

## Key Autoloads

| Name | File | Purpose |
|------|------|---------|
| EventBus | core/event_bus.gd | Global events |
| GameState | core/game_state.gd | Game data |
| BaseModule | core/base_module.gd | Module base class |
| DialogModule | modules/dialog/ | Dialog UI |
| CombatModule | modules/combat/ | Combat system |
| InventoryModule | modules/inventory/ | Items |
| MapModule | modules/map/ | Travel |
| SaveSystem | systems/save_system.gd | Save/load |

## References

- `tests/README.md` - Testing guide
- `tests/TEST_FRAMEWORK.md` - Test architecture
- `core/AGENTS.md` - Core framework details
- `tests/AGENTS.md` - Test framework details
