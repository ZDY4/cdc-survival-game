# NPC AI 三层架构实施文档

## 背景

当前项目希望让据点中的 NPC 具备“像真实生活在世界中一样”的自主行为能力，例如：

- 卫兵按排班执行值守与巡逻
- 到饭点后去吃饭
- 下班后娱乐或休息
- 夜间回家睡觉
- 突发警报时中断当前行为并响应

同时，本项目已经明确采用三端分离方向：

- `Bevy` 承载核心逻辑
- `Godot` 承载渲染、UI、动画和输入
- `Tauri` 承载编辑器能力

因此，NPC AI 的设计也必须遵守同样边界：

- 不继续把核心 AI 规则堆到 `Godot`
- 不把 `Bevy` 变成表现系统
- 共享结构与规则优先沉淀到 `Rust` 层

## 结论

对本项目来说，最合适的方案是三层结构：

- 上层：`Utility AI`
- 中层：`Light GOAP`
- 底层：`Action FSM / Executor`

一句话理解：

- `Utility AI` 决定“现在最该做什么”
- `GOAP` 决定“为了做到这个，需要哪些步骤”
- `FSM` 决定“这一步当前执行到哪里了”

这套分层比“纯状态机”更能支撑排班、需求和环境权衡，也比“纯 GOAP”更稳定、更低成本，更适合据点 NPC 的长期生活模拟。

## 为什么不是单一方案

### 只用状态机的问题

- 排班、需求、岗位、警报、资源占用叠加后，状态机会迅速膨胀
- 逻辑很容易演变成大量 `if/else`
- 维护成本高，扩职业时复用性差

### 只用 GOAP 的问题

- 生活节奏和全天优先级并不是 GOAP 最擅长的问题
- 如果每次都全量规划，计算成本高
- 容易让 planner 承担过多职责，最后变成系统复杂度黑洞

### 只用 Utility AI 的问题

- Utility AI 很适合选目标，但不擅长把目标拆成可靠步骤
- 很容易出现“想吃饭”和“真的吃到饭”之间的逻辑断层

## 推荐的正式架构

```text
┌─────────────────────────────────────────────────────────────┐
│ 上层：Utility AI                                            │
│ 负责：大目标选择、全天节奏、身份/环境/岗位/风险权衡            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 中层：Light GOAP                                            │
│ 负责：将大目标拆成短动作链，保证行为连贯                       │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 底层：Action FSM / Executor                                 │
│ 负责：预订、移动、等待、执行、释放、失败、打断、完成           │
└─────────────────────────────────────────────────────────────┘
```

## 各层职责

### 上层：Utility AI

上层只负责“大目标”，不负责细节执行。

典型职责：

- 现在应该继续值班，还是允许去吃饭
- 当前更应该补饥饿、补睡眠，还是响应岗位缺口
- 遇到警报时是否立刻打断当前行为
- 下班后优先娱乐还是直接回家睡觉

推荐目标集合：

- `RespondThreat`
- `PreserveLife`
- `SatisfyShift`
- `EatMeal`
- `Sleep`
- `RecoverMorale`
- `ReturnHome`
- `IdleSafely`

推荐优先级：

- `RespondThreat` > `PreserveLife` > `SatisfyShift` > `EatMeal` > `Sleep` > `RecoverMorale` > `ReturnHome` > `IdleSafely`

说明：

- 这不是绝对写死的剧情顺序，而是首版据点岗位 NPC 的默认权重顺序
- 后续职业差异优先通过目标权重调整，而不是复制整套 AI

### 中层：Light GOAP

中层只负责“目标拆解”，不直接操作 ECS 世界，不直接做导航和表现。

推荐原则：

- 只规划短链
- 只使用离散事实
- 只在需要时规划，不每帧全量重算

适合放进 GOAP 的事实：

- `Hungry`
- `VeryHungry`
- `Sleepy`
- `Exhausted`
- `NeedMorale`
- `OnShift`
- `ShiftStartingSoon`
- `ThreatDetected`
- `MealWindowOpen`
- `AtHome`
- `AtDutyArea`
- `HasReservedBed`
- `HasReservedMealSeat`
- `GuardCoverageInsufficient`

不适合直接放进 GOAP 的内容：

- 连续 hunger 数值本身
- 精确路径长度
- 动画状态
- Godot 场景树表现状态
- 复杂社交关系矩阵

典型动作集合：

