# Edit Recipe Workflow

## Scope

适用于：

- 修改现有 recipe
- 新增 recipe
- 调整材料、产出、技能要求、解锁条件

## Primary Files

- `data/recipes/*.json`

常见依赖：

- `data/items/*.json`
- `data/skills/*.json`
- 其他 `data/recipes/*.json`

## Agent Steps

1. 定位目标 recipe 文件。
2. 先读取 recipe 摘要，再检查关联 item / skill / recipe id。
3. 修改 JSON。
4. 跑最小校验。
5. 总结是否影响现有材料或 unlock 链路。

## Validation

当前优先使用：

- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind recipe -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind recipe -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind recipe -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind recipe -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind recipe -Id <id>`

旧 Rust/Bevy 对照基线仅在需要差异分析时使用：

- `cargo check -p bevy_recipe_editor -p content_tools`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File legacy/bevy/agent/open-editor.ps1 -Recipe <id>` 仅作为旧 Bevy 对照

Godot `CDC Agent Handoff` dock 会显示只读 `edit_plan`，用于确认 recipe 可编辑字段组、item / skill / unlock 影响和保存后 checklist；实际数据仍以 `data/recipes/*.json` 为权威。

## Output Expectations

- 修改了哪些材料、产出或条件
- 是否引入新的 item / skill / recipe 依赖
- 是否需要人工复核 unlock 链路
