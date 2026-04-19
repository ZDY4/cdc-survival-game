# Review Map Visual Workflow

## Purpose

这个 workflow 不负责主编辑，只负责地图空间结果复核。

## When To Use

- Agent 已修改 `data/maps/*.json`
- 需要确认空间布局、入口、对象位置、可视化效果
- 需要在 `bevy_map_editor` 中检查场景是否符合预期

## Expected Steps

1. 先执行 `pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map <id>`。
2. 脚本会先输出地图定位、摘要、overworld 引用和当前 validate 结果。
3. 脚本默认会继续打开或复用 `bevy_map_editor`，并选中目标地图。
4. 在 editor 中检查当前 level、入口点、关键对象、诊断面板、阻挡和明显不可达路径。
5. 如果发现问题，返回仓库数据继续修改，而不是在 editor 内走聊天修复。
6. 复核结束后给出结论：
   - 通过
   - 需继续调整
   - 存在高风险项

## Notes

- `bevy_map_editor` 现在只承担查看、保存、校验和空间复核，不再承担 AI proposal 入口。
- 如只想看 CLI 摘要而暂时不打开 editor，可加 `-NoOpenEditor`。
