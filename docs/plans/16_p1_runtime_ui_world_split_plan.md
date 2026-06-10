# P1 运行时输入、HUD 与表现拆分计划

本文规划当前 P1 级别的三个高风险大文件拆分：

- `godot/scripts/world/world_action_presenter.gd`
- `godot/scripts/ui/controllers/hud_controller.gd`
- `godot/scripts/app/controllers/game_runtime_input_controller.gd`

它们不是 core 规则权威，但都处在玩家体验主链路：输入、HUD、hover / selection、行动表现和 debug 面板。重构目标是让它们更符合 Godot 的节点 / scene / controller 风格，同时避免一次性重写造成交互回归。

## 当前问题

### `world_action_presenter.gd`

当前约 `2500` 行，包含移动、攻击、交互、换弹、战斗事件、门自动打开、pending movement segment、表现节点创建、材质、标签、Tween 跟踪和 public snapshot。

主要问题：

- 一个 presenter 同时处理多个行动类型，新增表现时容易继续堆分支。
- movement / attack / interaction / reload / combat event 的生命周期相似，但实现彼此缠在一个文件里。
- 材质、label、marker 创建细节和 presentation flow 混在一起。
- smoke 直接验证很多 metadata、phase、marker、label 文案，拆分时需要非常小步。

### `hud_controller.gd`

当前约 `2300` 行，包含 HUD 文本、interaction menu、debug console、debug panel、controls hint、feedback toast、hotbar、observe hotbar、drag/drop、tooltip 文案和 runtime control 文本。

主要问题：

- 它更像一个手写 HUD scene builder，而不是 Godot 中由多个 `Control` 子节点组成的 UI。
- debug console / debug panel / interaction menu / hotbar 都有独立状态和输入，应拆成独立控件脚本。
- 当前 `_build_layout()` 负责大量 UI 创建，后续转成 `.tscn` 会比较吃力。
- 作为 `HudRoot` 的底层 controller，改动会影响大量 UI smoke。

### `game_runtime_input_controller.gd`

当前约 `2050` 行，包含鼠标拾取、hover、selection、相机输入、快捷键 fallback、space hold wait、hotbar 数字键、技能目标预览、attack / move path markers 和 UI blocker 判断。

主要问题：

- 输入路由、世界 picking、hover state、视觉 marker 和命令提交前预览混在一起。
- 许多函数天然属于 `WorldInteractionPicker`、`HoverPreviewController`、`RuntimeMarkerController` 或 `CameraInputController`。
- `GameInputRouter` 已经存在，当前文件还保留 direct-call smoke fallback，职责边界不够干净。

## 重构原则

- 先拆“子职责 controller”，再考虑 `.tscn` scene 化。
- 保留现有 public facade，先改内部委托，等 smoke/tool 更新后再删旧入口。
- 每个拆分对象都要保持 snapshot / metadata / reason 文案兼容。
- 优先抽纯计算或纯视觉构建，再抽输入生命周期。
- 不把 UI 逻辑搬到 core，不把 world presentation 逻辑搬到 app。
- 不创建 `utils.gd` / `helpers.gd`，新文件名称必须体现职责。

## 目标目录

建议新增或演进为：

```text
godot/scripts/world/presentation/
  world_action_presenter.gd              # 薄 facade / 调度
  movement_action_presenter.gd
  attack_action_presenter.gd
  interaction_action_presenter.gd
  reload_action_presenter.gd
  combat_event_presenter.gd
  presentation_node_factory.gd
  presentation_materials.gd
  presentation_tracker.gd

godot/scripts/ui/hud/
  hud_controller.gd                      # 临时 facade，后续可被 HudRoot scene 替代
  debug_console_panel.gd
  debug_panel_view.gd
  interaction_menu_view.gd
  hotbar_view.gd
  observe_hotbar_view.gd
  feedback_toast_layer.gd
  hud_text_formatter.gd

godot/scripts/app/controllers/runtime_input/
  game_runtime_input_controller.gd       # 薄 facade / 生命周期
  world_interaction_picker.gd
  hover_state_controller.gd
  runtime_marker_controller.gd
  skill_target_preview_controller.gd
  camera_input_controller.gd
  space_wait_hold_controller.gd
```

目录可以随实际落地调整，但职责边界应保持清楚。

## Phase 0: Inventory 和依赖确认

- [ ] 为三个 P1 文件生成函数 inventory，按职责分组。
- [ ] 标记 public API、smoke 直接调用和只供内部使用的入口。
- [ ] 列出每个文件对应 smoke 场景。
- [ ] 记录现有 direct-call fallback，确认哪些必须暂保留。

验收：

