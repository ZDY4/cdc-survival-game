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
- `godot/resources/world_tiles/**/*.tres`
- `data/world_tiles/*.json`（迁移备份 / 外部工具兼容输入）
- `data/characters/*.json`

## Agent Steps

1. 定位目标 map scene。
2. 先读取地图摘要、关键入口和当前校验状态；地图定位和摘要应来自 `godot/scenes/maps/*.tscn`。
3. 修改 Godot `.tscn` 场景中的地图布局、入口点或对象节点。
4. 修改 tile / prop prototype 时，以 `godot/resources/world_tiles/**/*.tres` 为权威源；批量从 JSON 同步时运行 `world_tile_resource_migration.gd`。
5. 跑最小校验。
6. 输出本次操作摘要。
7. 默认要求再用 Godot map review 入口做空间复核。

## Validation

当前优先使用：

- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command format -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind map -Id <id>`
- `pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map <id>`
- `& $env:GODOT --headless --path godot --script res://scripts/tools/world_tile_resource_validate.gd`

如需进入 editor 复核或手工精修：

- `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map <id>`

Godot editor 当前能力：

- `CDC Map Review` dock 可加载地图预览、map review checklist，并打开对应 `.tscn` 场景。
- `CDC Map Tile Palette` 优先读取 `res://resources/world_tiles/palettes/default_world_tile_palette.tres`；Resource 缺失时才回退到 `data/world_tiles/*.json`。
- 地图对象、入口点、可视节点和布局应在 Godot 场景编辑器中维护。
- `locate map`、`summarize map`、`CDC Agent Handoff` 和 `CDC Map Review` 都应读取 Godot map scene 导出的定义。
- `data/maps/*.json` 只作为兼容备份，不作为新地图编辑主入口。
- `data/world_tiles/*.json` 只作为迁移备份或外部工具兼容输入；新增 tile 通常只需新增 `.tres` 和对应 glTF 资源。

## Review Policy

地图改动默认不是“改完即结束”。

必须明确说明：

- 改了哪些对象/格子/入口
- 是否影响 selected map 的可达性或诊断
- 是否已运行 `review-godot-map-visual.ps1`
