# Legacy Bevy Agent Workflows

This directory keeps archived Bevy workflow notes for behavior comparison during the Godot migration.

Current agent workflows live under `docs/agent-workflows/` and should use the Godot tools in `tools/agent/`.

Use these old commands only when explicitly comparing historical Rust/Bevy behavior:

```powershell
cargo run -p content_tools -- locate <item|recipe|character|map> <id>
cargo run -p content_tools -- validate <item|recipe|character|map> <id>
cargo run -p content_tools -- validate changed
cargo run -p content_tools -- summarize <item|recipe|character|map> <id>
cargo run -p content_tools -- references <item|map> <id>
cargo run -p content_tools -- format <item|recipe|character|map> <id>
cargo run -p content_tools -- format changed
cargo run -p content_tools -- diff-summary --path <file>
cargo check -p game_editor -p bevy_item_editor -p bevy_recipe_editor -p bevy_dialogue_editor -p bevy_quest_editor -p bevy_map_editor -p content_tools
pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Map <id>
pwsh -NoProfile -File legacy/bevy/agent/review-map-visual.ps1 -Map <id>
pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1
```