- `TravelToDutyArea`
- `ReserveGuardPost`
- `StandGuard`
- `PatrolRoute`
- `TravelToCanteen`
- `EatMeal`
- `TravelToLeisure`
- `Relax`
- `TravelHome`
- `ReserveBed`
- `Sleep`
- `RaiseAlarm`
- `RespondAlarm`
- `IdleSafely`

### 底层：Action FSM / Executor

底层只负责执行，不做大目标推理。

推荐动作生命周期：

- `AcquireReservation`
- `Travel`
- `Perform`
- `ReleaseReservation`
- `Complete`

典型职责：

- 占用床位、岗哨、座位、娱乐点
- 执行旅行时长
- 执行等待/值守/睡眠等持续动作
- 失败时回报重规划
- 支持被警报打断
- 支持玩家不在场时的离线结算

## 在本项目中的落点

### `rust/crates/game_data`

职责：

- 承载角色 `life` 配置
- 承载 `SettlementDefinition`
- 承载 `SmartObject`、`ScheduleBlock`、`ServiceRules`

当前相关实现：

- [character.rs](/G:/Projects/cdc_survival_game/rust/crates/game_data/src/character.rs)
- [settlement.rs](/G:/Projects/cdc_survival_game/rust/crates/game_data/src/settlement.rs)

建议长期保持为内容权威层，不写运行时执行逻辑。

### `rust/crates/game_core`

职责：

- 承载 Utility 规则
- 承载 GOAP 包装与动作定义
- 承载连续需求到离散事实的转换
- 承载离线动作推进

当前相关实现：

- [utility/mod.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/utility/mod.rs)
- [goap/mod.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/mod.rs)
- [goap/facts.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/facts.rs)
- [goap/goals.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/goals.rs)
- [goap/actions.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/actions.rs)
- [goap/planner.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/planner.rs)
- [goap/plan_runtime.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/plan_runtime.rs)
- [goap/offline_sim.rs](/G:/Projects/cdc_survival_game/rust/crates/game_core/src/goap/offline_sim.rs)

当前状态：

- `select_goal` 已从 GOAP 模块中拆出，成为独立 `utility` 入口
- GOAP 已收窄为“目标到终态要求 + 动作规划”

建议下一步继续把 `utility` 扩成更明确的评分层，例如按职业、岗位、警报、排班和需求来源拆分评分项。

### `rust/crates/game_bevy`

职责：

- 从 ECS 世界收集输入
- 构造 `NpcPlanRequest`
- 维护 `NeedState`、`ScheduleState`、`CurrentGoal`、`CurrentPlan`、`CurrentAction`
- 执行 action runtime
- 维护 smart object reservation
- 生成调试快照

当前相关实现：

- [npc_life.rs](/G:/Projects/cdc_survival_game/rust/crates/game_bevy/src/npc_life.rs)
- [lib.rs](/G:/Projects/cdc_survival_game/rust/crates/game_bevy/src/lib.rs)

### `rust/apps/bevy_server`

职责：

- 装配 headless runtime
- 加载 `CharacterDefinitions`、`MapDefinitions`、`SettlementDefinitions`
- 注册 `SettlementSimulationPlugin` 和 `NpcLifePlugin`

当前相关实现：

- [main.rs](/G:/Projects/cdc_survival_game/rust/apps/bevy_server/src/main.rs)

### `Godot`

职责明确限制为：

- 接收 NPC 当前目标、当前动作、位置和状态
- 做渲染、动画、UI、交互表现

不负责：

- 目标选择
- GOAP 规划
- 需求演化
- smart object 规则

## 推荐数据流

1. `game_bevy` 收集世界状态
2. 将连续需求和环境状态转为离散事实
3. `Utility AI` 选出当前主目标
4. `Light GOAP` 为该目标生成短计划
5. `Action FSM` 逐步执行计划
6. 若执行失败、世界状态变化或高优先级事件出现，则回到第 3 步

## 系统执行顺序建议

建议长期固定以下顺序：

1. 更新时间
2. 更新需求衰减
3. 更新排班状态
4. 收集世界事实
5. 执行 Utility 目标选择
6. 必要时执行 GOAP 规划
7. 执行 Action FSM
8. 应用动作效果
9. 生成调试快照

保持顺序稳定很重要，否则 NPC 行为会出现时序抖动。

## 当前已落地的最小闭环

当前仓库已经实现一版 `guard_only` 最小闭环，目标是先验证方案可行，而不是一次性完成全部职业：