- 每个函数族都有目标归属。
- 明确第一阶段只抽哪个最小职责，不同时动三条主链路。

## Phase 1: 拆 WorldActionPresenter 的 tracker / factory

先从低风险的公共工具层开始。

- [ ] 新建 `presentation_tracker.gd`，迁移 active node / active tween 跟踪、prune、finish、latest snapshot 记录。
- [ ] 新建 `presentation_materials.gd`，迁移 attack / interaction / reload / combat event / pending movement 材质生成。
- [ ] 新建 `presentation_node_factory.gd`，迁移 label、marker、mesh 创建的纯视觉工厂。
- [ ] `world_action_presenter.gd` 保留 public `present_result()`、`snapshot()`、`finish_active_presentations()`。

验收：

- `D:\godot\godot.cmd --headless --path godot --check-only --script res://scripts/world/world_action_presenter.gd`
- `pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario PlayerInteraction`
- `pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario Combat`

## Phase 2: 拆 MovementActionPresenter

- [ ] 新建 `movement_action_presenter.gd`。
- [ ] 迁移 movement path、facing、door auto-open marker、pending segment marker、movement tween。
- [ ] 保持 movement public snapshot 和 actor metadata 字段兼容。
- [ ] `WorldActionPresenter` 只负责从 events 中分发 movement presentation。

验收：

- `Movement`
- `PlayerInteraction`
- `Door`
- 重点检查 pending movement、自动开门、地图切换后 stale marker 清理。

## Phase 3: 拆 Attack / Reload / Combat Event presenters

- [ ] 新建 `attack_action_presenter.gd`，迁移攻击反馈、damage label、delivery marker、muzzle flash、projectile trail、shell eject、on-hit effect。
- [ ] 新建 `reload_action_presenter.gd`，迁移 reload marker / label / metadata。
- [ ] 新建 `combat_event_presenter.gd`，迁移非直接攻击类 combat event 表现。
- [ ] 公共 node factory / materials 不重复实现。

验收：

- `Combat`
- `PlayerInteraction`
- `SkillsUI`
- 重点检查 on-hit effect、miss / critical / defeated 文案和 marker metadata。

## Phase 4: 拆 InteractionActionPresenter

- [ ] 新建 `interaction_action_presenter.gd`。
- [ ] 迁移拾取、容器、对话、门、inspect 等 interaction feedback。
- [ ] 迁移 interaction visual profile / visual kind / feedback text。
- [ ] `WorldActionPresenter` 只聚合 snapshot 和 active presentation 状态。

验收：

- `Interaction`
- `PlayerInteraction`
- `ContainerUI`
- `DialogueUI`

## Phase 5: 拆 HUD debug console / debug panel

从 HUD 中相对独立的 debug UI 开始。

- [ ] 新建 `debug_console_panel.gd`，承接 console 输入、历史、autocomplete、schema、result 展示和输入事件处理。
- [ ] 新建 `debug_panel_view.gd`，承接 runtime/debug/AI/performance/selection 文本格式化和 panel 展示。
- [ ] `hud_controller.gd` 保留 `toggle_debug_console()`、`set_debug_console_result()`、`debug_panel_snapshot()` 等 facade。

验收：

- `UIToggle`
- `PlayerInteraction`
- 手动或 smoke 验证反引号控制台可输入命令、`show fps` / debug panel 状态不回归。

## Phase 6: 拆 HUD interaction menu 和 feedback toast

- [ ] 新建 `interaction_menu_view.gd`，承接右键/交互菜单按钮、禁用原因、summary、position 和 snapshot。
- [ ] 新建 `feedback_toast_layer.gd`，承接 toast row、style、metadata 和清理。
- [ ] 菜单点击继续通过已有 signal / Callable 进入 `GameApp` facade，不在 view 中写玩法规则。

验收：

- `PlayerInteraction`
- `ContainerUI`
- `TradeUI`
- `InventoryUI`

## Phase 7: 拆 Hotbar / ObserveHotbar

- [ ] 新建 `hotbar_view.gd`，承接 hotbar slot、group、drag/drop、cooldown mask、tooltip。
- [ ] 新建 `observe_hotbar_view.gd`，承接 observe mode / play / speed / auto tick 控件。
- [ ] 保持 hotbar hit test、drag metadata、drop acceptance 和 audio payload 兼容。

验收：

- `UIToggle`
- `SkillsUI`
- `InventoryUI`
- `PlayerInteraction`

## Phase 8: 拆 Runtime Input 的 picking

- [ ] 新建 `world_interaction_picker.gd`。
- [ ] 迁移 raycast、candidate sort、interaction metadata merge、picking diagnostics。
- [ ] `GameRuntimeInputController.update_hover_at_screen_position()` 保留 facade，内部委托 picker。
- [ ] 不同时修改 hover marker 或 selection 行为。

