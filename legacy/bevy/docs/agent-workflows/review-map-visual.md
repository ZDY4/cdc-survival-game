# Review Map Visual Workflow

## Purpose

这个 workflow 是旧 Bevy 地图空间复核入口，只在需要行为差异对照时使用。
Godot 迁移开发默认使用 `review-godot-map-visual.md` 和 `tools/agent/review-godot-map-visual.ps1`。

## When To Use

- Godot 复核结果与旧实现疑似不一致，需要旧 `bevy_map_editor` 做行为对照。
- 需要确认旧 Bevy 地图预览仍能打开目标地图。
- 不作为迁移开发的默认验收路径。

## Expected Steps

1. 默认先执行 `pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map <id>`。
2. 只有需要旧实现对照时，再执行 `pwsh -NoProfile -File legacy/bevy/agent/review-map-visual.ps1 -Map <id>`。
3. 旧脚本会先输出地图定位、摘要、overworld 引用和当前 validate 结果。
4. 旧脚本默认会继续打开或复用 `bevy_map_editor`，并选中目标地图。
5. 在 editor 中检查当前 level、入口点、关键对象、诊断面板、阻挡和明显不可达路径。
6. 如果发现问题，返回仓库数据继续修改，而不是在 editor 内走聊天修复。
7. 复核结束后给出结论：
   - 通过
   - 需继续调整
   - 存在高风险项

## Notes

- `bevy_map_editor` 现在只承担旧实现查看、保存、校验和空间复核对照，不再承担迁移默认复核或 AI proposal 入口。
- 如只想看 CLI 摘要而暂时不打开 editor，可加 `-NoOpenEditor`。
