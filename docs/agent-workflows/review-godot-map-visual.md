# Review Godot Map Visual Workflow

## Purpose

这个 workflow 负责 Godot 迁移路径下的地图空间结果复核，优先验证 Godot loader、地图摘要、overworld 引用、世界快照和生成场景链路。

## When To Use

- Agent 已修改 `data/maps/*.json`，并需要确认 Godot 侧能读取和生成场景。
- 需要替代旧 `review-map-visual.ps1` 的 Bevy editor 依赖做自动复核。
- 需要给出可复跑的 Godot map review 结果，而不是只看旧 Bevy editor。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map <id>`。
2. 脚本会先通过 Godot content CLI 输出地图定位、摘要、overworld 引用和 loader validate 结果。
3. 默认继续运行 Godot `World` 和 `Scene` smoke，确认世界快照与生成场景链路未断。
4. 如需进入 editor 复核，执行 `pwsh -NoProfile -File tools/agent/open-godot-editor.ps1 -Map <id>`，`CDC Agent Handoff` dock 会显示地图摘要、引用和 map review 区块。
5. 按脚本和 dock 输出检查 map id、size、level、entry points、object kinds、interaction targets、AI spawn 和 overworld 引用。
6. 若失败，先看对应 Godot CLI 或 smoke 输出，再回到 `data/maps/*.json` 或 `godot/scripts/world` 定位。

## Notes

- 当前 Godot map 复核入口先提供 editor dock 里的结构化摘要和引用预览，不打开旧 Bevy editor。
- 如只想看内容摘要而暂时不跑 world/scene smoke，可加 `-NoSmoke`。
- 旧 `review-map-visual.ps1` 保留为 Bevy 对照路径；Godot 迁移开发优先使用本 workflow。
