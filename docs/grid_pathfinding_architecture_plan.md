# 自研网格寻路架构方案

本文记录 Godot 主线下自研寻路系统的推荐方向。目标是在保留远距离 NPC 交互自动接近、AP 制、回合制和 headless 可验证能力的前提下，解决当前 BFS 寻路在远距离和不可达场景中的同步卡顿问题。

## 背景问题

当前寻路入口主要在 `godot/scripts/core/movement/pathfinder.gd`。实现是基于网格的广度优先搜索 BFS：

- 从起点开始向外一圈圈扩张。
- 每个格子检查 8 个方向，包括上下左右和斜向。
- 斜向移动会检查两侧直角边，避免穿墙角。
- 通过 `blocking_cells` 和 `occupied_actor_cells` 判断地图物件与 actor 占位。
- 找到目标后通过 `came_from` 重建路径。
- 如果不可达，会把可达区域尽量扫完后才返回 `path_unreachable`。

这个实现简单、确定，适合早期迁移验证，但在以下场景会变慢：

- 远距离目标：BFS 没有方向感，会从起点向所有方向扩张。
- 不可达目标：失败前需要扫描大量可达格。
- 交互接近：NPC 对话不是走到 NPC 所在格，而是走到 NPC 周围可交互格；当前会对多个候选交互格分别跑一次寻路。
- GDScript 开销：每步创建 `GridCoord`、字符串 key、数组和字典访问，在多次 BFS 中会放大。

### 最严重的病理：不可达时的 N 倍全图扫描

最值得优先解决的不是"远距离有方向感"，而是**交互接近在目标不可达时会触发 N 次完整扫描**。

`approach_goal_for_prompt()` 会生成一组候选交互格，然后逐个调用 `find_path()`。一旦目标整体不可达，每个候选格都会单独跑一次完整的 `path_unreachable` 扫描（扫完整个可达区才返回）。候选格数量随 `interaction_range` 增长（对话默认 range=1 已是 4 格，范围越大候选越多），于是失败路径的成本变成"单次全图扫描 × 候选数"。这是远距离与不可达场景主线程卡顿的首要来源。

同样的"逐候选 find_path 取最短"模式还出现在 `simulation.gd` 的 NPC approach 流程中（见迁移步骤），不止交互处理一处。

## 设计目标

- 保留远距离 NPC 对话、攻击和地图对象交互的自动接近功能。
- 保留格子制、AP 消耗、逐步移动、pending movement 和回合制规则。
- 寻路结果必须确定，同样输入得到同样路径与失败原因。
- 支持 headless smoke 和 profiler 诊断。
- 降低远距离和不可达目标的主线程同步耗时。
- 让交互接近从“多个候选点逐个寻路”改为“一次多目标寻路”。
- 在不重写 simulation 主流程的前提下逐步迁移。

## 非目标

- 不把 Godot `NavigationAgent3D` / NavMesh 作为核心玩法寻路权威。
- 不改成自由连续空间移动；角色仍以格子为规则坐标。
- 不在第一阶段重写 `TurnActionRunner`、AP 规则、世界回合或 AI planner。
- 不把 UI、marker 或 presenter 变成寻路规则来源。

## 为什么不采用 NavMesh 作为核心

NavMesh 适合连续 3D 空间导航和实时避障，但本项目核心规则是格子和 AP：

- AP 消耗需要稳定的“格子步数”，NavMesh 路径点不天然等于规则步数。
- 交互目标通常是一组合法格，例如 NPC 周围 `interaction_range` 内任意可站格。
- 动态 actor 占位需要严格表达“某个格本回合不可进入”，NavMesh avoidance 不等价于规则阻挡。
- 门、地图物件、阻挡和 bounds 已经由 topology 表达；动态 rebake NavMesh 会增加复杂度。
- headless simulation 更需要可解释、可复现、可记录失败原因的规则寻路。

因此推荐：

```text
核心玩法寻路：自研网格 A* / 多目标 A*
表现层平滑或未来自由移动辅助：可选 NavMesh
```

