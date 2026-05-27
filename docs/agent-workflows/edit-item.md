# Edit Item Workflow

## Scope

适用于：

- 修改现有 item 定义
- 新增 item
- 调整 item 属性、片段、掉落相关字段

## Primary Files

- `data/items/*.json`

常见依赖：

- `data/recipes/*.json`
- `data/characters/*.json`
- `data/json/effects/*`

## Agent Steps

1. 定位目标 item 文件；若不存在，先确认新建文件名和目标 id。
2. 先读取 item 摘要，再检查是否被 recipe、角色掉落、地图拾取或其他 item 片段引用。
3. 修改 JSON。
4. 跑最小校验。
5. 总结变更影响面。

## Validation

当前优先使用：

- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind item -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind item -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind item -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind item -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind item -Id <id>`

旧 Rust/Bevy 对照基线仅在需要差异分析时使用：

- `cargo check -p bevy_item_editor -p content_tools`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Item <id>`

Godot `CDC Agent Handoff` dock 会显示只读 `edit_plan`，用于确认可编辑字段组、引用影响和保存后 checklist；实际数据仍以 `data/items/*.json` 为权威。

## Output Expectations

- 修改了哪些字段
- 是否新增或变更 id
- 是否存在引用联动风险
- 是否需要再进入 editor 复核模型/预览
