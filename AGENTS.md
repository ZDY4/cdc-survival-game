# AGENTS.md

本文件定义本仓库内 agent 的默认工作方式。只保留当前仍然有效的约束。

## 当前基线

- 本项目迁移期默认运行时和工具链基于 `Godot 4.6.3 + GDScript`。
- Godot 命令行入口固定使用 `D:\godot\godot.cmd`，工程目录为 `godot/`。
- `data/` 下 JSON 仍是当前内容输入源；Godot 数据层负责加载、校验、摘要、引用和安全写回。
- 旧 `rust/` 与 Bevy app 只作为行为差异分析、历史参考和迁移收尾前的对照基线，不再作为新增功能默认落点。
- 内容编辑器保持独立工具形态，不把编辑能力重新塞回游戏运行时。

## 架构边界

- 核心规则、状态计算、AI、寻路、战斗等逻辑放在 `godot/scripts/core/` 或 Godot 运行时装配层，不放在 UI、表现层或编辑器前端。
- 共享数据结构以 `data/` JSON 和 `godot/scripts/data/` 的 loader / validator / edit service 为准，不重复定义长期并存的第二套 schema。
- 纯规则与可复用校验优先放在 Godot 引擎无关的 `RefCounted` 模块；Godot 场景层负责运行时集成和空间表现相关能力。
- 编辑器可以依赖 Godot 数据层和核心层，但不应反向成为权威数据来源。
- 新功能默认只做一套长期实现；不要为了历史做法保留双写、镜像或平行规则实现。

## 代码组织

- 默认优先模块化实现，不要把新增功能持续堆进单个大文件。
- 新增功能前，先判断应落在哪个现有模块；若现有文件或模块已承担多种职责，应优先拆分后再继续扩写。
- 单个模块应尽量只负责一个明确能力；不要把不相干的类型、系统、命令、UI 事件处理、数据访问、序列化逻辑混放在同一文件中。
- `project.godot`、autoload、app 入口脚本只承担入口、装配、导出职责；具体业务逻辑放到独立模块。
- 避免创建无明确边界的 `utils.rs`、`common.rs`、`helpers.rs` 大杂烩文件；只有在职责清晰且被多个模块稳定复用时才抽公共模块。
- 模块拆分优先按职责和数据流组织，不按“先放一起，后面再说”处理；Godot 相关代码优先拆成 `app`、`core`、`data`、`world`、`ui`、`addons`、`tools` 等职责明确的模块。
- 若一个功能同时包含数据定义、规则计算、持久化、UI 展示，至少拆成两个层次；面向编辑器的改动，优先把“数据读写/校验”和“界面交互”分开。
- 一个文件一旦开始同时回答“数据是什么”“怎么计算”“怎么显示”“怎么保存”这几类问题，就说明已经该拆分。

## 注释规范

- 写代码时，应为关键逻辑、关键变量、关键函数补充简洁的中文注释，说明其业务意图、重要约束、边界条件或容易误改的原因；避免只复述代码字面含义的低价值注释。
- 写代码时，关键流程、关键状态变更、重要失败分支应补充可用于排查问题的日志，日志内容应包含必要上下文，例如资源 id、目标对象、动作类型、失败原因或关键参数；避免无上下文、不可行动或高频刷屏的日志。

## 文件规模约束

- 把文件大小和复杂度当作设计信号，不要默认接受持续膨胀的文件。
- 超过约 `300` 行的业务文件时，应主动评估是否继续拆分。
- 超过约 `500` 行且仍在继续新增业务逻辑时，默认应先拆分，再继续开发；除非该文件天然适合作为集中定义文件。
- 超过约 `8-10` 个顶级类型、函数组或系统入口的文件，默认说明职责过多，应考虑按主题拆开。
- 若本次任务正好修改到臃肿文件，应顺手做最小必要拆分，避免继续恶化。

## 目录职责

- `godot/project.godot`: Godot 4.6.3 工程入口。
- `godot/scripts/data`: 内容路径、JSON 加载、registry、校验、引用查询、格式化和安全编辑服务。
- `godot/scripts/core`: 引擎无关的公共规则与运行时逻辑，包括 simulation、移动、交互、战斗、经济、任务、对话、AI、视野和大地图。
- `godot/scripts/app`: Godot app 装配、headless runner、游戏入口和 player interaction controller。
- `godot/scripts/world`: 地图快照、场景生成、空间表现、雾战和 tile / object 渲染。
- `godot/scripts/ui`: HUD、背包、任务、对话、交易、容器等 UI snapshot、controller 和面板。
- `godot/scripts/tools`: Godot headless 校验、内容 CLI、smoke 和迁移期复核脚本。
- `godot/addons/cdc_game_editor`: Godot editor 插件、handoff、content browser、map preview 和专用编辑 dock。
- `data`: 当前内容权威输入源，迁移完成前不要与 `.tres` / `.res` 长期双写。
- `tools/agent`: repo-local agent workflow 标准入口，默认走 Godot 脚本。
- `rust` 和 `run_bevy_*.bat`: 旧 Rust/Bevy 实现与启动脚本，只在明确需要旧行为对照时使用。

