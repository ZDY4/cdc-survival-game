# 2026-03-24 Bevy Headless Completion Plan

本文件专门服务当前目标：

- 先完全脱离 `Godot` 运行时
- 先在 `Rust / Bevy` 中把完整游戏逻辑跑通
- 当前阶段不优先考虑表现层、动画、UI、场景树接入

这不是“三端分离”的总规划文档，而是接下来一段时间的**headless 逻辑收口执行计划**。

## 1. 当前状态

截至 2026-03-24，Rust 侧已经具备以下 headless 运行时基础：

- `game_data`
  - 已承接 item / recipe / quest / shop / skill 等内容加载入口
- `game_core`
  - 已有网格、阻挡、寻路、自动移动、回合/AP、基础交互、场景上下文快照
  - 已有 headless `economy`
    - 背包
    - 装备槽
    - 弹药装填/消耗
    - 耐久消耗
    - 金钱
    - 技能学习
    - 配方解锁 / 制作
    - 商店买卖
  - 已有战斗主体
    - 攻击距离
    - 命中后伤害 / HP 扣减
    - 击杀
    - 掉落生成
    - XP / 升级 / 点数发放
  - 已有最小 quest runtime
    - `kill`
    - `collect`
    - `start -> objective -> reward -> end`
- `SimulationRuntime`
  - 已能暴露 quest 启动 / 查询
  - 已能暴露 runtime 内部 `economy`
  - 已能挂载 item / skill / recipe / quest / shop library
- `bevy_server`
  - 已能以 headless 方式构建 runtime
  - 已能加载共享内容
  - 已能对 runtime 进行基础 smoke 初始化

当前这条链路已经证明：核心规则不再必须依赖 Godot 才能推进。

## 2. 还没有真正收完的缺口

如果目标是“完整逻辑先在 Bevy/Rust 中跑通”，当前最关键的剩余缺口不是 UI，而是这些 headless 规则域：

### 2.1 缺正式运行时接口的域

- 装备 / 换装 / 装填 / 学技能 / 制作 / 商店买卖 还主要通过 `economy` 直接调用
- 这些能力虽然已经存在，但还没有整理成稳定的 runtime 命令面

### 2.2 缺正式运行时状态持久化

- 还没有权威 `save snapshot / load snapshot`
- 还无法稳定保存：
  - actor runtime state
  - economy state
  - quest state
  - map object runtime delta
  - world context

### 2.3 缺权威 dialogue runtime

- 当前交互能返回 `dialogue_id`
- 但并没有真正的对话状态机、节点推进、选项选择、动作结算

### 2.4 缺权威 map travel / scene transition runtime

- 目前已有上下文快照和 `SceneTransitionRequested`
- 但还没有真正统一的地图切换命令、返回点恢复、子场景切换状态承接

### 2.5 缺“完整 gameplay 可脚本驱动”的协议面

- `game_protocol` 已有基础消息
- 但还没有覆盖完整 headless 游戏所需的命令面和事件面

### 2.6 缺完整 headless 集成回归

- 现在测试更多是域级单测 / 小型集成测试
- 还没有“从开局到移动、交互、战斗、拾取、任务、制作、交易、存档”的长链路 smoke

## 3. 迁移原则

### 3.1 当前阶段优先级

1. 先让 `bevy_server` 成为完整逻辑宿主
2. 先让 `SimulationRuntime` 成为统一 headless 入口
3. 先让 `game_protocol` 成为外部驱动入口
4. 最后才考虑 Godot / debug viewer / UI 如何消费这些能力

### 3.2 当前阶段不要做的事

- 不要为了临时跑通而把规则补回 Godot
- 不要先做 Godot 协议前端，再倒逼 Rust 补逻辑
- 不要继续在 `bevy_server` 外面挂第二份权威 runtime state
- 不要把本该是 runtime 命令的行为，长期留在测试或 demo helper 里

## 4. 推荐执行顺序

## Phase 1. 把现有 economy 能力整理成正式 runtime command surface

目标：

- 让背包、装备、制作、交易、技能学习不再只是“runtime 内部存在”
- 而是成为 `SimulationRuntime` 的正式 headless 操作能力

本阶段要做：

- 在 `game_core` 明确 runtime 级操作入口，至少覆盖：
  - equip item
  - unequip item
  - reload equipped weapon
  - learn skill
  - craft recipe
  - buy from shop
  - sell to shop
- 这些入口统一走 `SimulationRuntime`
- 逐步决定哪些能力需要升级为：
  - `SimulationCommand`
  - 或 `game_protocol` request
- 避免后续 `bevy_server`、测试、debug 工具直接深挖 `economy` 结构体做业务

完成标准：

- headless 客户端不直接操作 `HeadlessEconomyRuntime` 内部字段
- 核心生存经济行为都能通过 runtime 入口完成
- 对应行为都有单测或 runtime 集成测试

## Phase 2. 建立权威 save/load snapshot

目标：

- 让 headless runtime 可以保存和恢复完整游戏状态
- 这是彻底脱离 Godot 的关键门槛

本阶段要做：

- 在 `game_core` 或相邻共享层新增 runtime save model，至少覆盖：
  - actor registry
  - actor positions
  - AP / turn state
  - combat HP / progression
  - economy actor state
  - active / completed quests
  - current map id
  - interaction context
  - runtime-generated pickups / map object deltas
