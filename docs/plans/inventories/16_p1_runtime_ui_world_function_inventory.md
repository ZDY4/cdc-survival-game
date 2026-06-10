# P1 运行时输入、HUD 与表现函数 Inventory

来源文件：

- `godot/scripts/world/world_action_presenter.gd`
- `godot/scripts/ui/controllers/hud_controller.gd`
- `godot/scripts/app/controllers/game_runtime_input_controller.gd`

本文用于执行 `docs/plans/16_p1_runtime_ui_world_split_plan.md` 的 Phase 0。

## 总览

| 文件 | 规模 | 当前职责 | 第一拆分方向 |
| --- | ---: | --- | --- |
| `world_action_presenter.gd` | 约 `2516` 行，`111` funcs | movement / attack / interaction / reload / combat event 表现、marker、label、材质、Tween 跟踪 | 先抽 tracker / materials / node factory |
| `hud_controller.gd` | 约 `2278` 行，`136` funcs | HUD 文本、debug console、debug panel、interaction menu、toast、hotbar、observe hotbar、drag/drop、runtime 文本 | 先抽 debug console / debug panel |
| `game_runtime_input_controller.gd` | 约 `2059` 行，`122` funcs | input lifecycle、picking、hover、selection、camera、markers、skill preview、space hold | 先抽 world picker，再抽 hover/marker |

## `world_action_presenter.gd` 函数族

| 行范围 | 当前函数族 | 目标归属 |
| --- | --- | --- |
| `28-106` | `present_result`、`snapshot`、`finish_active_presentations`、event 提取 | `WorldActionPresenter` facade / aggregator |
| `118-600` | movement、movement cancelled、door auto-open markers、pending movement segment、movement tween、movement snapshot | `MovementActionPresenter` |
| `613-1394` | attack presentation、damage label、delivery marker、muzzle flash、projectile trail、shell eject、on-hit effect、attack materials / text / metadata | `AttackActionPresenter` + `PresentationNodeFactory` + `PresentationMaterials` |
| `1406-1522` | interaction presentation、interaction marker / label、interaction visual profile | `InteractionActionPresenter` |
| `1546-1725` | reload presentation、reload marker、reload material / label / text | `ReloadActionPresenter` |
| `1725-1871` | combat event presentation、label、material、text | `CombatEventPresenter` |
| `1902-2007` | actor / target node lookup、presentation layer lookup、grid helpers | shared lookup helpers or kept in facade until presenters stabilize |
| `2016-2336` | materials、visual profile、feedback text、label color / y offset | `PresentationMaterials` + type-specific presenter |
| `2345-2415` | public snapshot builders、duration parsing、Vector3 defaults | `PresentationTracker` / presenter-specific snapshot |
| `2421-2461` | active node / tween tracking, prune, latest record | `PresentationTracker` |
| `2469-2510` | grid/vector/dictionary helpers | move to consuming presenter only; no generic utils |

### Public / observed API

- Public: `present_result(host, world_root, command_result, world_result)`、`snapshot()`、`finish_active_presentations()`。
- Direct smoke call: `player_interaction_smoke.gd` calls `game_root.world_action_presenter.call("present_result", ...)` for synthetic event presentation.
- App flow: `WorldActionFlowController` owns `WorldActionPresenter.new()` and calls `present_result()` / snapshots.

### Smoke coverage

- Movement / door auto-open: `Movement`、`PlayerInteraction`、`Door`
- Attack / reload / combat event: `Combat`、`PlayerInteraction`、`SkillsUI`
- Interaction feedback: `Interaction`、`PlayerInteraction`、`ContainerUI`、`DialogueUI`

## `hud_controller.gd` 函数族

| 行范围 | 当前函数族 | 目标归属 |
| --- | --- | --- |
| `60-111` | ready、snapshot apply、layout build entry | future `HudRoot` scene facade |
| `185-300` | controls hint、debug panel、debug console public facade、console schema/result/history | `DebugConsolePanel` + `DebugPanelView` facade |
| `305-389` | console command history, interaction menu public facade, input blocker snapshot | `DebugConsolePanel` + `InteractionMenuView` |
| `397-525` | feedback toast layer, toast row/style/metadata/clear | `FeedbackToastLayer` |
| `533-598` | dynamic construction for interaction menu, debug console, debug panel | replace with scene nodes or dedicated view setup |
| `626-708` | console input event, history recall, autocomplete, help text, command detail | `DebugConsolePanel` |
| `719-821` | debug panel apply and line formatting | `DebugPanelView` |
| `831-1035` | interaction menu apply, option buttons, disabled tooltips, context option details, disabled reason text | `InteractionMenuView` |
| `1074-1480` | hotbar / group / observe hotbar render, button setup, audio payload, tooltip, cooldown, resource text | `HotbarView` + `ObserveHotbarView` |
| `1495-1681` | hotbar / observe drag/drop acceptance and hover render | `HotbarView` + `ObserveHotbarView` |
| `1687-1704` | menu positioning and prompt summary | `InteractionMenuView` |
| `1718-2259` | HUD text formatters: inventory, event, quest, combat, info panel, runtime control, performance, hover, skill targeting | `HudTextFormatter` + debug panel specific formatter |
| `2259-2277` | dictionary / array / number helpers | move to consumers; no generic helper module unless stable |

### Public / observed API