- 支持角色 `life` 配置
- 支持独立 settlement 数据
- 使用 `dogoap` 作为 planner 内核
- 支持卫兵排班、值守、巡逻、吃饭、回家、睡觉
- 支持对象预订冲突后重规划
- 支持警报打断当前行为并重规划
- 支持离线持续模拟

当前样例数据：

- [safehouse_guard_liu.json](/G:/Projects/cdc_survival_game/data/characters/safehouse_guard_liu.json)
- [safehouse_survivor_outpost.json](/G:/Projects/cdc_survival_game/data/settlements/safehouse_survivor_outpost.json)

## 当前实施状态

当前阶段定位：

- 该系统处于“共享 Rust 基础层 + Bevy 运行时样板”阶段
- 已完成 `guard_only` 的最小可运行闭环
- 尚未进入多职业复用、Godot 展示同步和编辑器支持阶段

当前完成度判断：

- 架构方向：已明确
- 核心类型与数据落点：已建立
- 卫兵样板：已可运行
- `Utility` 与 `GOAP` 主边界：已完成首轮拆分
- 多职业扩展：未开始
- Godot 端消费：未开始
- 编辑器工作流：未开始

## 当前已完成项

### 数据层

- 已为 `CharacterDefinition` 增加可选 `life` 配置
- 已增加 `NpcRole`、`ScheduleBlock`、`NeedProfile` 等共享类型
- 已新增 `SettlementDefinition`、`SmartObjectDefinition`、`ServiceRules`
- 已增加 `data/settlements/` 目录和最小 safehouse 样例

### 规则层

- 已接入 `dogoap` 作为纯 Rust planner 内核
- 已新增独立 `utility` 模块负责目标选择
- 已建立连续需求到离散事实的转换
- 已建立目标枚举、动作枚举、计划请求和结果封装
- 已建立离线 action runtime 和多步离线推进逻辑

### Bevy 运行时

- 已增加 `NpcLifePlugin`
- 已增加 `SettlementSimulationPlugin`
- 已增加需求、排班、当前目标、当前计划、当前动作、预订状态等 ECS 组件
- 已支持 smart object reservation
- 已支持警报打断并重规划
- 已支持离线持续模拟

### 验证

- 已补充 `game_data` 的 schema 加载/校验测试
- 已补充 `game_core` 的 GOAP 和离线执行测试
- 已补充 `game_bevy` 的卫兵样板运行时测试
- Rust `cargo test` 已通过

## 当前未完成项

### 架构层未完成

- `Utility AI` 虽已拆为独立模块，但当前评分规则仍然是单文件集中实现
- 目前“目标选择”和“目标到 Goal 的映射”虽然分层了，但仍然共用同一批请求输入结构
- 当前 action 定义仍然偏卫兵样板，没有形成更明确的职业能力集组织方式

### 内容层未完成

- 还没有第二类职业样板
- 还没有 settlement 的多场景/多据点内容模板
- 还没有独立的 patrol route 编辑与校验流程

### 执行层未完成

- 目前以离线持续模拟和轻量执行为主，还没有接入真实在线导航执行
- 还没有与 Godot 的表现同步协议
- 还没有视觉调试界面来显示目标、动作、预订和排班状态

### 工具链未完成

- 还没有在 `tauri_editor` 中提供 settlement 编辑器
- 还没有可视化编辑 `smart_objects`、`schedule`、`routes`
- 还没有 AI 内容校验工具或批处理检查命令

## 当前主要风险

### 风险 1：Utility 与 GOAP 边界继续混合

虽然首轮边界已经拆开，但如果后续又把目标优先级判断写回 GOAP 模块，会导致：

- 目标选择和动作拆解耦合越来越深
- 后续加职业时复用性下降
- 更难调试“为什么选了这个目标”

控制方式：

- 保持 `utility` 作为唯一目标选择入口
- 明确 `Utility` 只输出目标，不直接输出动作链

### 风险 2：GOAP 膨胀为全能系统

如果后续把导航、连续值、表现状态、复杂社交都往 GOAP 里塞，会导致：

- planner 过度复杂
- 性能和可解释性下降
- 很难稳定复用到不同职业

控制方式：

- 强制保持 GOAP 只处理离散事实和短计划
- 复杂执行逻辑继续留在底层 executor

### 风险 3：Bevy 与 Godot 职责重新混乱

如果未来为了快速出效果，把目标选择或规则判断重新写回 Godot，会导致：

- 三端分离方向倒退
- 逻辑重复定义
- 同步与调试成本上升

控制方式：

- Godot 只消费状态，不复制规划逻辑
- 所有核心规则唯一归属 Rust / Bevy

