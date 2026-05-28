# Edit Map Workflow

## Scope

适用于：

- 修改现有地图
- 新增地图
- 调整格子、对象、入口、层级、AI spawn 相关配置

## Primary Files

- `godot/scenes/maps/*.tscn`

常见依赖：

- `godot/scripts/world/map_scene_root.gd`
- `godot/scripts/world/map_entry_point_node.gd`
- `godot/scripts/world/map_object_node.gd`
- `data/overworld/*.json`
- `data/world_tiles/*.json`
- `data/characters/*.json`

## Agent Steps

1. 定位目标 map scene。
2. 先读取地图摘要、关键入口和当前校验状态。
3. 修改 Godot `.tscn` 场景中的地图布局、入口点或对象节点。
4. 跑最小校验。
5. 输出本次操作摘要。
6. 默认要求再用 Godot map review 入口做空间复核。

## Validation

当前优先使用：

- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map <id>`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map <id>`

Godot editor 当前能力：

- `CDC Map Review` dock 可加载地图预览、map review checklist，并打开对应 `.tscn` 场景。
- 地图对象、入口点、可视节点和布局应在 Godot 场景编辑器中维护。
- `data/maps/*.json` 只作为兼容备份，不作为新地图编辑主入口。

## Review Policy

地图改动默认不是“改完即结束”。

必须明确说明：

- 改了哪些对象/格子/入口
- 是否影响 selected map 的可达性或诊断
- 是否已运行 `review-godot-map-visual.ps1`
