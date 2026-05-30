# Review Godot Map Visual Workflow

## Purpose

这个 workflow 负责 Godot 地图空间结果复核，优先验证地图摘要、overworld 引用、世界快照、生成场景链路和对应 Godot map scene 是否可用。

## When To Use

- Agent 已修改 `godot/scenes/maps/*.tscn` 或地图兼容数据，并需要确认 Godot 侧能读取和生成场景。
- 需要给出可复跑的 Godot map review 结果。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map <id>`。
2. 脚本会先通过 Godot content CLI 输出地图定位、摘要、overworld 引用和 loader validate 结果；地图定位和摘要读取 `godot/scenes/maps/*.tscn`，引用和兼容校验仍覆盖迁移期 `data/maps` 备份。
3. 默认继续运行目标地图的 `map_preview_smoke.gd`，再运行 Godot `World` 和 `Scene` smoke；前者验证目标地图 review dock 和 `.tscn` scene 入口，后两者作为默认启动场景的全局 runtime 回归。
4. 如需进入 editor 复核，执行 `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map <id>`，`CDC Agent Handoff` dock 会显示地图摘要、引用和 map review 区块，`CDC Map Review` dock 可显示预览、checklist 并打开对应 `.tscn` 场景。
5. 按脚本和 dock 输出检查 map id、size、level、entry points、object kinds、interaction targets、AI spawn 和 overworld 引用。
6. 若失败，先看对应 Godot CLI 或 smoke 输出，再回到 `godot/scenes/maps/*.tscn`、兼容数据或 `godot/scripts/world` 定位。

## Notes

- 当前 Godot map 复核入口提供 editor dock 里的结构化摘要、引用预览、地图预览和打开 `.tscn` 场景的入口；地图布局编辑交给 Godot 场景编辑器，复核摘要来自 scene 导出的 map definition。
- 如只想看内容摘要而暂时不跑 world/scene smoke，可加 `-NoSmoke`。
