# Godot 风格应用层重构计划

## 目标

将当前偏“集中式 app controller”的运行时结构，逐步重构为更符合 Godot 项目开发范式的场景树和节点职责模型。

重点不是简单拆小文件，而是让 `GameApp` 从承载启动、输入、世界刷新、UI 编排、debug、smoke 适配的全能脚本，收敛为薄的根节点；让世界、UI、输入、debug 和运行时刷新分别由明确的 scene / controller 负责。

## 当前执行状态

截至 2026-06-10，计划已开始执行，但尚未完成“薄根节点”终态。

已完成或基本收敛：

- startup request 和 new/continue runtime 构建已抽到 `godot/scripts/app/controllers/runtime_boot_controller.gd`。
- debug console 命令执行和 debug overlay mode 状态已抽到 `godot/scripts/app/controllers/debug_runtime_controller.gd`。
- HUD 运行时刷新已通过 `hud_controller.apply_runtime_snapshot()` 和 `input_blocker_snapshot()` 收敛为 facade。
- 顶层输入分发已抽到 `godot/scripts/app/controllers/game_input_router.gd`。
- 世界表现入口已抽到 `godot/scripts/world/world_root.gd`，`GameApp` 主要调用 WorldRoot 接口。
- runtime refresh / world snapshot 构建已抽到 `godot/scripts/app/controllers/runtime_refresh_controller.gd`。
- world action presenter、queue、pending UI 和 final refresh 状态已抽到 `godot/scripts/app/controllers/world_action_flow_controller.gd`。
- 运行时性能统计已抽到 `godot/scripts/app/controllers/runtime_performance_tracker.gd`。
- observe mode、auto tick 和 info panel 状态已抽到 `godot/scripts/app/controllers/runtime_control_state_controller.gd`。
- map level、focused actor 和视图导航状态已抽到 `godot/scripts/app/controllers/runtime_view_state_controller.gd`。
- 玩家命令 authority audit 已抽到 `godot/scripts/app/controllers/player_command_authority_audit.gd`。
- AI debug snapshot 构建已抽到 `godot/scripts/app/controllers/ai_debug_snapshot_builder.gd`。
- world time snapshot 格式化已抽到 `godot/scripts/app/controllers/world_time_snapshot_builder.gd`。
- 背包、容器、交易和角色面板的运行时反馈状态已抽到 `godot/scripts/app/controllers/ui_feedback_state_controller.gd`，`GameApp.active_*_feedback` 仅作为 smoke / tool 兼容属性保留。
- skill targeting 状态、preview 记录、confirm/cancel 状态转换和 skill activation targeting 解析已抽到 `godot/scripts/app/controllers/skill_targeting_controller.gd`，`GameApp.active_skill_targeting` / `active_skill_target_preview` 仅作为兼容属性保留。
- crafting queue latest result、pending cancel feedback、queue 标准化和 queue summary 已抽到 `godot/scripts/app/controllers/crafting_feedback_controller.gd`，`GameApp.latest_*_crafting_result` 仅作为兼容属性保留。
- tooltip layer 和 drag preview layer 的节点创建、样式、显示/隐藏和 render snapshot 已抽到 `godot/scripts/app/controllers/ui_overlay_render_controller.gd`，并由 `HudRoot` 持有；`GameApp` 仅保留兼容 facade。
- tooltip source 解析、tooltip snapshot 和 tooltip visual placement 计算已抽到 `godot/scripts/app/controllers/tooltip_snapshot_controller.gd`，`GameApp.hover_tooltip_snapshot()` 仅作为兼容 facade。
- drag source、payload、preview 文案、preview 尺寸和 drag state 组装已抽到 `godot/scripts/app/controllers/drag_snapshot_controller.gd`。
- hotbar、observe hotbar、equipment、inventory action、container 和 trade 的 drag hover target / acceptance 已抽到 `godot/scripts/app/controllers/drag_hover_target_controller.gd`，`GameApp` 只保留 `drag_state_snapshot()` 兼容 facade 和 reason 文案补全。
- gameplay input blocker、modal/context menu event、close priority 和 UI layer stack 组装已抽到 `godot/scripts/app/controllers/ui_blocker_state_controller.gd`；`GameApp` 只保留从 HUD / panel 节点读取当前状态的 facade。
- 容器 take / store / transfer / close 玩家动作 facade 已抽到 `godot/scripts/app/controllers/container_action_controller.gd`；背包 drop / use / deconstruct / split / reorder 玩家动作 facade 已抽到 `godot/scripts/app/controllers/inventory_action_controller.gd`；交易 buy / sell / cart 玩家动作 facade 已抽到 `godot/scripts/app/controllers/trade_action_controller.gd`；装备 equip / unequip / reload 和属性点 facade 已抽到 `godot/scripts/app/controllers/character_action_controller.gd`；技能 learn / bind / hotbar group / hotbar use / runtime target confirm facade 已抽到 `godot/scripts/app/controllers/skill_action_controller.gd`。
- 制作配方提交、制作队列推进、等待后续队列恢复、pending crafting 取消和 queue snapshot facade 已抽到 `godot/scripts/app/controllers/crafting_action_controller.gd`；`GameApp` 只保留 smoke / UI 兼容入口和刷新执行。
- 任务 turn-in 和地图面板进入 overworld location 的 action facade 已抽到 `godot/scripts/app/controllers/world_panel_action_controller.gd`；`GameApp` 只保留兼容入口、world rebuild 和刷新执行。
- 对话选择、无选项继续和关闭对话的 core-service 调用已抽到 `godot/scripts/app/controllers/dialogue_action_controller.gd`；`GameApp` 只保留兼容入口、trade 收尾和面板刷新分发。
- Space wait 和 auto tick wait 的 `wait` 命令提交已抽到 `godot/scripts/app/controllers/wait_action_controller.gd`；`GameApp` 只保留兼容入口、observe / pending 分支、制作队列接力和 runtime refresh。
- 主交互和选项交互的执行 facade 已抽到 `godot/scripts/app/controllers/interaction_action_controller.gd`；`GameApp` 只保留兼容入口和交互结果应用。
- 脚本级 `HudRoot` facade 已引入到 `godot/scripts/ui/hud_root.gd`，当前承接 HUD / panel setup、刷新、stage panels、settings、panel blocker、modal stack、theme、context menu snapshot、controls hint、debug console、debug panel、tooltip render 和 drag preview render；`GameApp` 保留旧 HUD / panel / overlay 字段作为 smoke 兼容引用。

