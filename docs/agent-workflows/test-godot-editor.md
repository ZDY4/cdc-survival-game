# Test Godot Editor Workflow

## Purpose

这个 workflow 负责 Godot editor 侧的 agent smoke 复核，验证 handoff、独立内容编辑窗口、map review、map tile palette 和共享编辑服务能在 headless 环境中跑通。

## When To Use

- 修改 `godot/addons/cdc_game_editor` 后。
- 修改 `godot/scripts/data/content_edit_service.gd` 或 editor presenter 后。
- 需要一条命令复核 Godot editor 侧 handoff、内容编辑窗口、地图复核、地图块 palette 和编辑服务。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/test-godot-editor.ps1`。
2. 默认场景 `All` 会运行当前所有 Godot editor headless smoke。
3. 检查脚本输出的 result JSON 和各场景 console log 路径。
4. 若失败，先看对应场景 `.log` 中的 Godot 编译错误、断言或 runtime error，再回到 Godot addon / data service 定位。

## Notes

- 当前 smoke 全部通过 `D:\godot\godot.cmd --headless --path godot --script ...` 执行。
- 单场景复核可使用 `-Scenario EditorHandoff`、`-Scenario ContentEditors`、`-Scenario MapReview`、`-Scenario MapTilePalette`、`-Scenario ContentEdit`。
- `MapTilePalette` 在临时 map scene 中测试 palette 加载、建筑 tile 放置、prop wrapper 创建、marker 创建、旋转和删除，不写入真实地图场景。