- Public via `HudRoot` / `GameApp`: `toggle_debug_console`、`close_debug_console`、`debug_console_snapshot`、`set_debug_console_schema`、`set_debug_console_result`、`clear_debug_console_history`、`toggle_debug_panel`、`debug_panel_snapshot`、`show_interaction_menu`、`hide_interaction_menu`、`is_interaction_menu_open`、`input_blocker_snapshot`、`hotbar_hit_test` behavior through `HudRoot` facade.
- Direct smoke/node observations:
  - `ui_toggle_smoke.gd` finds `DebugConsole`、`ConsoleInput`、`DebugPanel`、`HotbarDock`、`HotbarGroupBar`、`Observe*Button` nodes.
  - `skills_ui_smoke.gd` calls private hotbar drop methods such as `_can_drop_hotbar_skill` / `_drop_hotbar_skill`.
  - `ui_smoke.gd` calls text helper methods such as `_disabled_reason_text` and `_skill_target_reason_text`.
  - `ui_toggle_smoke.gd` calls `_can_drop_observe_hotbar`.

### Smoke coverage

- Debug console / panel: `UIToggle`、`PlayerInteraction`
- Interaction menu: `PlayerInteraction`、`ContainerUI`、`TradeUI`
- Hotbar / observe hotbar: `UIToggle`、`SkillsUI`、`InventoryUI`、`PlayerInteraction`
- Text formatting: `UISmoke`、`UIToggle`

## `game_runtime_input_controller.gd` 函数族

| 行范围 | 当前函数族 | 目标归属 |
| --- | --- | --- |
| `74-190` | init, attach world, process/input/unhandled entry, public mouse handlers | `GameRuntimeInputController` facade |
| `196-266` | mouse motion/button lifecycle, context menu outside click, hover facade | facade + `WorldInteractionPicker` |
| `305-337` | hover / selection snapshots, camera key handling entry | `HoverStateController` / `CameraInputController` |
| `437-474` | Space hold wait repeat | `SpaceWaitHoldController` |
| `482-530` | digit key, observe hover focus, hotbar group key | keep facade until `GameInputRouter` fully owns shortcut routing |
| `556-619` | clear selection, skill target preview marker update, focus current actor | `HoverStateController` + `SkillTargetPreviewController` + `CameraInputController` |
| `624-699` | public space/camera wrappers, stage keybindings, camera drag/zoom, hover refresh | `CameraInputController` + `SpaceWaitHoldController` |
| `703-849` | hover cursor, clear hover/selection, set ground/interaction/failure hover | `HoverStateController` |
| `870-1095` | raycast picking, metadata merge, priority/subpriority, diagnostics | `WorldInteractionPicker` |
| `1130-1317` | hover replacement, selection debug, prompt, move / attack preview | `HoverStateController` |
| `1317-1680` | hover cursor, target outline, attack markers, range markers, move path / pending path markers | `RuntimeMarkerController` |
| `1695-1764` | runtime snapshot, grid, interaction node, skill target preview / target from hover | `SkillTargetPreviewController` + facade |
| `1768-1811` | camera lookup, focus positions, observed level | `CameraInputController` |
| `1817-1951` | marker mesh builders for hover / attack / move / skill | `RuntimeMarkerController` |
| `1969-2044` | UI blocker queries, pending checks, actor grid, viewport/map size | split by caller; keep local until controllers stabilize |

### Public / observed API

- App / router calls: `process`、`input`、`unhandled_input`、`mouse_over_blocking_ui`、`close_context_menu_on_outside_click`、`handle_world_mouse_motion`、`handle_world_mouse_button`、`update_hover_at_screen_position`、`hover_state_snapshot`、`selection_debug_snapshot`、`clear_selection_state`、`update_skill_target_preview_markers`、`focus_current_actor`、`handle_space_key_pressed`、`stop_space_wait_hold`、`scale_camera_zoom`、`reset_camera_zoom`、`has_selection_state`。
- Direct smoke calls:
  - `PlayerInteraction` calls `update_hover_at_screen_position` frequently and directly inspects `runtime_input_controller.world_result`.
  - `PlayerInteraction` calls private `_attack_range_candidate_grids` and `_player_focus_position`.
  - `ContainerUI`、`DialogueUI`、`TradeUI`、`SkillsUI`、`UIToggle` call `runtime_input_controller.input(event)`.
  - `PlayerInteraction` / `UIToggle` call `process(0.0)` and selection APIs.

### Smoke coverage

- Picking / hover / selection: `PlayerInteraction`、`Interaction`、`Scene`
- Markers / previews: `PlayerInteraction`、`Combat`、`SkillsUI`、`Movement`
- Camera / focus / wheel / drag: `PlayerInteraction`、`UIToggle`
- Space hold: `UIToggle`、`PlayerInteraction`

## 现有 direct-call fallback

这些入口需要在拆分时暂保留 facade：

- `GameRuntimeInputController.input()` / `process()`：多个 UI smoke 直接调用。
- `GameRuntimeInputController.update_hover_at_screen_position()`：大量 PlayerInteraction smoke 直接调用。
- `GameRuntimeInputController._attack_range_candidate_grids()` / `_player_focus_position()`：当前是 private direct smoke 依赖，拆 marker/hover 前应先提供稳定 public probe 或同步改 smoke。
- `HudController._can_drop_hotbar_skill()`、`_drop_hotbar_skill()`、`_can_drop_observe_hotbar()`、`_disabled_reason_text()`、`_skill_target_reason_text()`：当前 smoke 直接调用；拆 hotbar/text formatter 时保留 wrapper。
- `WorldActionPresenter.present_result()`：`WorldActionFlowController` 和 PlayerInteraction synthetic event smoke 依赖。

## 第一刀建议

按当前依赖，P1 第一阶段应先做 `WorldActionPresenter` 的公共底座拆分：

1. `PresentationTracker`：active node / tween / latest snapshot。
2. `PresentationMaterials`：各类材质工厂。
3. `PresentationNodeFactory`：label / marker / mesh 创建。

这一步不改变 movement / attack / interaction 的分发，不触碰 HUD 和 input；验证面相对集中。
