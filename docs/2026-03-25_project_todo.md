# 2026-03-25 Project TODO

本文件用于替代已删除的 `2026-03-24_unfinished_consolidated.md`。

整理原则：

- 仅保留当前仓库状态下仍然需要继续推进的事项
- 已有明显底层落点、但尚未闭环的内容，按“继续收口”记录
- 已基本完成、只剩零散优化的内容，不再单独保留为主 backlog

---

## 1. Rust / Bevy Headless 主链路

### 1.1 Runtime command surface 继续收口

- [ ] 继续减少 `bevy_server`、debug 工具、测试代码对 `economy_mut()` 的直接依赖
- [ ] 将高频 runtime 操作进一步提升为统一入口，而不是长期保留在 demo helper 或子系统直调中
- [ ] 明确哪些操作应进入 `SimulationCommand`
- [ ] 明确哪些操作应进入 `game_protocol` request/response

### 1.2 权威 save / load snapshot

- [x] 在共享 Rust 层建立第一版 runtime save model
- [x] 覆盖 actor registry、actor positions、AP / turn state、combat HP / progression
- [x] 覆盖 economy actor state、active / completed quests、current map id、interaction context
- [x] 覆盖 runtime-generated pickups / map object deltas
- [x] 提供 `save_snapshot()` / `load_snapshot()`
- [x] 为 schema version / migration 预留升级位点
- [x] 补最小验证，确认存档前后 actor 数量、背包、quest、地图对象变化、地图上下文一致

当前已完成的是“共享 Rust 层的第一版权威 runtime snapshot 基础”。

- 目前明确不持久化 `actor_runtime_actions`、`ai_controllers`、`events`
- 这属于有意收口后的第一阶段边界，不阻塞 save / load 主链路
- 若后续需要把 NPC 长时动作执行态也做成可恢复存档，应单列为下一批 snapshot 扩展项

### 1.3 权威 dialogue runtime 继续下沉

- [x] 将对话运行时状态正式下沉到共享 Rust 层，而不是只停留在 interaction 返回 `dialogue_id`
- [x] 在 Rust 侧统一承载 start dialogue / read current node / enumerate choices / choose option / advance / end
- [x] 让 quest、item、money、map travel 等对话动作由 Rust 权威结算
- [x] 将 `AdvanceDialogue` 真正接到 runtime command path
- [x] 改造 `bevy_debug_viewer`，不再本地推进对话节点和选项

补充进度：

- 已在共享 Rust 层新增对话节点推进 helper，并补最小单测
- 已形成 `Simulation` / `SimulationRuntime` 级 authority dialogue session/runtime state，并纳入 snapshot
- `bevy_debug_viewer` 现已通过 runtime authority 推进对话；本地仅保留展示 / fallback 所需资源解析
- `bevy_server` in-process protocol handler 已支持 `AdvanceDialogue` 并返回权威 `DialogueState`

### 1.4 gameplay 协议面继续补齐

- [x] 扩充 `game_protocol`，补 runtime snapshot request、runtime delta / event push
- [x] 补 equip / unequip / reload、craft / buy / sell、learn skill
- [x] 补 start quest、advance dialogue、save / load
- [x] 补 overworld route / start travel / advance travel / enter location / return to overworld
- [x] 补 `TravelToMap` / scene-context map travel
- [x] 为失败场景定义稳定错误语义
- [ ] 明确 command id、response、async event 的关系

补充进度：

- 已补 `runtime snapshot save / load` request / response payload 与消息枚举
- 已补 `equip / unequip / reload / learn skill / craft / buy / sell / start quest` request / response payload 与消息枚举
- 已补 `advance dialogue` request / response payload 与消息枚举，并接通 `bevy_server` handler
- 已补 overworld route、start travel、advance travel、enter location、return to overworld 的 `bevy_server` handler
- 已补 `SubscribeRuntime` 初始 snapshot、`RequestOverworldSnapshot`、`TravelToMap` 与基于 runtime event drain 的 `Delta` 推送
- 已为 runtime 常见失败场景补稳定错误码前缀映射，避免继续依赖不稳定的自由文本判断
- `delta / event push` 的订阅粒度与 command id 关联语义仍需继续收口到长期稳定协议面

### 1.5 `bevy_server` 本地 transport

- [ ] 在 `bevy_server` 增加长期使用的本地 transport
- [ ] 只选择一套长期主通道，优先 TCP 或 IPC 其一
- [ ] 支持 world snapshot 订阅、request snapshot、command dispatch、runtime event stream、error channel
- [ ] 支持 connect / disconnect / reconnect / load initial state
- [ ] 保持消息语义与 `SimulationCommand` / `SimulationEvent` 一致

补充进度：

- 已在 `bevy_server` 增加可测试的 in-process protocol handler
- 已有 ECS message 级 request / response dispatch、snapshot store、基础错误回传
- 这为后续 TCP / IPC transport 提供了可直接挂接的 server 内部入口，但还不是最终 transport

### 1.6 headless smoke / 长链路验证

- [x] 增加完整 headless smoke scenarios
- [x] 至少覆盖开局载入、移动、拾取、战斗击杀、quest 开始/推进/完成
- [x] 至少覆盖技能学习、制作、商店交易、地图切换、对话推进、存档/读档

补充进度：

- 已在 `game_core` 增加 headless 长链路 smoke test，串联移动、拾取、战斗击杀、quest 开始/完成、对话推进、技能学习、制作、商店交易、地图切换、存档/读档
- 这为后续 `bevy_server` transport 与 Godot 协议前端化提供了稳定的核心回归基线

---

## 2. 地图切换与上下文

以下内容已有明显底层实现，但还没有完全闭环，后续按“继续收口”推进：

