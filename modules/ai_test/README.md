# AI Test Module

This module provides a lightweight, in-project testing interface for game logic. It exposes an action registry and an optional HTTP API for automation.

## Enable HTTP API
1. Edit `modules/ai_test/ai_test_settings.tres`:
   - `enable_http_api = true`
   - `auto_start = true`
   - `port = 8080` (or your preferred port)
2. Run the game.

In `test_mode`, HTTP is disabled by default unless `enable_http_api = true`.

## HTTP Endpoints
- `GET /health` -> `{ "status": "ok" }`
- `GET /actions` -> list of registered actions
- `POST /` with JSON body:
  - Single action:
    ```json
    { "action": "start_game", "params": {} }
    ```
  - Batch:
    ```json
    { "batch": [ { "action": "start_game" }, { "action": "get_state" } ] }
    ```
  - State:
    ```json
    { "method": "get_state" }
    ```

## Default Actions
Scene
- `start_game`
- `continue_game`

Interaction
- `interact.primary` (params: `node_path` or `node_name`)
- `interact.option` (params: `node_path` or `node_name`, optional `index` or `option_name`)

Dialog
- `dialog.choose` (params: `index` or `text`)
- `dialog.continue`

Combat
- `combat.attack` (params: `attack_type`, `target_part`)

## Notes
- Actions are implemented in `modules/ai_test/ai_test_bridge.gd`.
- The registry is intentionally game-logic first; UI automation is optional.