仍需继续推进：

- `godot/scripts/app/game_app.gd` 仍约 2126 行，还保留 tooltip / drag snapshot facade、overlay 兼容属性、observe / pending 分支、移动交互和交互结果应用等兼容入口。
- 运行时 UI 还没有完全落成独立 `HudRoot.tscn` scene；当前已通过 `HudRoot` script 包住现有 HUD controller 和 panel controller。
- `GameApp` 文件名和 main scene 入口尚未收敛为 `GameRoot` 命名；暂不建议先改名，避免破坏 smoke/tool 入口。
- 下一步优先抽取玩家动作 facade，而不是一次性重命名根脚本。

## 当前问题

当前 `godot/scripts/app/game_app.gd` 承担了过多职责：

- 启动 runtime、registry、simulation 和 world snapshot。
- 直接管理世界容器、地图渲染、fog、debug overlay 和相机输入。
- 直接刷新 HUD、各类面板、tooltip、context menu 和 debug panel。
- 处理全局输入、UI 快捷键、debug console、observe mode 和运行时交互。
- 承载 world action queue、presentation、final refresh 等流程状态机。
- 为 headless smoke 暴露大量测试入口。

这使它不像典型 Godot 项目中的 `Main` / `GameRoot`，而更像迁移期的应用总线。继续往里面加功能会让输入焦点、UI 生命周期、世界刷新时序和测试入口越来越难维护。

## Godot 风格原则

### 场景树优先

优先把“天然属于一个场景区域的职责”放回对应 scene：