验收：

- `PlayerInteraction`
- `Interaction`
- `Scene`
- 重点检查 door / container / transition / actor / pickup picking 优先级。

## Phase 9: 拆 Runtime Input 的 hover state 和 marker

- [ ] 新建 `hover_state_controller.gd`，迁移 hover state、selection debug、hover prompt、move / attack preview 汇总。
- [ ] 新建 `runtime_marker_controller.gd`，迁移 hover cursor、target outline、attack marker、attack range marker、move path marker、pending movement marker。
- [ ] 新建 `skill_target_preview_controller.gd`，迁移技能目标 preview marker。
- [ ] `GameRuntimeInputController` 只协调 picker -> hover state -> marker controller -> GameApp facade。

验收：

- `PlayerInteraction`
- `SkillsUI`
- `Combat`
- `Movement`

## Phase 10: 拆 CameraInput 和 SpaceHold

- [ ] 新建 `camera_input_controller.gd`，迁移相机键盘、拖拽、滚轮、zoom scale 和 focus。
- [ ] 新建 `space_wait_hold_controller.gd`，迁移 Space 长按等待重复提交。
- [ ] `GameInputRouter` 和 `GameRuntimeInputController` 的 direct-call fallback 分工重新整理。

验收：

- `UIToggle`
- `PlayerInteraction`
- `Movement`
- 重点检查 WASD 不再平移旧相机、F focus、滚轮 zoom、Space hold wait。

## Phase 11: Scene 化 HUDRoot

这一阶段可选，等 `hud_controller.gd` 明显变薄后再做。

- [ ] 新建或整理 `godot/scenes/ui/hud_root.tscn`。
- [ ] 把 debug console、debug panel、interaction menu、hotbar、toast 作为真实 Control 子节点。
- [ ] `HudRoot` 从脚本 facade 变成 scene root script。
- [ ] `GameApp` 只实例化 / 引用 HUD scene，不再靠 `_build_layout()` 动态创建大部分 UI。

验收：

- 所有 UI smoke：`UIToggle`、`InventoryUI`、`ContainerUI`、`TradeUI`、`DialogueUI`、`SkillsUI`、`CraftingUI`。

## 推荐执行顺序

1. `WorldActionPresenter` 公共 tracker / factory / materials。
2. `MovementActionPresenter`。
3. `Attack` / `Reload` / `CombatEvent` presenters。
4. HUD debug console / debug panel。
5. HUD interaction menu / toast。
6. Runtime input picking。
7. Runtime input hover / marker。
8. Camera / Space hold。
9. HUDRoot scene 化。

理由：

- world presentation 拆分相对独立，不会先扰动 UI tree。
- HUD debug console 是相对独立的 UI 子块，适合验证 Control 子脚本模式。
- input picking 和 marker 风险较高，放在已有 world/HUD 拆分经验之后。

## 不做事项

- 不把 presentation 逻辑塞回 `GameApp`。
- 不把 HUD 的 button callback 写成直接修改 `Simulation`。
- 不在拆 input 时顺手改相机手感、hover 优先级或 UI blocker 策略。
- 不在拆 HUD 时顺手重做视觉风格。
- 不一次性把三个 P1 文件同时大改。

## 验证矩阵

常用静态检查：

```powershell
D:\godot\godot.cmd --headless --path godot --check-only --script res://scripts/world/world_action_presenter.gd
D:\godot\godot.cmd --headless --path godot --check-only --script res://scripts/ui/controllers/hud_controller.gd
D:\godot\godot.cmd --headless --path godot --check-only --script res://scripts/app/controllers/game_runtime_input_controller.gd
```

常用 smoke：

```powershell
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario PlayerInteraction
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario UIToggle
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario Combat
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario SkillsUI
```

阶段末可跑：

```powershell
pwsh -NoProfile -File tools\agent\test-godot-game.ps1 -Scenario All
```

若 `All` 失败在无关既有场景，应记录失败场景、result 路径和关键信号，不把无关修复混进当前拆分提交。

## 完成标准

- `world_action_presenter.gd` 只作为行动表现 facade / 聚合器，具体行动表现进入独立 presenter。
- `hud_controller.gd` 不再手写所有 HUD 子控件细节，debug、menu、hotbar、toast 等有独立 Control 脚本。
- `game_runtime_input_controller.gd` 不再同时承担 picking、hover state、marker 构建、camera input 和 long-press wait。
- 新增 runtime 输入、HUD 或表现能力有明确落点，不再默认加入这三个大文件。