## 推荐架构

### Pathfinder 继续作为唯一底层入口

保留 `Pathfinder` 作为规则层寻路服务，外部仍通过 simulation 调用它。第一阶段保持现有返回结构兼容：

```gdscript
{
    "success": true,
    "path": [
        {"x": 24, "y": 0, "z": 39},
        {"x": 25, "y": 0, "z": 39}
    ],
    "steps": 1,
    "visited_cell_count": 8,
    "pathfinding_time_ms": 0.2
}
```

失败结果继续包含稳定 reason：

```gdscript
{
    "success": false,
    "reason": "path_unreachable",
    "start": {},
    "goal": {},
    "visited_cell_count": 340,
    "pathfinding_time_ms": 12.5
}
```

### 从 BFS 升级为 A*

`find_path(start, goal, topology, occupied_actor_cells)` 应从 BFS 改为 A*：

- open set 按 `f_score = g_score + heuristic` 排序。
- `g_score` 表示已走成本。
- `heuristic` 表示到目标的估计距离。
- 当前若所有移动成本相同，可用 octile distance 适配 8 方向移动。
- 若未来不同地形有不同成本，`g_score` 可以接入 terrain movement cost。

推荐启发式：

```text
dx = abs(a.x - b.x)
dz = abs(a.z - b.z)
octile = max(dx, dz)
```

如果希望斜向和直向都消耗 1 AP，`max(dx, dz)` 与当前 8 方向步数模型最接近。若未来斜向成本改为 1.414，则可改成标准 octile cost。

#### 保留 `start_key` 起点豁免

当前 `find_path()` 全程传递 `start_key`，用于在 `_blocking_info()` 中实现"起点自身被 actor 占位时不算阻挡"。A\* 重写必须原样保留这个豁免参数，否则起点恰好与某个占位格重合的边界场景会回归（例如起点与 `occupied_actor_cells` 命中同一 key 时被误判为不可出发）。

### 新增多目标寻路

交互接近不应该对每个候选格各跑一次 `find_path()`。新增接口：

```gdscript
func find_path_to_any(
    start: RefCounted,
    goals: Array[RefCounted],
    topology: Dictionary,
    occupied_actor_cells: Dictionary = {}
) -> Dictionary:
```

返回内容除现有字段外，增加选中的目标：

```gdscript
{
    "success": true,
    "chosen_goal": {"x": 31, "y": 0, "z": 10},
    "goal_count": 12,
    "path": [],
    "steps": 8,
    "visited_cell_count": 64,
    "pathfinding_time_ms": 1.3
}
```

多目标 A* 的目标集合可以用 `goal_keys` 字典保存。搜索过程中只要当前格 key 在 `goal_keys` 中，就可以返回路径。

对 NPC 对话、攻击接近、开门接近、拾取接近等场景，优先走 `find_path_to_any()`。

#### 多目标启发式必须取 min（保证可采纳）

多目标 BFS 天然返回"扩张顺序中最先到达的目标"，即最短路径目标，与现状"取步数最小候选"等价。但**多目标 A\* 的启发式必须定义为到目标集合中任一目标的最小估计距离**：

```text
h(cell) = min(octile(cell, g) for g in goals)
```

只有这样启发式才可采纳（admissible），第一个从 open set 弹出的目标才保证是全局最短路径目标。若误用"到单个代表目标的距离"或质心，对更近的目标会高估，破坏可采纳性，可能弹出非最短目标，导致 A\* 非最优、`chosen_goal` 与旧 BFS 行为不一致。

交互候选格是聚簇的，`min(octile)` 的逐目标成本很低；若想完全规避这个风险，多目标版本也可以直接令 `h = 0`，退化为 Dijkstra / 一致代价 BFS，结果仍正确，只是损失方向感。建议默认用 min-over-goals，把 `h=0` 作为保守回退。

#### 多目标版本要预过滤被阻挡的候选格

