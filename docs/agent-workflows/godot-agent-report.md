# Godot Agent Report Workflow

## Purpose

这个 workflow 负责生成 agent 可读的 Godot 脚本和 scene 结构报告，便于快速理解工程结构、地图 scene、脚本依赖和资源实例关系。

## When To Use

- 需要快速查看 `.gd` 文件的 `class_name`、`extends`、preload 和 const 分布。
- 需要快速查看 `godot/scenes/**/*.tscn` 的节点层级、脚本引用和实例资源引用。
- 修改地图 scene、editor dock、world renderer 或脚本结构前，需要先整理上下文。

## Expected Steps

1. 执行 `pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scripts` 生成脚本摘要。
2. 执行 `pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind Scenes` 生成 scene 摘要。
3. 如需源码汇总，执行 `pwsh -NoProfile -File tools/agent/godot-agent-report.ps1 -Kind All -IncludeSource`。
4. 打开 `.local/agent-reports/godot/<timestamp>/result.json` 和对应 Markdown 摘要查看输出。

## Notes

- 报告只写入 `.local/agent-reports/godot`，不要写入 `godot/` 工程目录。
- `Scenes` 优先覆盖 `godot/scenes/**/*.tscn` / `.scn`，适合检查地图 scene 中的节点、脚本和实例资源。
- 这个工具只迁移 `CODEXVault_GODOT` 中的汇总思路，不迁入其 EditorScript 临时输出文件方案。
