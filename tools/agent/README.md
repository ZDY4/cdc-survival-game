# Agent Tools

本目录收纳 repo-local agent workflow 的脚本入口。

Agent 不应把这些脚本当成“可选附加物”，而应优先把它们视为标准工作流的一部分。

## Discovery Rules

- 处理内容编辑、复核、editor 跳转时，先读本文件，再按需读 `docs/agent-workflows/*.md`。
- 若脚本支持 PowerShell help，先执行 `Get-Help tools/agent/<script>.ps1` 看参数和示例。
- 优先复用这里已有脚本，不要重复发明新的 editor 启动或 handoff 流程。

## Tools

### `open-editor.ps1`

用途：

- 打开或复用现有 Bevy editor，并自动定位到指定 `item` / `recipe` / `character` / `map`。

何时使用：

- 已经完成数据修改，需要进入 editor 做可视化复核或手工精修。
- 需要让 editor 直接切到具体目标，而不是手动在列表里查找。

示例：

```powershell
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Item 1001
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Recipe recipe_bandage_basic
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Character scavenger_maya
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Map forest
```

行为：

- 若对应 editor 最近处于活跃状态，会优先复用现有实例。
- 脚本会写 `tmp/editor_handoff/*.navigation.json` 让运行中的 editor 切换选中目标。
- 会 best-effort 尝试前置 editor 窗口；前置失败不影响 handoff。
- 若没有最近活跃实例，则直接启动对应 editor，并通过启动参数选中目标。

### `review-map-visual.ps1`

用途：

- 为地图改动提供标准化的视觉复核入口。

何时使用：

- `data/maps/*.json` 已被修改，需要在进入 `bevy_map_editor` 前先看摘要、引用和校验。
- 需要把“map 校验 + visual review”压成一个固定命令，而不是手动拼多条命令。

示例：

```powershell
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map forest
pwsh -NoProfile -File tools/agent/review-map-visual.ps1 -Map factory -NoOpenEditor
```

行为：

- 先在 `rust/` workspace 下串行执行：
  - `cargo run -q -p content_tools -- locate map <id>`
  - `cargo run -q -p content_tools -- summarize map <id>`
  - `cargo run -q -p content_tools -- references map <id>`
  - `cargo run -q -p content_tools -- validate map <id>`
- 然后输出固定 visual review checklist。
- 默认继续调用 `open-editor.ps1 -Map <id>` 打开或复用 `bevy_map_editor`。
- 若使用 `-NoOpenEditor`，则只输出 CLI 复核信息，不启动 editor。

## Maintenance Rule

- 新增脚本时，至少补齐：
  - 这个 README 的用途和示例
  - 脚本自身的 comment-based help
  - 对应的 `docs/agent-workflows/*.md`
