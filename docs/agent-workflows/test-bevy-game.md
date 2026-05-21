# Test Bevy Game Workflow

## Purpose

这个 workflow 负责 Bevy game 侧的 agent smoke 复核，优先验证输入、picking、交互 prompt 和 UI 状态是否能在确定场景中串起来。

## When To Use

- 修改 `bevy_debug_viewer` 的鼠标输入、交互菜单、picking 或世界交互 UI 后。
- 修改共享交互规则后，需要确认玩家端右键菜单仍能打开。
- 需要 agent 自己给出可复跑的 game smoke 结果，而不是只做人工窗口检查。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/test-bevy-game.ps1`。
2. 默认场景 `WorldInteractionMenu` 会运行 `agent_smoke_right_click_pickup_opens_interaction_menu`。
3. 检查脚本输出的 result JSON 和 console log 路径。
4. 若失败，先看 console log 中的断言、panic 或编译错误，再回到 Rust 代码定位。

## Notes

- 当前 smoke 是确定性的 in-process gameplay 测试，不依赖窗口焦点、屏幕坐标或 OCR。
- 如后续增加真实窗口级 smoke，应继续复用本脚本作为统一入口，而不是新增分散命令。