单目标 `find_path()` 对被占/阻挡的 goal 直接返回失败（`:43-51`），由 `approach_goal_for_prompt` 的循环跳过（`:324`）。多目标版本必须在构建 `goal_keys` 前剔除命中 `blocking_cells` / `occupied_actor_cells` 的候选格，**只对剩余合法候选搜索**；不能因为候选集合里某个格被挡就整体返回失败。若全部候选都被挡，才返回失败 reason（如 `goal_all_blocked`）。

#### `chosen_goal` 必须有确定的 tie-break

现状取"步数严格更小"的候选，等长时按候选迭代顺序保留先到者。多目标搜索切换后，等长多候选时选哪个落脚格可能改变，而落脚格会影响角色朝向、后续交互合法性判断与表现。因此 `chosen_goal` 需要一个稳定的 tie-break 规则（建议：等代价时按候选固定顺序选择），并纳入"结果必须确定"的验收范围。

## 规则边界

`Pathfinder` 只负责空间可达性和路径，不决定业务是否可执行。

仍由现有 core 层判断：

- actor 是否存在。
- actor 是否处于 turn_open。
- AP 是否足够。
- 交互选项是否可用。
- 攻击目标是否合法。
- 门是否可自动打开。
- pending movement 是否需要跨回合保留。

`Pathfinder` 接收已经准备好的 topology：

- `bounds`
- `blocking_cells`
- runtime door state 合并后的阻挡
- `occupied_actor_cells`

这样能保持当前 simulation 作为规则权威。

## 数据结构建议

### Grid Key

当前大量使用 `GridCoord.key()` 字符串，例如 `"24:0:39"`。这便于字典查询，但在密集搜索里会产生字符串开销。

第一阶段可以继续保留字符串 key，降低迁移风险。第二阶段可以考虑内部使用整数 key：

```text
packed_key = ((x - min_x) << 16) | (z - min_z)
```

如果未来存在多层地图，则把 `y` 纳入 key。对外结果仍返回 `{x, y, z}`。

### Priority Queue

A* 需要优先队列。GDScript 第一版可先实现小型 binary heap：

```gdscript
push(item, priority)
pop_min()
is_empty()
```

不要用每步 `Array.sort_custom()`，否则节点多时会把 A* 优势吃掉。

为保证确定性，堆的比较键不能只用 `f_score`：`f_score` 相等时若不带稳定次序，弹出顺序依赖插入/堆化细节，会导致同输入产生不同路径。比较键应为 `(f_score, insertion_seq)`，其中 `insertion_seq` 是每次 `push` 递增的整数计数器：

```text
比较：先比 f_score，相等再比 insertion_seq（小者先出）
```

这样同输入恒定得到同一条路径，满足"结果必须确定"的目标，也让 smoke 路径点位可复现。

### Search Result

建议所有寻路结果增加诊断字段：

- `algorithm`: `"astar"` / `"multi_goal_astar"`
- `visited_cell_count`
- `expanded_cell_count`
- `max_frontier_size`
- `goal_count`
- `chosen_goal`
- `pathfinding_time_ms`
- `budget_exceeded`

这些字段进入 profiler 和 smoke 日志，不作为 UI 常规展示。

## 性能保护

即使使用 A*，也需要预算保护，避免异常地图或坏数据卡住主线程。

建议参数：

```gdscript
const DEFAULT_MAX_VISITED_CELLS := 2048
const DEFAULT_TIME_BUDGET_MS := 8.0
```

达到预算时返回：

```gdscript
{
    "success": false,
    "reason": "pathfinding_budget_exceeded",
    "visited_cell_count": 2048,
    "pathfinding_time_ms": 8.1
}
```

预算保护只阻止单次寻路卡住主线程，不代表永久不可达。后续可以配合分帧寻路继续规划。

## 缓存策略

第一阶段可以不做全局缓存，先完成 A* 和多目标寻路。第二阶段增加小型 LRU 缓存：

缓存 key 建议包含：

- map id
- start key
- goal key 或 goal set hash
- bounds / blocking revision
- door state revision
- occupied actor revision
- movement profile id

缓存值保存：