- 世界显示、actor/object 节点、fog、debug overlay、camera rig 属于 `WorldRoot.tscn`。
- HUD、面板、debug console、debug panel、tooltip、context menu 属于 `HudRoot.tscn`。
- 玩家输入、相机输入和 UI 输入按节点职责处理，而不是全部汇入一个根脚本。

### 薄根节点

根节点只负责：

- 创建或引用主要子 scene。
- 初始化 controller。
- 连接少量跨系统 signal。
- 提供有限的 smoke / tool 兼容 facade。

根节点不直接写具体玩法规则、UI 面板细节或世界渲染细节。

### Signal 和 Facade 优先

跨节点通信优先通过 signal 或窄接口完成：

- UI 发出 `panel_action_requested`、`debug_command_submitted`。
- 输入路由发出 `player_command_requested`、`camera_command_requested`。
- world action flow 发出 `presentation_started`、`presentation_finished`。
- `GameRoot` 只做必要转发，不直接展开所有细节。

### UI 输入尊重 Control

Godot 的 UI 输入应尽量由 `Control` 自身处理：

- `LineEdit`、`Button`、`Tree`、`ItemList` 等控件优先使用 `_gui_input`、内置信号和 focus。
- 游戏输入层只处理没有被 UI 接管的 `_unhandled_input`。
- 当 debug console、modal、context menu 等 UI 有焦点或阻塞状态时，玩家移动和相机快捷键不得抢事件。

### 核心规则继续引擎无关

重构不是把规则塞回 scene script：

- 战斗、移动、任务、交易、背包、AI、进度判断继续在 `godot/scripts/core`。
- 数据读取、校验、保存继续在 `godot/scripts/data`。
- scene 节点负责表现、输入转发和 runtime 装配。

## 目标结构

建议逐步收敛到以下结构：

```text
godot/scenes/app/game_root.tscn
godot/scripts/app/game_root.gd

godot/scenes/world/world_root.tscn
godot/scripts/world/world_controller.gd
godot/scripts/world/camera_rig_controller.gd
godot/scripts/world/debug_overlay_controller.gd

godot/scenes/ui/hud_root.tscn
godot/scripts/ui/hud_root.gd
godot/scripts/ui/debug_console_panel.gd
godot/scripts/ui/debug_panel.gd

godot/scripts/app/controllers/runtime_boot_controller.gd
godot/scripts/app/controllers/runtime_refresh_controller.gd
godot/scripts/app/controllers/game_input_router.gd
godot/scripts/app/controllers/world_action_flow_controller.gd
godot/scripts/app/controllers/debug_runtime_controller.gd
```

命名可以随实际场景文件调整，但职责边界应保持稳定。

## 目标职责

### `GameRoot`

保留：

- `_ready()` 中装配 registry、runtime、world、HUD 和 controller。
- `_process()` 中驱动少量跨系统 controller。
- 顶层 signal 连接。
- 兼容 smoke / agent tool 所需的少量 facade。

移出：

- debug command match。
- 世界渲染和 fog 细节。
- HUD 各面板内部刷新。
- world action queue 状态机。
- 具体移动、战斗、背包、任务、交易规则。

### `RuntimeBootController`

负责：

- 解析 startup request。
- 初始化 registry。
- 创建 simulation。
- 构建初始 world snapshot。
- 返回启动上下文。

### `RuntimeRefreshController`

负责：

- 从 simulation 生成 world / UI snapshot。
- 协调 runtime 变更后的刷新顺序。
- 维护 refresh 原因、触发来源和错误信息。
- 给 world / HUD 派发快照，而不是直接操作节点细节。

### `WorldRoot`

负责：

- 承载地图容器、actor 容器、object 容器、fog、overlay、camera。
- 对外提供 `apply_world_snapshot(snapshot)`。
- 对外提供 `set_debug_overlay(mode)`、`refresh_fog(snapshot)`。
- 管理世界节点生命周期。

不负责：

- 计算玩法结果。
- 修改背包、任务、角色属性或存档。
- 直接读取非地图 JSON。