### 风险 4：过早数据化动作系统

如果在行为域还没稳定前就投入编辑器化动作配置，会导致：

- schema 反复变化
- 编辑器维护成本上升
- 大量时间花在不稳定抽象上

控制方式：

- 先以代码注册动作稳定行为域
- 等第二类、第三类职业验证后再决定编辑器化边界

## 当前边界

当前设计明确不覆盖：

- 复杂社交推理
- 长期记忆系统
- 动态对话目标
- 跨据点迁徙
- 编辑器化动作配置
- 复杂战斗策略 AI

这些能力可以后续基于同样分层扩展，但不应该进入首版生活 AI 的核心链路。

## 推荐实施步骤

### P1：完成三层边界固化

- 将当前 `utility` 从单文件扩展为更明确的评分层结构
- 固化 `Utility -> GOAP -> FSM` 的固定接口
- 收敛目前卫兵样例中的硬编码字段命名与评分常量来源

完成标准：

- 目标选择与规划保持分层，不再回退混写
- `NpcPlanRequest` / `NpcPlanResult` 成为稳定接口
- 卫兵行为不因模块拆分发生回归

### P2：扩展第二类职业

推荐优先实现：

- 厨师，或者
- 医生

目标：

- 验证该分层是否能通过“目标权重 + 动作集变化”复用，而不是重新设计一套 AI

完成标准：

- 新职业无需复制整套系统
- 仅通过新增目标偏好、smart object 和动作集即可接入
- 至少完成一个“非卫兵”的完整日常样板

### P3：接入 Godot 同步展示

- 为 Godot 输出 NPC 当前目标、当前动作、位置、排班状态
- 将 Godot 端 NPC 表现与 Rust 侧运行时解耦

完成标准：

- Godot 端只消费状态
- 不在 Godot 中重复实现规划逻辑
- 能在客户端侧观察 NPC 当前目标与当前动作

### P4：编辑器支持

- 在编辑器中可视化编辑 settlement
- 编辑 `smart_objects`、`routes`、`schedule`
- 做内容校验

完成标准：

- AI 生活数据可编辑
- 不再依赖手写 JSON 才能配置据点生活

## 推荐下一步任务单

为了让后续实施更顺，建议按下面顺序推进：

1. 将 `utility` 进一步拆成评分项或策略函数，避免所有目标评分长期堆在一个函数中。
2. 新增第二类职业样板，优先建议“厨师”。
3. 为 `game_bevy` 增加更明确的调试快照字段，覆盖当前目标、动作、预订对象和当前位置。
4. 为 `bevy_server` 增加最小调试输出或调试接口，方便联调。
5. 在 Godot 侧只做状态消费型 NPC 表现同步，不迁回核心逻辑。

## 文档维护规则

为了让本文档长期可用，后续更新建议遵循：

- 每完成一个阶段，更新“当前已完成项”和“当前未完成项”
- 每次新增职业模板，补充到“推荐实施步骤”或新增阶段
- 如果底层运行方式发生变化，先更新“各层职责”和“数据流”
- 如果有实现落地，优先附上实际代码路径，而不是只写概念描述

## 测试建议

### 单元测试

- 连续需求到离散事实转换是否正确
- Utility 目标选择优先级是否正确
- GOAP 是否能生成预期短计划
- 预订冲突时是否触发重规划
- durative action 的执行生命周期是否正确

### 集成测试

- 单个卫兵完整一天行为
- 多卫兵岗位覆盖
- 用餐窗口切换
- 夜间回家睡觉
- 警报打断
- 玩家不在据点时的离线持续推进

### 手动验证

- 启动 `bevy_server`
- 观察调试快照中的目标、计划和当前动作
- 核对不同时间片里 NPC 的地点与行为是否符合排班和需求

## 设计原则总结

这套系统长期应坚持以下原则：

- 大目标用 `Utility AI`
- 目标拆解用 `Light GOAP`
- 具体执行用 `FSM`
- 核心逻辑留在 `Rust / Bevy`
- `Godot` 只做表现消费
- 不让 planner 直接理解整个世界
- 不让执行层反向承担规划职责

## 一句话结论

对本项目来说，最稳的 NPC 生活 AI 方案不是“纯 GOAP”，而是：

`Utility AI 定大目标 + Light GOAP 拆短计划 + FSM 执行具体动作`

这套分层最符合当前三端分离方向，也最适合据点岗位 NPC 的长期生活模拟与后续扩展。
