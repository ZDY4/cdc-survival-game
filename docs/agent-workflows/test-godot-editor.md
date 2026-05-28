# Test Godot Editor Workflow

## Purpose

这个 workflow 负责 Godot editor 侧的 agent smoke 复核，验证迁移后的 handoff、content browser、map preview 和共享编辑服务能在 headless 环境中跑通。

## When To Use

- 修改 `godot/addons/cdc_game_editor` 后。
- 修改 `godot/scripts/data/content_edit_service.gd`、map edit service 或 editor presenter 后。
- 需要替代旧 `legacy/bevy/agent/smoke_bevy_editors.ps1` 的 Bevy editor 聚合 smoke。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1`。
2. 默认场景 `All` 会运行当前所有 Godot editor headless smoke。
3. 检查脚本输出的 result JSON 和各场景 console log 路径。
4. 若失败，先看对应场景 `.log` 中的 Godot 编译错误、断言或 runtime error，再回到 Godot addon / data service 定位。

## Notes

- 当前 smoke 全部通过 `D:\godot\godot.cmd --headless --path godot --script ...` 执行，不打开旧 Bevy editor。
- 单场景复核可使用 `-Scenario EditorHandoff`、`-Scenario ContentBrowser`、`-Scenario MapPreview`、`-Scenario ContentEdit`、`-Scenario MapEdit`。
- 旧 `legacy/bevy/agent/smoke_bevy_editors.ps1` 仅作为行为差异对照；迁移开发优先运行本 workflow。