### `HudRoot`

负责：

- HUD 和所有运行时 UI 面板。
- debug console 和 debug panel。
- tooltip、context menu、modal blocker。
- 对外提供 `apply_runtime_snapshot(snapshot)`、`open_panel(panel_id)`、`toggle_debug_console()`。

不负责：

- 直接决定玩法结果。
- 手写数据读取和保存。
- 抢占没有焦点的游戏输入。

### `GameInputRouter`

负责：

- 顶层快捷键分发。
- 根据 UI blocker / focus 决定是否允许玩家输入。
- 将玩家命令转发给 interaction controller。
- 将相机命令转发给 camera rig。

输入原则：

- `_input` 只处理必须抢先处理的全局开关，例如 debug console toggle。
- `_unhandled_input` 处理玩家移动、交互和相机输入。
- UI 控件有 focus 时，游戏输入层不消费字符输入。

### `DebugRuntimeController`

负责：

- debug console 命令执行。
- debug panel 数据模型。
- overlay / observe mode / show fps 等 debug 行为。

`show fps`、`show overlays`、`observe mode` 不再散落在 `GameRoot` 的 match 中。

### `WorldActionFlowController`

负责：

- 执行玩家动作后的 presentation 流程。
- 管理 presenter 阻塞输入状态。
- 在 presentation 完成后通知 runtime refresh。

不负责：

- 直接渲染世界。
- 直接刷新具体 UI 控件。

## 分阶段计划

### Phase 0: 建立重构安全网

- [x] 固定当前可用 smoke 清单，至少覆盖 Godot check-only、UI toggle 和 player interaction。
- [x] 为 `GameApp` 当前对外 facade 做滚动 inventory，保留 tool / smoke 兼容入口。
- [x] 新增重构期间临时约束：新增功能不得继续扩大 `game_app.gd`。
- [ ] 补齐完整 facade inventory 文档，明确哪些入口可以在 Phase 7 删除或重命名。

验收：

- `test-godot-static.ps1` 能跑通。
- `test-godot-game.ps1 -Scenario UIToggle` 能跑通。
- 已知无法跑通项有明确 issue / 文档记录。

### Phase 1: 拆 debug runtime

优先拆 debug，因为它边界清楚、风险低，并且最近已有 `show fps`、debug console 输入等变更。

- [x] 新建 `debug_runtime_controller.gd`。
- [x] 将 debug console 命令执行和 debug overlay mode 状态迁入 controller。
- [x] 保留 `debug_console_command_runner.gd` 作为命令 schema / mutation command runner。
- [ ] 继续收敛 observe mode / auto tick / info panel 与 debug runtime 的边界，避免调试状态散在多个 controller 中。
- [x] smoke 继续通过 `submit_debug_console_command()` 验证兼容入口。

验收：

- debug console 可输入。
- `show fps` 可切换常驻 debug panel。
- `show overlays` 可切换 overlay。
- `observe mode` 行为不变。

### Phase 2: 拆 HUD facade

