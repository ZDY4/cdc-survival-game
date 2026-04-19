# Agent Workflows

本目录定义仓库内 AI Agent 的内容修改主路径。

目标：

- 不再以 Bevy editor 内聊天窗口作为 AI 入口
- 让 Codex / OpenCode 一类 Agent 直接在仓库中读写数据
- 统一通过共享 Rust 层和后续 CLI 做校验、格式化、摘要和 editor 复核

## Workflow List

- `edit-item.md`
- `edit-recipe.md`
- `edit-character.md`
- `edit-map.md`
- `review-map-visual.md`

## General Rules

1. 先定位目标文件，再读相关依赖和约束，不要直接盲改。
2. 修改后必须跑最小校验；若当前仓库存在已知编译阻塞，需要在结果里明确说明。
3. 地图类改动默认要求再用 `bevy_map_editor` 做空间复核。
4. `item / recipe / character` 优先直接改数据文件，不要依赖 editor 内 AI 入口。
5. 不要在 editor 里重建新的 AI 聊天窗口或 provider 设置页。

## Current Validation Baseline

当前优先使用：

- `cargo run -p content_tools -- locate <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- validate <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- validate changed`
- `cargo run -p content_tools -- summarize <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- references <item|map> <id>`
- `cargo run -p content_tools -- format <item|recipe|character|map> <id>`
- `cargo run -p content_tools -- format changed`
- `cargo run -p content_tools -- diff-summary --path <file>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Item <id>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Map <id>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Character <id>`
- `pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map <id>`

保底编译基线：

- `cargo check -p game_editor -p bevy_item_editor -p bevy_recipe_editor -p bevy_map_editor -p content_tools`

## Editor Handoff

当修改已经完成，需要进入 Bevy editor 做可视化复核或手工精修时，统一使用：

- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Item <id>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Recipe <id>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Character <id>`
- `pwsh -NoProfile -File tools/agent/open-editor.ps1 -Map <id>`
- `pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map <id>`

当前 handoff 行为：

- 若对应 editor 最近处于活跃状态，会优先复用现有实例
- 脚本会把目标 id 写入 `tmp/editor_handoff/*.navigation.json`
- editor 会读取 handoff 请求并切换到目标记录
- 脚本会 best-effort 尝试前置该 editor 窗口；前置失败不影响选中请求
- 若没有最近活跃实例，则直接启动 editor，并通过启动参数选中目标

地图视觉复核辅助：

- `review-map-visual.ps1` 会先串行执行 `locate` / `summarize` / `references` / `validate`
- 随后输出固定的视觉复核 checklist
- 默认会继续调用 `open-editor.ps1 -Map <id>` 打开或复用 `bevy_map_editor`
