# Test Godot Game Workflow

## Purpose

这个 workflow 负责 Godot game 侧的 agent smoke 复核，优先验证迁移后的 headless runner、runtime、世界生成、交互、UI、任务、战斗和存档闭环。

## When To Use

- 修改 `godot/scripts/core`、`godot/scripts/world`、`godot/scripts/ui`、`godot/scenes/game` 或 `godot/assets/shaders` 后。
- 修改共享 `data/` 内容后，需要确认 Godot loader 和 runtime 仍能跑通。
- 需要 agent 自己给出可复跑的 Godot game smoke 结果，而不是只做人工窗口检查。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/test-godot-game.ps1`。
2. 默认场景 `All` 会运行当前所有 Godot headless smoke。
3. 检查脚本输出的 result JSON 和各场景 console log 路径。
4. 若失败，先看对应场景 `.log` 中的 Godot 编译错误、断言或 runtime error，再回到 Godot 脚本定位。

## Notes

- 当前 smoke 全部通过 `D:\godot\godot.cmd --headless --path godot --script ...` 执行。
- `HeadlessNewGame` 和 `HeadlessWorld` 通过 `godot/scripts/app/headless_runner.gd` 覆盖迁移后的 Bevy server/headless 替代入口。
- 单场景复核可使用 `-Scenario HeadlessNewGame`、`-Scenario HeadlessWorld`、`-Scenario Runtime`、`-Scenario ContentCLI`、`-Scenario ContentEdit`、`-Scenario EditorHandoff`、`-Scenario EditorBrowser`、`-Scenario FogShader`、`-Scenario Overworld`、`-Scenario Movement`、`-Scenario Interaction`、`-Scenario DialogueAction`、`-Scenario Combat`、`-Scenario ContainerUI`、`-Scenario Equipment`、`-Scenario Crafting`、`-Scenario Save` 等。
- Bevy smoke 仅作为旧客户端行为对照；迁移开发优先运行本 workflow。