- [x] 统一 map travel / scene context runtime 的对外入口，避免 Godot 本地规则继续扩张
- [ ] 继续收口 `enter_subscene` / `enter_overworld` / `exit_to_outdoor` / `enter_outdoor_location` 的长期入口
- [ ] 让 Godot 侧逐步只消费 Rust 权威返回的 map context、return point、entry point、world mode
- [x] 补充相关 smoke / runtime tests，覆盖 scene context 与 return context

---

## 3. Godot 客户端迁移与 legacy 清理

### 3.1 Godot 协议前端化

- [ ] 基于 `game_protocol` 增加 Godot 端交互查询 / 执行 / 对话推进传输层
- [ ] 将 Godot 端收敛为点击命中、菜单 UI、动画表现、命令发送、事件消费
- [ ] 不再扩展 GDScript 本地交互权威逻辑

### 3.2 旧交互实现继续退役

- [ ] 将 `systems/interaction_system.gd` 继续收敛为协议前端壳
- [ ] 将 `systems/player_controller.gd` 从本地交互执行热点逐步降级为客户端输入与表现桥接
- [ ] 将 `modules/interaction/*` 在协议路径稳定后分阶段瘦身
- [ ] 移除 `talk_interaction_option.gd` 的本地对话执行路径
- [ ] 移除 `attack_interaction_option.gd` 的本地攻击入口路径
- [ ] 将 travel 相关 option 从直接调用 `MapModule` 迁移到协议 / runtime 返回结果驱动

### 3.3 B 级 legacy 域边界整理

- [ ] `core/game_state.gd` 继续拆分为 Rust 权威状态、Godot 只读缓存、UI 临时状态
- [ ] `modules/map/map_module.gd` 继续拆开旅行规则与场景加载编排
- [ ] `systems/ai/ai_manager.gd` 剥离本地决策与规则判断，仅保留表现桥接 / actor 映射
- [ ] `core/data_manager.gd` 继续移除共享 schema、校验、规则迁移等长期应归属 Rust 的职责

---

## 4. 角色交互与内容数据

### 4.1 角色交互配置数据化

- [ ] 在 `data/characters/*.json` 中逐步补全显式 `interaction`
- [ ] 优先覆盖高频 NPC：商人、医生、守卫
- [ ] 让 `game_bevy` 组装层优先读取显式交互配置
- [ ] fallback 仅保留给未迁移旧数据

---

## 5. Item Fragment Editor

### 5.1 引用预览能力收尾

- [ ] 为 item / effect 引用补 hover 预览
- [ ] 保持 badge 摘要、detail panel、picker 预览一致
- [ ] 补齐高频引用位点的详情入口

### 5.2 Shared Registries / Catalog Tightening

- [ ] 在共享 Rust 层建立 registry / catalog
- [ ] 收紧高频字符串字段：`equipment slots`、`rarity`、`weapon subtype`、`usable subtype`
- [ ] 编辑器默认从 registry 选择，而不是以前端 seed 默认值长期代替权威来源
- [ ] 对未知值输出 warning

### 5.3 Data Lint and Reporting

- [ ] 在共享 Rust 层增加内容质量 lint
- [ ] 覆盖未被引用 effect、缺 icon item、缺 economy fragment item
- [ ] 覆盖可装备 item 无属性加成也无效果、placeholder effect 未替换、重复 item 组合
- [ ] 在编辑器中增加只读报告页：`Items report`、`Effects report`、`Broken references`、`Unused content`

### 5.4 Fragment Header Quick Edit

- [ ] 在 fragment 卡片头部增加高频字段快速编辑
- [ ] 优先覆盖 `economy.rarity`、`stacking.max_stack`、`equip.level_requirement`
- [ ] 优先覆盖 `usable.use_time`、`weapon.damage`

### 5.5 测试补齐

- [ ] 增加前端测试，覆盖新建 item、添加 fragment、保存后重载、删除 fragment、picker 写回、摘要更新
- [ ] 增加 workspace / host 集成测试
- [ ] 覆盖 `load_item_workspace`、save 时交叉引用校验、effect / item 引用错误映射

---

## 6. NPC AI

Rust / Bevy 侧 AI backlog 已基本完成，当前仅保留 Godot 只读表现同步：

- [ ] 输出 NPC 当前目标、当前动作、动作阶段、地点锚点
- [ ] 输出值班状态、警戒状态、睡眠状态
- [ ] Godot 侧只消费状态，不复制规划逻辑

---

## 7. 调试与验证补强

### 7.1 `bevy_debug_viewer` 交互调试继续补强

- [ ] 继续补完整 option payload 展示
- [ ] 补 pending interaction、pending movement、inventory、地图上下文展示
- [ ] 补对话动作结果展示
- [ ] 补不可执行交互的失败原因展示

### 7.2 交互专项测试

- [ ] 增加接近后自动执行 attack / talk / scene transition 的测试
- [ ] 增加敌对切换时 interaction prompt 顺序变化测试
- [ ] 增加地图对象切换后 prompt 刷新测试
- [ ] 增加对话分支与动作节点共享运行时测试

---

## 8. 当前优先顺序

建议继续按以下顺序推进：

1. `save / load snapshot`
2. `dialogue runtime` 真正下沉
3. `game_protocol` 完整 gameplay surface
4. `bevy_server` 本地 transport
5. Godot 协议前端化
6. 旧交互实现退役
7. NPC AI 的 Godot 只读表现同步
8. Item Editor 的 registry / lint / report / tests

---

## 9. 继续沿用的原则

- `逻辑` 继续优先下沉到 Rust / Bevy
- `表现` 继续留在 Godot
- `编辑` 继续向独立工具迁移
- 避免为了短期方便重新强化 Godot 对核心逻辑的承载
- 所有改动优先选择可验证、可回退的小步推进
