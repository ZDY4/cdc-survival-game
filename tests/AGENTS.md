# Tests - Agent Notes

## Scope

- Applies to files under `tests/`.
- The repo currently mixes Python API smoke tests with GDScript sanity/functional tests.

## Current Entry Points

```bash
# API connectivity and basic state/action checks
python tests/test_via_api.py

# Agent-style smoke run through the HTTP bridge
python tests/agent_test_runner.py
```

## Test Layout

- `tests/sanity/`: GDScript file-integrity and baseline checks
- `tests/functional/unit/`: GDScript unit-style tests
- `tests/agent/`: Python agent utilities and base classes
- `tests/manual/`: manual/editor smoke scenes
- `tests/utils/`: shared GDScript test helpers

## HTTP Bridge Notes

- The game test bridge exposes `/health`, `/state`, `/actions`, and `/execute`.
- `/execute` currently expects `{"action": "...", "params": {...}}`.
- The source of truth for registered action names is `modules/ai_test/ai_test_bridge.gd`, not this document.

## Working Rules

- Prefer behavior checks over implementation-detail assertions.
- If a test depends on the live HTTP bridge, make sure the project is already running.
- When documenting or adding an action-based test, verify the action exists in `/actions` first.
- Keep examples aligned with the current API shape and current registered actions.

## Useful References

- [tests/README.md](G:\Projects\cdc_survival_game\tests\README.md)
- [tests/TEST_FRAMEWORK.md](G:\Projects\cdc_survival_game\tests\TEST_FRAMEWORK.md)
- [modules/ai_test/ai_test_bridge.gd](G:\Projects\cdc_survival_game\modules\ai_test\ai_test_bridge.gd)