## 编辑器约束

- 数据编辑、保存、校验尽量复用 `godot/scripts/data` 能力，不让编辑器前端各自维护一套独立长期数据格式。
- 强依赖 3D 场景、预览、空间交互的编辑能力放在 Godot editor 插件或 Godot 场景工具侧。
- 偏内容管理、表单、工作流、文本生产的能力优先收口到 Godot 数据层，再按需要接到专用 dock 或 headless tool。
- 需求不明确时，优先把新增能力放到 Godot 数据层或核心层，再接到具体 app 或编辑器；若旧 Rust/Bevy 实现与 Godot 迁移方向冲突，优先收口到 Godot，而不是继续扩散到旧消费端。
- 若一段逻辑既能做成共享规则库，也能直接写进 Godot node script，优先先抽共享规则，再做场景集成；开发时优先做“小模块组合”，不要做“大文件追加”。

## Agent 工具使用

- `tools/agent/` 下的脚本是 repo-local agent workflow 的标准工具入口；处理内容编辑复核时，优先查看 `tools/agent/README.md` 和 `docs/agent-workflows/*.md`，不要靠猜测脚本用途。
- 内容定位、摘要、引用、校验、格式化和 diff 摘要默认使用 `tools/agent/godot-content.ps1`。
- 需要打开或复用 Godot editor 并定位到指定目标时，优先使用 `tools/agent/open-godot-editor.ps1`，不要只告诉用户“手动打开 editor 再搜索”。
- 地图改动完成后，需要做空间结果复核时，优先使用 `tools/agent/review-godot-map-visual.ps1`；它会先串联 Godot map 摘要、引用、校验和 smoke，再提示进入 Godot editor 的 `CDC Map Preview` dock。
- 游戏运行时 smoke 默认使用 `tools/agent/test-godot-game.ps1`；旧 `test-bevy-game.ps1` 只在需要旧行为差异分析时使用。
- 旧 `open-editor.ps1`、`review-map-visual.ps1`、`test-bevy-game.ps1` 仅作为 Bevy 对照入口，不作为迁移开发默认路径。
- 若脚本已提供 PowerShell comment-based help，先用 `Get-Help tools/agent/<script>.ps1` 确认参数、示例和副作用，再执行。
- 新增 `tools/agent/` 脚本时，必须同时补这三处说明：脚本自身 help、`tools/agent/README.md`、相关 workflow 文档；不要只落脚本文件本体。

## Bug / Crash 排查

- 处理 bug、报错、回归或崩溃时，若仓库中存在相关运行日志，默认先查看对应 `logs/<app>/` 下最新且相关的日志文件，再决定复现和修复路径。
- 默认排查顺序：先识别受影响的 app 或工具，再查看最新相关日志并提取具体报错、panic、调用上下文或最后一批异常事件，最后再决定是继续复现、改代码还是补充信息；不要在没有证据时直接猜测根因。
- 若日志不足、日志已过期、或与当前问题无关，应明确说明，再继续做最小复现、代码定位或运行验证。
- 该规则主要适用于运行时 bug / crash / regression 排查；纯编译错误、类型错误、明显静态重构任务不强制要求先查日志。

## 验证与交付

- 不主动新增测试文件，除非用户明确要求；优先使用现有 Godot headless smoke、`godot-content.ps1`、`validate_all.gd`、已有运行入口或最小手动 smoke 进行验证。
- 旧 `cargo check` / Rust tests 仅在本次改动涉及旧 Rust/Bevy 对照实现时运行；Godot 迁移开发不应因为旧 workspace 存在而默认回到 Cargo 验证。
- 若无法验证，明确说明未验证项、原因和建议的下一步；若进行了模块拆分，应在交付说明中简要说明新的职责边界。
- 若本次修复依赖日志结论，交付时说明使用了哪个日志文件、观察到了什么关键信号、是否完成复现验证，以及结论主要来自日志、复现还是静态分析。
- 若改动涉及日志相关代码，应优先补充可行动的上下文信息，例如子系统名、资源 id、文件路径、命令或动作上下文、失败原因；避免只记录空泛报错。
- 每完成一个独立开发任务并通过必要验证后，应创建一次 Git commit；只暂存并提交与该任务直接相关的文件，避免混入无关改动或用户已有改动。Commit message 尽量使用简体中文，简洁说明本次变更的目的和范围。

## 禁止事项

- 不要把核心规则写回表现层、调试层或编辑器前端。
- 不要让旧 `Bevy` / `Rust` 路径继续承担新增功能或通用内容编辑 UI 的主职责。
- 不要让编辑器直接定义或漂移出共享 schema。
- 不要为了短期方便重复定义共享数据结构。
- 不要保留无必要的双实现或兼容层。

## 一句话原则

把 `规则`、`表现`、`编辑` 拆开，统一以 Godot 数据层和核心层为迁移后的权威。
