# AGENTS.md

本文件定义本仓库内 agent 的默认工作方式。

## 当前基线

- 运行时和工具链基于 `Godot 4.6.3 + GDScript`。
- Godot 命令行入口固定使用 `D:\godot\godot.cmd`，工程目录为 `godot/`。
- 地图主来源为 `godot/scenes/maps/*.tscn`，后续地图布局、入口点和地图对象按 Godot scene 工作流维护；`data/maps/*.json` 只作为迁移期兼容备份。
- 非地图内容仍以 `data/` 下 JSON 为当前权威输入源；Godot 数据层负责加载、校验、摘要、引用查询、格式化和安全写回。
- 玩家运行时不承载内容编辑 UI；内容编辑能力放在 Godot editor 插件、headless tool 或独立脚本中。

## 架构边界

- 新增能力先判断权威落点：内容格式进 `data` / `godot/scripts/data`，玩法规则进 `godot/scripts/core`，启动编排进 `godot/scripts/app`，画面表现进 `godot/scripts/world` 或 `godot/scripts/ui`，编辑体验进 `godot/addons/cdc_game_editor`。
- 读写非地图 `data/` 内容时，统一走 `godot/scripts/data`；不要在 UI、editor dock 或 smoke 脚本里手写第二套 JSON 解析、路径规则或保存逻辑。
- 读写地图布局时，优先操作 `godot/scenes/maps/*.tscn` 中的 `MapSceneRoot`、`MapEntryPointNode` 和 `MapObjectNode`；不要新增长期 JSON -> scene 转换步骤。
- 玩法结果由 `godot/scripts/core` 计算；场景、UI 和 editor 只提交输入、展示结果或发起工具调用，不直接决定移动、战斗、任务、交易、背包等业务结果。
- `godot/scripts/app` 只负责启动流程、存档装配、输入转发和各核心模块串联；不要把具体战斗、任务、经济规则写进 app controller。
- `godot/scripts/world` 只负责把地图和快照表现成场景对象；不要在渲染脚本里改变存档、任务、背包或角色属性。
- `godot/scripts/ui` 只负责面板状态、按钮事件和 snapshot 展示；业务判断先落到 core/data，再由 UI 调用。
- `godot/addons/cdc_game_editor` 可以做表单、地图复核和 handoff；非地图内容保存必须调用 data edit service，并通过 validator 后写回。

## 目录职责

- `godot/project.godot`: Godot 工程入口。
- `godot/scripts/data`: 内容路径、JSON 加载、registry、校验、引用查询、格式化和安全编辑服务。
- `godot/scripts/core`: 引擎无关的玩法规则与运行时逻辑。
- `godot/scripts/app`: app 装配、headless runner、启动流程、玩家交互 controller。
- `godot/scripts/world`: 地图快照、场景生成、空间表现、雾战、tile / object 渲染。
- `godot/scenes/maps`: Godot 地图场景，承载 map id、尺寸、入口点、地图对象、footprint 和对象 props，是后续地图开发主入口。
- `godot/scripts/ui`: HUD、背包、任务、对话、交易、容器等 UI snapshot、controller 和面板。
- `godot/scripts/tools`: Godot headless 校验、内容 CLI、smoke 和复核脚本。
- `godot/addons/cdc_game_editor`: 当前 Godot editor 插件，包括 handoff、content browser、map review 和编辑 dock。
- `data`: 非地图内容权威输入源；`data/maps` 是迁移期兼容备份，不再作为新地图开发主入口。
- `tools/agent`: repo-local agent workflow 标准入口，默认调用 Godot 工具链。
- 根目录 `addons/` 若只包含旧备份或残留文件，不作为当前 Godot 插件来源。

## 代码组织

- 默认按职责拆分模块，不把新增功能持续堆进单个大文件。
- `project.godot`、autoload、app 入口脚本只承担入口、装配和导出职责；业务逻辑放到独立模块。
- 避免创建无明确边界的 `utils.gd`、`common.gd`、`helpers.gd` 大杂烩；只有职责清晰且稳定复用时才抽公共模块。
- 一个功能同时包含数据读写、规则计算、持久化、UI 展示时，至少拆成数据/规则层和界面/装配层。
- 超过约 `300` 行的业务文件应评估是否拆分；超过约 `500` 行且还要新增业务逻辑时，默认先做最小必要拆分。
- 修改臃肿文件时，只有在本任务直接触及且能保持小范围时才做职责切分。

## 注释与日志

- 非显然业务规则、跨层边界、重要约束或容易误改的逻辑应补充简洁中文注释。
- 避免只复述代码字面含义的低价值注释。
- 关键流程、关键状态变更、重要失败分支应补充可排查的日志，包含资源 id、目标对象、动作类型、失败原因或关键参数。
- 避免无上下文、不可行动或高频刷屏的日志。

## Agent 工具使用

- 处理内容编辑、定位、摘要、引用、格式化、校验时，先看 `tools/agent/README.md`；涉及具体流程时再看 `docs/agent-workflows/*.md`。
- 内容 CLI 默认使用 `tools/agent/godot-content.ps1`。
- 需要打开或复用 Godot editor 并定位目标时，优先使用 `tools/agent/open-godot-editor.ps1`。
- 地图改动后的空间复核优先使用 `tools/agent/review-godot-map-visual.ps1`；需要人工查看或精修时打开对应 Godot map scene，并用 `CDC Map Review` dock 查看复核信息。
- 游戏运行时 smoke 默认使用 `tools/agent/test-godot-game.ps1`。
- Editor 插件和编辑服务 smoke 默认使用 `tools/agent/test-godot-editor.ps1`。
- 若脚本提供 PowerShell comment-based help，先用 `Get-Help tools/agent/<script>.ps1` 确认参数、示例和副作用。
- 新增 `tools/agent/` 脚本时，同时更新脚本自身 help、`tools/agent/README.md` 和相关 workflow 文档。

## Bug / Crash 排查

- 处理 bug、报错、回归或崩溃时，先识别受影响的 app、tool、scene 或 smoke。
- 若有相关日志，先查看 `logs/` 下最新相关文件，或查看 `tools/agent` / Godot headless smoke 输出，再决定复现和修复路径。
- 日志不足、过期或无关时，应说明这一点，然后继续做最小复现、代码定位或运行验证。
- 纯语法错误、静态类型错误、明显重构任务不强制先查日志。

## 验证与交付

- 不主动新增测试文件，除非用户明确要求；默认用现有 Godot headless smoke、`godot-content.ps1`、`validate_all.gd`、已有运行入口或最小手动 smoke 验证。
- 若无法验证，交付时明确说明未验证项、原因和建议下一步。
- 若修复依赖日志结论，交付时说明使用了哪个日志文件或 smoke 输出、观察到的关键信号、是否完成复现验证。
- 完成涉及文件修改的独立开发任务并通过必要验证后，默认创建一次 Git commit；只暂存并提交与本任务直接相关的文件。纯审查、答疑或探索任务不提交；用户明确要求不提交时也不提交。
- Commit message 使用简体中文，简洁说明变更目的和范围。

## 禁止事项

- 不要绕过 `godot/scripts/data` 或 `godot/scripts/core`，把内容读写、共享 schema 或核心规则复制到 UI、场景表现、调试层或 editor dock。
- 不要保留无必要的双实现、兼容层或重复共享数据结构。
- 不要把根目录旧 `addons/` 残留当作当前 Godot 插件实现。

## 一句话原则

把 `内容读写`、`玩法结果`、`场景表现`、`编辑体验` 拆开，统一以 Godot 数据层和核心层为权威。
