# NarrativeLab Online AI Protocol Plan

## 背景

当前 NarrativeLab 的离线回归已经稳定通过，说明本地产品链路本身可用：

- 对话发送与会话流转可用
- Markdown 显示可用
- patch 应用与保存可用
- 待批准动作与派生文档链路可用

在线模式暴露的问题主要集中在真实模型输出的不稳定性，而不是 NarrativeLab 自身的编辑器链路：

- `clarification` / `options` / `plan` 在真实模型下容易超时或不收敛
- `split-out-character-doc` 容易只返回正文修订，不返回 `create_derived_document`
- `stream` 可以改善感知延迟，但不能单独解决结构化协议不稳定

因此，下一步不建议继续强化“大一统 JSON 输出协议”，而是应当降低单轮请求对模型结构化输出的要求，把协议拆成更窄、更稳的阶段。

## 目标

本计划的目标是：

1. 降低在线请求对单轮复杂 JSON 的依赖。
2. 保持现有离线回归与编辑器行为不回退。
3. 优先解决最值钱的在线失败场景：
   - `split-out-character-doc`
   - `clarification-missing-brief`
   - `options-branching`
   - `plan-complex-task`
4. 让回归报告能明确区分：
   - 产品缺陷
   - 模型波动
   - provider 错误
   - 未分类超时

## 设计原则

- 不改离线回归基线，继续以 stub 场景作为 NarrativeLab 的稳定产品回归。
- 在线路径优先做“协议减负”，不是继续把更多结构强塞给模型。
- 让宿主承担更多推断和补救工作，而不是假设模型每次都严格遵守完整结构。
- 只有宿主无法可靠推断的内容，才要求模型显式结构化输出。
- 优先做最小可回退改动，避免大规模重写现有 NarrativeLab 生成链路。

## 方案总览

建议把当前在线协议从“单轮全量结构化输出”调整为“分阶段窄协议”。

### 阶段 A：短分类

目标：先判断当前回合属于哪一类，而不是同时要求输出所有字段。

输出目标只保留：

- `clarification`
- `options`
- `plan`
- `final_answer`
- `blocked`

要求：

- 返回尽量短
- 优先低 token、低延迟
- 如果分类失败，允许宿主根据自然语言弱结构继续推断

适用原因：

- 当前在线结构化失败主要集中在 `clarification` / `options` / `plan`
- 这类判断不需要正文，也不应与完整正文生成捆绑

### 阶段 B：内容生成

目标：根据阶段 A 的结果，只生成当前模式真正需要的内容。

分支策略：

- 若为 `clarification`：只生成 1 到 3 个问题
- 若为 `options`：只生成 2 到 4 个推进方向
- 若为 `plan`：只生成 3 到 5 步计划
- 若为 `final_answer`：只生成正文或修订稿

要求：

- 不再同时要求 `requested_actions`
- 不再同时承担“正文 + 动作 + 提问 + 计划”多重职责

### 阶段 C：动作补提取

目标：只在必要时单独提取待批准动作。

触发条件：

- 当前回合为 `final_answer`
- 用户需求明显涉及派生文档或待批准动作
- 正文已经生成
- 但 `requested_actions` 为空或不完整

典型场景：

- “把商人老王移出去，单独创建人物设定”
- “基于当前文稿创建一份地点文档”

输出目标只保留：

- `requested_actions`

要求：

- 单轮任务只做动作提取
- 如果没有动作，显式返回空数组
- 若动作缺失，宿主标记为 `model_variance`

## 第一阶段实施重点

建议先做“动作补提取”，再考虑把 `clarification/options/plan` 也改成两段式。

原因：

- 当前最明确、最稳定复现的在线问题是：正文能生成，但 `requested_actions` 缺失
- 这类问题最适合通过“二次补提取”修复
- 改动面最小，收益最大

### 第一阶段具体目标

1. 保留现有 `resolve_narrative_action_intent` 与 `revise_narrative_draft` 主路径。
2. 在 `final_answer` 后新增“动作补提取”分支。
3. 条件满足时自动发起第二次请求，仅提取 `requested_actions`。
4. 将补提取结果并回当前响应。
5. 回归报告记录：
   - 是否走了补提取
   - 补提取是否成功
   - 如果失败，属于 `model_variance` 还是 `provider_error`

### 第一阶段触发条件建议

宿主可按以下规则触发动作补提取：

- `turn_kind == final_answer`
- `requested_actions.length == 0`
- 用户 prompt 包含以下特征之一：
  - “单独创建”
  - “移出去”
  - “拆出”
  - “创建一份”
  - “新建文档”
- 且需求对象明显是可派生文稿：
  - 人物设定
  - 地点设定
  - 任务文档
  - 角色卡

### 第一阶段验收标准

- 离线 `12/12` 不回退
- `online-core` 中：
  - `direct-revise-section` 继续通过
  - `split-out-character-doc` 的 `requested_actions` 成功率明显提升
- 若仍失败，报告中能明确看到：
  - 是否触发补提取
  - provider 错误还是模型波动

## 第二阶段实施重点

在动作补提取稳定后，再把结构化对话类场景拆成短分类 + 内容生成。

### 第二阶段目标

1. 将 `clarification` / `options` / `plan` 改成更短的分类请求。
2. 分类成功后，再发第二轮生成对应内容。
3. 宿主保留弱结构识别兜底。
4. 在线 `online-structured` 的失败从 `timeout_unclassified` 逐步转成：
   - 成功通过
   - 或清晰归类为 `model_variance`

### 第二阶段收益

- 降低单轮 prompt 复杂度
- 降低模型对复杂 JSON 契约的违约率
- 让在线结构化对话更接近真实聊天行为，而不是一次性协议生成

## Stream 的定位

`stream` 仍然建议保留，但它只负责改善前台体验，不作为结构稳定性的主方案。

具体定位：

- 用于更早显示增量内容
- 用于更及时响应取消
- 用于在 provider 可用时降低“卡住”的主观感受

不应期待 `stream` 单独解决的问题：

- 真实模型整体太慢
- 结构化字段缺失
- `requested_actions` 丢失
- `clarification/options/plan` 不收敛

## 回归策略调整

### 离线

继续作为产品能力基线：

- 必须稳定全通过
- 每次协议改动后必跑

### 在线

继续拆分为两档：

- `online-core`
  - `direct-revise-section`
  - `split-out-character-doc`
- `online-structured`
  - `clarification-missing-brief`
  - `options-branching`
  - `plan-complex-task`

预期：

- `online-core` 先稳定
- `online-structured` 后稳定

## 建议实施顺序

1. 增加“动作补提取”请求路径
2. 为补提取增加回归断言与导出字段
3. 重跑离线全量和 `online-core`
4. 观察 `split-out-character-doc` 是否从 `model_variance` 降到通过
5. 再将 `clarification/options/plan` 改为短分类 + 内容生成
6. 重跑 `online-structured`

## 非目标

本计划不包含以下内容：

- 不为旧 Godot 编辑器增加兼容逻辑
- 不改变 NarrativeLab 离线 stub 回归基线
- 不把真实模型在线波动伪装成“通过”
- 不为了追求单轮完美协议而继续扩大 prompt 复杂度

## 成功标准

完成本计划后，应达到以下状态：

- 离线回归继续稳定 `12/12`
- `online-core` 至少稳定通过正文改写与派生动作场景
- `online-structured` 的主要失败不再是纯超时，而是可归因的模型波动或结构不匹配
- NarrativeLab 能在不依赖单轮大 JSON 的前提下，稳定完成真实在线对话与文档编辑