- [x] 保留原有 panel controller 内部实现，先不大改面板内部结构。
- [x] HUD 运行时刷新已通过 `hud_controller.apply_runtime_snapshot()` 和 `input_blocker_snapshot()` 收敛为 facade。
- [x] 背包、容器、交易和角色面板的反馈状态已抽到 `ui_feedback_state_controller.gd`。
- [x] skill targeting 状态和 targeting definition 解析已抽到 `skill_targeting_controller.gd`。
- [x] crafting queue / pending crafting 反馈状态已抽到 `crafting_feedback_controller.gd`。
- [x] tooltip / drag preview overlay render layer 已抽到 `ui_overlay_render_controller.gd`。
- [x] tooltip snapshot 计算已抽到 `tooltip_snapshot_controller.gd`。
- [x] drag source / payload / preview snapshot 组装已抽到 `drag_snapshot_controller.gd`。
- [x] hotbar、observe hotbar、equipment、inventory action、container 和 trade 的 drag hover target / acceptance 已抽到 `drag_hover_target_controller.gd`。
- [x] gameplay input blocker、modal/context menu event、close priority 和 UI layer stack 组装已抽到 `ui_blocker_state_controller.gd`。
- [x] context menu 关闭转发已抽到 `ui_blocker_state_controller.gd`，`GameApp` 只提供 owner panel 映射。
- [x] 容器 take / store / transfer / close 玩家动作 facade 已抽到 `container_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 背包 drop / use / deconstruct / split / reorder 玩家动作 facade 已抽到 `inventory_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 交易 buy / sell / cart 玩家动作 facade 已抽到 `trade_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 装备 equip / unequip / reload 和属性点 facade 已抽到 `character_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 技能 learn / bind / hotbar group / hotbar use / runtime target confirm facade 已抽到 `skill_action_controller.gd`，`GameApp` 只保留兼容方法、target marker 更新和刷新执行。
- [x] 制作配方提交、制作队列推进、等待后续队列恢复、pending crafting 取消和 queue snapshot facade 已抽到 `crafting_action_controller.gd`，`GameApp` 只保留兼容方法和刷新执行。
- [x] 任务 turn-in 和地图面板进入 overworld location facade 已抽到 `world_panel_action_controller.gd`，`GameApp` 只保留兼容方法、world rebuild 和刷新执行。
- [x] 对话选择、无选项继续和关闭对话 facade 已抽到 `dialogue_action_controller.gd`，`GameApp` 只保留兼容方法、trade 收尾和刷新执行。
- [x] Space wait 和 auto tick wait 的 `wait` 命令提交已抽到 `wait_action_controller.gd`，`GameApp` 只保留兼容方法、observe / pending 分支、制作队列接力和刷新执行。
- [x] 主交互和选项交互 facade 已抽到 `interaction_action_controller.gd`，`GameApp` 只保留兼容方法和交互结果应用。
- [x] 引入脚本级 `HudRoot` facade，承接 HUD / panel setup、刷新、stage panels、settings、panel blocker、modal stack、theme 和 context menu snapshot。
- [x] controls hint、debug console、debug panel 的 HUD 控件开关、snapshot、schema/result 写入已通过 `HudRoot` 窄接口转发；`GameApp` 只保留兼容入口、刷新和音频反馈。
- [x] tooltip render 和 drag preview render controller 已由 `HudRoot` 持有，`GameApp` 的旧 overlay 属性和 render 方法只作为 smoke / tool 兼容 facade。
- [ ] 将 `GameApp` 中剩余 tooltip / drag snapshot 组装、兼容 panel 引用等代码继续替换为 `hud_root.apply_runtime_snapshot()`、`hud_root.toggle_*()` 等窄接口。
- [ ] 将移动交互、observe / pending 分支、交互结果应用等剩余玩家动作 facade 继续从 `GameApp` 移出。
- [x] 将 panel blocker / active modal 状态通过 `hud_root.input_blocker_snapshot()` / `gameplay_input_blocker_snapshot()` 暴露；debug console blocker 由 `HudRoot` 暴露，world action blocker 仍由 `GameApp` 做跨层合成。

验收：

- 背包、角色、任务、地图、技能、制作、设置面板快捷键行为不变。
- debug console 打开时字符输入不被游戏输入层吞掉。
- tooltip 和 context menu 不回归。

### Phase 3: 拆输入路由

- [x] 新建 `game_input_router.gd`。
- [x] 顶层输入分发已迁入 input router。
- [ ] 将顶层快捷键、UI blocker 判断、玩家命令分发、相机命令分发进一步集中到 input router。
- [ ] 玩家移动 / 交互输入继续交给现有 runtime input controller，但从 `GameApp` 直接调用改为 input router 调用。
- [ ] 相机控制逐步迁到 `camera_rig_controller.gd`。

验收：

- UI 有焦点时不吞字符。
- 玩家移动、拾取、交互、快捷键、观察模式不回归。
- camera pan / zoom / rotate 行为不回归。

### Phase 4: 拆 WorldRoot