- path
- chosen_goal
- steps
- failure reason
- topology revision

缓存适用场景：

- hover preview 与 execute 连续请求同一目标。
- 玩家反复点击同一个 NPC。
- 同一回合多次查询同一目标。

缓存不应跨地图结构变化、门状态变化或 actor 占位变化复用。

## 交互接近改造

### 受影响的候选-逐个寻路站点

"生成候选格再逐个 `find_path()` 取最短" 的模式不止一处，迁移时需一并切换，否则只优化了玩家交互而漏掉 NPC：

- `InteractionCommandHandler.approach_goal_for_prompt()`：玩家对话、攻击、map object 交互接近。
- `simulation.gd` 的 NPC approach 流程（`_npc_approach_*` 一带）：AI 走向目标 actor 的相邻可站格，同样逐候选 `find_path()` 取最短。

两处都应统一切到 `find_path_to_any()`。

当前 `InteractionCommandHandler.approach_goal_for_prompt()` 会先生成候选格，然后逐个 `find_path()`。

目标形态：

```gdscript
var candidates: Array[RefCounted] = interaction_goals(...)
var plan := simulation._pathfinder.find_path_to_any(
    actor.grid_position,
    candidates,
    topology,
    simulation._occupied_actor_cells(actor.actor_id)
)
if not plan.success:
    return null
return plan.chosen_goal
```

更进一步，可以让 `begin_interaction_approach_for_runner()` 直接拿到完整 `plan`，避免先算一次目标、再由 `begin_move()` 对同一目标重新算一次路径。

推荐新增内部 helper：

```gdscript
func approach_plan_for_prompt(simulation, actor, prompt, topology) -> Dictionary
```

它返回完整 plan，而不是只返回目标格。

## 迁移步骤

### 阶段 1：多目标 BFS，先去掉重复搜索

- 新增 `find_path_to_any()`，内部先复用 BFS（单次扩张、命中目标集合任一格即返回）。
- `approach_goal_for_prompt()` 改成一次多目标搜索。
- `simulation.gd` 的 NPC approach 流程一并切到 `find_path_to_any()`。
- 保持 `find_path()` 不变。
- 验证远距离 NPC 交互和 map object 交互。

这一阶段风险最低，收益最大：把不可达场景从"N 次全图扫描"降到一次，并直接消除“候选格数量倍增”的卡顿。注意保持 `chosen_goal` 的 tie-break 与旧实现一致（等长按候选顺序）。

注意：仅这一步只是把 `N` 次候选搜索降到 `1` 次目标搜索，但接近流程整体仍是 `1 + 1`——`find_path_to_any()` 算出 plan 后被丢弃，随后 `begin_move()`（及 `approach_then_execute_interaction` 的 `:208`）对同一目标又算了一次。要真正落地正文 `approach_plan_for_prompt()` 的优化，必须同时做下面这步。

### 阶段 1b：让 begin_move / 接近流程复用已算好的 plan

- 新增 `approach_plan_for_prompt()`，返回完整 plan（含 `chosen_goal` 与 `path`），而不仅是目标格。
- `begin_move()` 增加可选入参，接受预先算好的 `path` / `plan`；提供时跳过内部 `find_path()`，直接用该路径建立 `pending_movement`。
- `begin_interaction_approach_for_runner()` 与 `approach_then_execute_interaction()` 改为传入 plan，去掉 `:208`、`:276` 处的二次寻路。
- 校验：接近流程的底层搜索调用次数从 `1 + 1` 降到 `1`（可用 profiler 计数断言）。

把这一步与阶段 1 一起做，否则 `:312` 的优化永远不会落地。

### 阶段 2：A* 替换单目标 BFS

- 实现 binary heap。
- `find_path()` 切换为 A*。
- 保持返回结构不变。
- 增加 `algorithm`、frontier 和 visited 诊断字段。
- 对比 BFS 与 A* 在 smoke 场景中的路径长度和可达性。

### 阶段 3：多目标 A*

