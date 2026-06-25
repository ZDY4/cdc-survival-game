# Test Godot Static Workflow

## Purpose

这个 workflow 负责 Godot 静态验证，覆盖 import/cache 预热和 GDScript parse/check-only 检查。它吸收 `CODEXVault_GODOT` 的 headless 验证思路，但保持本仓库的 Windows + GDScript 工具链。

## When To Use

- 修改 `.gd`、`.tscn`、autoload、`project.godot` 或资源引用后。
- Godot smoke 失败疑似来自 import cache、script-class cache 或 GDScript 解析阶段时。
- 需要先跑基础静态验证，再决定是否继续跑 game/editor smoke 时。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/test-godot-static.ps1`。
2. 需要拆开复核时，分别执行 `-Scenario Import` 和 `-Scenario CheckOnly`。
3. 检查脚本输出的 result JSON 和各场景 console log 路径。
4. 若失败，先看对应 `.log` 中的 Godot import、resource 或 parse 错误，再回到对应 `.gd` / `.tscn` / project 配置定位。

## Notes

- Godot 命令解析优先级为：显式 `-Godot` 参数、环境变量 `GODOT`、PATH 中的 `godot` / `godot.exe` / `godot.cmd`、`D:\godot\godot.cmd`。
- `Import` 调用解析出的 Godot 命令执行 `--headless --editor --import --quit --path godot`。
- `CheckOnly` 遍历 `godot/**/*.gd`，逐个调用解析出的 Godot 命令执行 `--headless --path godot --check-only --script res://...`。
- 输出写入 `.local/agent-smoke/godot_static/<timestamp>/`。
- 不包含 Godot Mono / .NET、Linux setup、pre-commit 或 CI 安装逻辑。
