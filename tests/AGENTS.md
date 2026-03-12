# Tests - Knowledge Base

**Location:** `tests/`  
**Scope:** 3-layer testing architecture

## Overview

Unique testing architecture with three layers:
- **Sanity** (30s): File integrity, syntax, basic connectivity
- **Functional** (5min): Unit/integration tests via Python runner
- **Agent** (30min+): AI-driven exploratory testing via HTTP API

## Quick Commands

```bash
# Agent smoke test (HTTP API)
python tests/agent_test_runner.py

# API smoke test
python tests/test_via_api.py

# Single test via API
curl http://localhost:8080/execute \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"action": "get_state", "params": {}}'
```

## Where to Look

| Layer | Directory | Runner | Duration |
|-------|-----------|--------|----------|
| Sanity | `tests/sanity/` | Python | 30s |
| Functional | `tests/functional/` | Python | 5min |
| Agent | `tests/agent/` | Python + AI | 30min+ |
| Utils | `tests/utils/` | Shared | - |

## Test Execution Flow

```
Sanity Test
    ↓ PASS
Functional Test
    ↓ PASS (P0: 100%, P1: >95%)
Agent Test
    ↓ COMPLETE
Final Report
```

**Rules:**
- Sanity fails → Stop immediately
- Functional fails → Fix before Agent
- Agent fails → Review findings

## Writing Tests

### Sanity Test
```python
# tests/sanity/test_module_exists.py
def test_dialog_module_exists():
    """Verify dialog_module.gd exists and has valid syntax"""
    assert file_exists("modules/dialog/dialog_module.gd")
    assert syntax_valid("modules/dialog/dialog_module.gd")
```

### Functional Test
```gdscript
# tests/functional/unit/test_dialog_module.gd
static func run_tests(runner: TestRunner) -> void:
    runner.register_test(
        "test_show_dialog",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P0_CRITICAL,
        _test_show_dialog
    )

static func _test_show_dialog() -> void:
    DialogModule.show_dialog("Test message")
    assert(DialogModule._dialog_ui.visible, "Dialog should be visible")
```

### Agent Test
```python
# tests/agent/test_exploration.py
class ExplorationAgent(CDCAgentBase):
    def decide_next_action(self, game_state):
        # AI decision logic
        if game_state["player"]["hp"] < 30:
            return AgentAction.SLEEP, {}
        elif random.random() < 0.5:
            return AgentAction.SEARCH, {}
        else:
            return AgentAction.TRAVEL, {"destination": "street_a"}
```

## Test Priority Levels

| Priority | Criteria | Required Pass Rate |
|----------|----------|-------------------|
| P0_CRITICAL | Core functionality | 100% |
| P1_MAJOR | Important features | >95% |
| P2_MINOR | Nice-to-have | >80% |

## API Testing

Game exposes HTTP API on port 8080:

```bash
# Get full game state
curl http://localhost:8080/state

# Execute action
curl -X POST http://localhost:8080/execute \
  -d '{"action": "travel", "params": {"destination": "street_a"}}'
```

## Anti-Patterns (Tests)

- **Don't** test implementation details - test behavior
- **Don't** have tests depend on each other
- **Don't** hardcode timeouts - use configurable waits
- **Don't** skip failing tests - fix or remove

## Debug Overlay

Press **F12** in-game to see:
- Live game state
- AI Test Bridge status
- Recent actions log

## See Also

- Parent: [`../AGENTS.md`](../AGENTS.md)
- Architecture: `tests/TEST_FRAMEWORK.md`
- Usage: `tests/README.md`
- API: `modules/ai_test/ai_test_bridge.gd`