- `find_path_to_any()` 切换为多目标 A*。
- 交互接近、NPC approach 和攻击接近统一使用多目标接口。
- 记录 `goal_count`、`chosen_goal` 和 `visited_cell_count`。

### 阶段 4：预算保护与缓存

- 增加 visited / time budget。
- 增加小型 LRU 缓存。
- hover preview 与 execute 共享缓存。
- 连续点击同目标不重复全量搜索。

### 阶段 5：分帧规划

如果仍存在大型地图长路径卡顿，再新增分帧寻路 job：

- 点击后创建 pathfinding job。
- 每帧扩展有限节点数。
- UI 显示规划中或移动准备中。
- 规划完成后交给 `TurnActionRunner` 开始移动。

分帧是最后阶段，不应先于 A* 和多目标搜索实施。

## 验收标准

必须保留：

- 远距离 NPC 对话自动接近。
- 远距离 map object 自动接近。
- AP 不足时 pending movement 语义。
- 逐格移动表现和 `TurnActionRunner` 阶段推进。
- `path_unreachable` 等稳定失败 reason。

建议 profiler 指标：

- 单次寻路（`find_path` / `find_path_to_any`）主线程同步耗时低于 `DEFAULT_TIME_BUDGET_MS`（8ms，约半帧）。这是寻路本身的阈值，与上面的预算保护一致。
- 远距离 NPC talk **端到端**执行同步耗时低于 100ms。注意：此 100ms 是包含寻路 + 交互结算 + 事件发射 + 快照重建的整条命令链上限，不是寻路单项阈值；寻路单项应远低于此，落在 8ms 预算内。
- 不可达目标不会超过预算阈值。
- 多目标交互接近只调用一次底层搜索（接近流程整体降到 `1` 次，见阶段 1b）。
- `visited_cell_count` 明显低于旧 BFS 多候选点累计值。
- hover preview 和 execute 连续调用可命中缓存。

建议 smoke：

- `tools/agent/test-godot-game.ps1 -Scenario PlayerInteraction`
- `tools/agent/test-godot-game.ps1 -Scenario Combat`
- `tools/agent/test-godot-game.ps1 -Scenario UI`
- 目标脚本 `--check-only`

## 风险与注意事项

- A* 的 tie-break 会影响同等长度路径选择，可能导致 smoke 里路径具体点位变化。需要保证“长度正确、合法、确定”，不要依赖旧 BFS 的任意路径顺序。
- 多目标搜索的 `chosen_goal` 在等长多候选时可能与旧实现选不同落脚格，进而影响朝向与后续交互判定。必须给定稳定 tie-break 并纳入验收。
- 多目标 A* 启发式必须取"到目标集合最小距离"，否则不可采纳，可能返回非最短目标。
- 候选交互格由 `interaction_goals()` 用曼哈顿距离 `abs(dx)+abs(dz)` 生成（菱形环），而移动是 8 方向、启发式用 octile。计算"到目标集合最小距离"时应基于实际候选格集合，不要用解析公式近似目标形状。
- `start_key` 起点豁免必须在 A* / 多目标重写中保留，避免起点与占位格同 key 的边界回归。
- 若斜向移动仍消耗 1 AP，启发式必须与该成本一致，避免 A* 非最优。
- 自动开门 topology 必须在寻路前准备好，避免路径认为门阻挡但执行时又打开。
- 预算保护不能静默吞掉交互，应返回稳定 reason 供 UI 和日志展示。
- 缓存必须绑定 topology revision，不能在门状态或 actor 占位变化后复用旧路径。

## 推荐优先级

最高优先级：

1. `find_path_to_any()`。
2. 交互接近改为一次多目标搜索。
3. 单目标 A*。

中优先级：

1. 多目标 A*。
2. profiling 诊断字段。
3. 预算保护。

低优先级：

1. 路径缓存。
2. 整数 packed key。
3. 分帧寻路 job。

整体方向是：不要牺牲远距离自动寻路功能，而是把当前同步、多次、无方向感的 BFS，演进成适合回合制格子玩法的确定性 A* 寻路服务。