- 提供：
  - `save_snapshot()`
  - `load_snapshot()`
- 为版本升级预留 schema version / migration 位点

完成标准：

- 能从一个运行中的 runtime 导出 snapshot
- 能从 snapshot 重建等价 runtime
- 能验证存档前后：
  - actor 数量一致
  - 玩家背包一致
  - quest 状态一致
  - 地图对象变化一致
  - 当前地图上下文一致

## Phase 3. 完成权威 dialogue runtime

目标：

- 把“返回 dialogue_id”升级为“真正可运行的对话系统”

本阶段要做：

- 在 `game_data` 补齐/确认 dialogue library 的权威加载入口
- 在 `game_core` 增加 `DialogueRuntimeState`
- 明确支持的最小能力：
  - start dialogue
  - read current node
  - enumerate choices
  - choose option
  - apply node actions
  - advance to next node
  - end dialogue
- 先只做 headless 行为闭环
- 暂不为 Godot UI 设计展示细节

完成标准：

- Rust runtime 能独立推进完整一段对话
- 对话动作如果影响：
  - quest
  - item
  - money
  - map travel
  则由 Rust 直接结算

## Phase 4. 完成权威 map travel / scene context runtime

目标：

- 让地图切换与场景上下文不再停留在“发一个 transition 事件”
- 而是成为真正能推进世界状态的 runtime 行为

本阶段要做：

- 在 `game_core` 增加统一地图切换入口
- 统一处理：
  - enter subscene
  - return to overworld
  - outdoor location enter/exit
  - spawn/return point
  - current interaction context refresh
- 切换时同步更新：
  - `GridWorld`
  - 当前 map object 集
  - actor 位置
  - 当前上下文快照

完成标准：

- 不依赖 Godot 场景树，也能在 Rust 侧完成地图切换
- 切换前后的 runtime snapshot 可稳定比较

## Phase 5. 把 gameplay 操作收敛进 `game_protocol`

目标：

- 让 headless runtime 不只可以“在进程内调用”
- 也可以“通过统一协议驱动”

本阶段要做：

- 扩充 `game_protocol`，至少覆盖：
  - runtime snapshot request
  - runtime delta / event push
  - equip / unequip / reload
  - craft / buy / sell
  - learn skill
  - start quest
  - advance dialogue
  - map travel
  - save / load
- 为失败场景补稳定错误语义
- 明确 command id / response / async event 关系

完成标准：

- `bevy_server` 可以只通过协议暴露完整 gameplay 控制面
- 上层工具不需要直接引用 `game_core` 内部类型也能驱动完整流程

## Phase 6. 把 `bevy_server` 升级成长期 runtime host

目标：

- 从“当前 headless demo runner”升级成长期可接客户端的逻辑宿主

本阶段要做：

- 加本地 transport
  - 优先 TCP 或 IPC 其一，先选一个长期方案
- 接入：
  - subscribe snapshot
  - request snapshot
  - command dispatch
  - runtime event stream
  - error channel
- 增加连接生命周期管理：
  - connect
  - disconnect
  - reconnect
  - load initial state

完成标准：

- `bevy_server` 可以长期运行，不再只是启动即退出的 demo
- 外部客户端可完整驱动 gameplay

## Phase 7. 做完整 headless gameplay smoke scenarios

目标：

- 证明“游戏逻辑真的已经能脱离 Godot 跑通”

本阶段要做：

- 增加长链路 smoke tests，至少覆盖：
  - 开局载入
  - 地图移动
  - 拾取
  - 战斗击杀
  - quest 开始 / 推进 / 完成
  - 技能学习
  - 制作
  - 商店交易
  - 地图切换
  - 对话推进
  - 存档 / 读档
- 增加 fixture 或 scenario seed，避免所有测试都手写组装

完成标准：

- 有一组固定 scenario 可以反复证明 headless 逻辑完整闭环
- Godot 不再是验证“完整玩法是否成立”的必要前提

## 5. 每阶段交付门槛

每一阶段完成后都要满足同一组门槛：

- Rust 权威实现已经存在
- 对外入口已经稳定
- 有对应测试或 smoke 验证
- `bevy_server` 能消费该能力
- 没有新增 Godot 规则耦合

## 6. 推荐的最近三步

如果按当前仓库状态继续推进，推荐直接按这三步做：

1. 先做 Phase 1
   - 把 `economy` 的高频能力收敛成正式 runtime command surface
2. 再做 Phase 2
   - 建立权威 save/load snapshot
3. 然后做 Phase 3
   - 把 dialogue runtime 收权到 Rust

原因：

- 这三步完成后，headless runtime 才真正具备“完整游戏逻辑宿主”的雏形
- 也能最大程度减少后面再回头改协议和宿主边界的成本

## 7. 完成判定

可以认为“已基本脱离 Godot 运行时”的判定标准是：

- 游戏主流程可在 `bevy_server` 中独立推进
- 核心规则不再依赖 GDScript 决策
- 存档、对话、地图切换、任务、经济、战斗都由 Rust 权威结算
- Godot 即使完全不接入，headless smoke scenario 仍能跑通

在达到这个标准之前，不建议开始大规模删除 Godot legacy 文件；当前更重要的是先把 Rust 侧补成完整宿主。
