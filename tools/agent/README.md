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

- 打开或复用现有 Bevy editor，并自动定位到指定 `item` / `recipe` / `dialogue` / `quest` / `character` / `map`。

何时使用：

- 已经完成数据修改，需要进入 editor 做可视化复核或手工精修。
- 需要让 editor 直接切到具体目标，而不是手动在列表里查找。

示例：

```powershell
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Item 1001
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Recipe recipe_bandage_basic
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Dialogue trader_lao_wang
pwsh -NoProfile -File tools/agent/open-editor.ps1 -Quest zombie_hunter
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

- 为地图改动提供旧 Bevy 路径的标准化视觉复核入口。

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

### `review-godot-map-visual.ps1`

用途：

- 为地图改动提供 Godot 迁移路径下的标准化复核入口。

何时使用：

- `data/maps/*.json` 已被修改，需要验证 Godot loader、地图摘要、引用、世界快照和生成场景链路。
- 需要替代旧 `bevy_map_editor` 视觉复核依赖，优先走 Godot 工具链。

示例：

```powershell
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01
pwsh -NoProfile -File tools/agent/review-godot-map-visual.ps1 -Map survivor_outpost_01 -NoSmoke
```

行为：

- 先通过 `godot-content.ps1` 串行执行 `locate map`、`summarize map`、`references map` 和 `validate changed`。
- 默认继续调用 `test-godot-game.ps1 -Scenario World` 和 `test-godot-game.ps1 -Scenario Scene`。
- 输出 Godot map review checklist；当前不打开旧 Bevy editor。

### `godot-content.ps1`

用途：

- 通过 Godot headless content CLI 执行内容定位、摘要、引用和校验，作为 `content_tools` 的迁移替代入口。

何时使用：

- 需要在不进入 Rust workspace 的情况下检查 `data/` 内容。
- 需要验证 Godot loader 对当前内容的读取、摘要和引用结果。

示例：

```powershell
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command locate -Kind item -Id 1006
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command summarize -Kind map -Id survivor_outpost_01
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command references -Kind item -Id 1006
pwsh -NoProfile -File tools/agent/godot-content.ps1 -Command validate -Kind changed
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script res://scripts/tools/content_cli.gd`。
- 当前覆盖 `locate` / `summarize` / `references` / `validate changed`。
- `references` 当前覆盖 `item` 和 `map`，与旧 `content_tools` 的主路径保持一致。

### `test-bevy-game.ps1`

用途：

- 运行 Bevy game 的 agent smoke 测试，验证可自动进入确定的 gameplay runtime 并检查关键交互链路。

何时使用：

- 修改 `bevy_debug_viewer` 输入、picking、交互菜单、运行时 prompt 或世界交互 UI 后。
- 需要确认 agent 可以用一条命令复核“右键可交互目标会打开交互菜单”。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-bevy-game.ps1
pwsh -NoProfile -File tools/agent/test-bevy-game.ps1 -Scenario WorldInteractionMenu
```

行为：

- 在 `rust/` workspace 下运行目标 `cargo test`。
- 当前 `WorldInteractionMenu` 场景会构造固定 gameplay runtime、选中玩家、定位 pickup 目标，并断言交互菜单和 prompt 正常。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/bevy_game/<timestamp>/`。

### `test-godot-game.ps1`

用途：

- 运行 Godot runtime / game 的 agent smoke 测试，作为 Bevy game smoke 的迁移替代入口。

何时使用：

- 修改 Godot runtime、世界生成、交互、UI、任务、战斗或存档后。
- 需要一条命令复核当前 Godot 可玩闭环。

示例：

```powershell
pwsh -NoProfile -File tools/agent/test-godot-game.ps1
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Interaction
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools/agent/test-godot-game.ps1 -Scenario Save
```

行为：

- 固定调用 `D:\godot\godot.cmd --headless --path godot --script <smoke>`。
- 默认 `-Scenario All` 会运行所有已迁移 Godot smoke。
- 输出 console log 和 result JSON 到 `.local/agent-smoke/godot_game/<timestamp>/`。

## Maintenance Rule

- 新增脚本时，至少补齐：
  - 这个 README 的用途和示例
  - 脚本自身的 comment-based help
  - 对应的 `docs/agent-workflows/*.md`
