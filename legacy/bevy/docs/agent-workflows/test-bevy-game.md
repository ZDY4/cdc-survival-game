# Test Bevy Game Workflow Legacy

## Purpose

这个 workflow 是旧 Bevy game 侧的 agent smoke 对照入口。Godot 迁移开发默认使用 `test-godot-game.md` 和 `tools/agent/test-godot-game.ps1`。

## When To Use

- 修改 `bevy_debug_viewer` 的鼠标输入、交互菜单、picking 或世界交互 UI 后。
- 需要旧 Bevy `WorldInteractionMenu` 行为差异对照。
- 不作为迁移开发的默认验收路径；Godot 等价覆盖见 `test-godot-game.ps1 -Scenario BevyEquivalence`。

## Expected Steps

1. 默认先执行 `pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario BevyEquivalence`。
2. 只有需要旧实现对照时，再执行 `pwsh -NoProfile -File legacy/bevy/agent/test-bevy-game.ps1`。
3. 默认场景 `WorldInteractionMenu` 会运行 `agent_smoke_right_click_pickup_opens_interaction_menu`。
4. 检查脚本输出的 result JSON 和 console log 路径。
5. 若失败，先看 console log 中的断言、panic 或编译错误，再回到 Rust 代码定位。

## Notes

- 当前 smoke 是确定性的 in-process gameplay 测试，不依赖窗口焦点、屏幕坐标或 OCR。
- 旧 Bevy smoke 目标已由 Godot `BevyEquivalence` 场景输出机器可读覆盖映射。
- 如后续增加真实窗口级 smoke，应优先接入 Godot `test-godot-game.ps1`，旧 Bevy 脚本只保留对照用途。