- [x] 世界表现入口已抽到 `godot/scripts/world/world_root.gd`。
- [x] 将地图容器、actor/object 容器、fog overlay、debug overlay、camera rig 的主要显示入口收敛到 WorldRoot。
- [x] `GameApp` 主要通过 WorldRoot 接口应用世界快照和 debug overlay。
- [ ] 继续整理 `world_root.tscn` / camera rig controller，减少 `GameApp` 对世界节点引用的兼容字段。

验收：

- 地图 scene 加载、对象显示、actor 显示、碰撞、fog、debug overlay 不回归。
- 地图切换或 runtime refresh 不产生重复节点。
- world render count / actor count / object count 统计继续正确。

### Phase 5: 拆 runtime refresh

- [x] 新建 `runtime_refresh_controller.gd`。
- [x] 将 runtime snapshot -> world snapshot 的构建迁入 controller。
- [x] 明确 refresh reason：startup、player command、debug command、world action final refresh、editor smoke。
- [ ] 继续将 world apply -> HUD apply 的最终顺序收敛到 controller，减少根脚本手写刷新链。
- [ ] 将错误处理和日志集中到 refresh controller。

验收：

- player command 后 world / UI 状态一致。
- debug command 后 world / UI 状态一致。
- refresh 日志能定位 source、reason、map id、actor id 等关键上下文。

### Phase 6: 拆 world action flow

这是风险最高阶段，应最后做。

- [x] 新建 `world_action_flow_controller.gd`。
- [x] 将 world action presenter、queue、pending UI 和 pending final refresh 状态迁出 `GameApp`。
- [ ] 使用 signal 通知 `RuntimeRefreshController` 何时执行最终刷新。
- [x] 保留当前 action presentation 行为，不在同一阶段重做动效。

验收：

- 移动 presentation 不闪烁、不提前刷新终点状态。
- presentation 阻塞输入逻辑不回归。
- final refresh 后 HUD 和世界状态一致。

### Phase 7: 收敛命名与兼容入口

- [ ] 将 `game_app.gd` 收敛为 `game_root.gd` 或保留文件名但改为薄根节点。
- [ ] 清理只为迁移期存在的 wrapper。
- [ ] smoke / tools 仍可通过稳定 facade 调用。
- [ ] 更新 AGENTS.md、tools README 和相关 workflow 文档中的入口描述。

验收：

- `game_app.gd` 或替代根脚本职责清楚，文件规模明显下降。
- 新增功能有明确落点，不再默认进入根脚本。

## 不做事项

- 不把核心玩法规则迁入 scene script。
- 不把非地图数据读写绕过 `godot/scripts/data`。
- 不把地图编辑能力重新塞回运行时 UI。
- 不在同一阶段同时重做 UI 视觉、地图资产和运行时架构。
- 不为了“拆文件”制造无职责边界的 `utils.gd` / `helpers.gd`。

## 推荐提交策略

- 每个 phase 至少一个独立提交。
- 每次提交只移动一类职责，避免 debug、world、UI、input 混在一起。
- 大文件拆分优先保持行为不变，行为变化另起提交。
- 对已知 dirty 工作区，提交时只暂存当前 phase 直接相关文件。

## 验证矩阵

每个 phase 根据触及范围选择验证：

```text
pwsh -NoProfile -File tools\agent\test-godot-static.ps1
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario UIToggle
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario PlayerInteraction
pwsh -NoProfile -File tools\agent\test-godot-editor.ps1 -Scenario All
```

如果某个 smoke 被无关 dirty 文件阻塞，应在交付中写清楚阻塞文件、错误信息和本次已完成的最低验证。

## 完成判定

当以下条件满足时，可以认为应用层已回到更典型的 Godot 项目结构：

- 根脚本只负责装配和少量转发。
- 世界、UI、输入、debug、runtime refresh 都有独立 controller 或 scene。
- UI 控件按 Godot Control/focus 机制处理输入。
- 玩法规则仍保持在 core/data，不被 scene 脚本污染。
- smoke 和 agent tool 仍有稳定入口。
