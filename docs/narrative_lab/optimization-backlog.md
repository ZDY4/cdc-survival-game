# Narrative Lab 后续优化清单

本文记录 `tools/narrative_lab` 在当前重构基础上，仍然值得继续推进的优化点。

目标不是继续“堆功能”，而是把现有 AI 会话能力做得更稳定、更容易维护、更容易验证。

## 当前状态

最近几轮已经完成的收口包括：

- 会话 helper 已从大组件中拆出：
  - `narrativeSessions.ts`
  - `narrativeSessionHelpers.ts`
  - `narrativeSessionFlow.ts`
- `NarrativeWorkspace.tsx` 中大量重复的会话状态更新逻辑已经转为调用纯函数 helper。
- `requested_actions` 后端解析更严格，并补上 Rust 单测。
- patch 构建逻辑对 Markdown 标题更友好，降低了不必要的整篇覆盖回退。
- 前端 vitest 和后端 `cargo test` 已对新抽出的 helper 建立了基础覆盖。

这意味着下一阶段的重点，应该从“初步拆分”转向“继续降低主组件复杂度”和“强化边界验证”。

## P0：继续瘦身 `NarrativeWorkspace`

### 1. 抽离文档状态流

当前仍有一批“文档本地状态更新”留在 `NarrativeWorkspace.tsx`，例如：

- 本地 draft 创建
- 文档 dirty/savedSnapshot/isDraft 状态维护
- 保存后 slug/documentKey remap
- 关闭标签时回滚 saved snapshot
- 删除 draft 与删除已保存文档的分支逻辑

建议新增一个类似 `narrativeDocumentState.ts` 的模块，抽出这些纯逻辑：

- `buildEditableDraftDocument`
- `applySavedDocumentResult`
- `revertDocumentToSavedSnapshot`
- `markDocumentDirtyState`
- `removeDraftDocumentState`

这样主组件会从“既管理会话，又管理文档生命周期”的双重职责里进一步解耦。

建议落点：

- `tools/narrative_lab/src/modules/narrative/narrativeDocumentState.ts`
- `tools/narrative_lab/src/modules/narrative/narrativeDocumentState.test.ts`

### 2. 抽离 request 构建逻辑

`runGeneration()` 虽然已经比之前清晰，但仍然同时承担：

- 读取当前文档与会话
- 组装 user message
- 组装 `NarrativeGenerateRequest`
- 推送“thinking”占位消息
- 调用后端
- 根据结果更新会话和文档

建议把“请求构建”和“发起前状态更新”再拆出去：

- `buildGenerationRequest`
- `buildGenerationUserMessage`
- `beginGenerationSession`

这样 `runGeneration()` 可以更接近：

1. 构建输入
2. 发请求
3. 应用结果

而不是夹杂大量数据拼接细节。

建议落点：

- `tools/narrative_lab/src/modules/narrative/narrativeGenerationFlow.ts`
- `tools/narrative_lab/src/modules/narrative/narrativeGenerationFlow.test.ts`

### 3. 用 reducer/store 取代大量 `setState` 拼接

当前会话与文档虽然已经抽出很多 helper，但主组件仍大量使用：

- `setDocumentAgents((current) => ...)`
- `setDocuments((current) => ...)`
- `setTabState((current) => ...)`

长远看，这仍然会把编排层重新拖回复杂状态机。

后续可以考虑两条路径之一：

- 轻量路径：继续使用 React state，但统一通过 reducer 风格函数更新
- 更彻底路径：用 Zustand 或 `useReducer` 管 Narrative Lab 工作区状态

建议优先选择轻量路径，不必急着引入新库。

## P0：强化 AI 协议边界

### 4. 为 `requested_actions.payload` 建立每种动作的显式校验

目前后端已经会：

- 过滤非法 action type
- 规范化风险级别
- 丢弃空标题动作

但每种 action 的 `payload` 仍然偏宽松。

下一步建议为高频动作逐一建立 payload 校验：

- `apply_candidate_patch` 必须有 `patchId`
- `create_derived_document` 必须有 `docType`
- `rename_active_document` 必须有合法标题
- `set_document_status` 必须是允许的状态值

收益：

- 模型输出即使轻微跑偏，也能安全失败
- 前端错误提示会更明确
- 后端动作执行层更容易写单测

建议落点：

- `tools/narrative_lab/src-tauri/src/narrative_agent_actions.rs`
- `tools/narrative_lab/src-tauri/src/narrative_provider.rs`

### 5. 明确 `preview_only` 的真实语义

现在协议里已有 `preview_only`，但执行层仍偏“协议保留字段”。

建议明确：

- 哪些动作支持 preview
- preview 结果是否只回 summary / diff / document summary
- preview 时是否应禁止真正写盘

这个点不做清楚，后续一旦做“AI 批量整理文档”就容易让协议变得含混。

### 6. 为 turn/result 解析补更多异常场景测试

还值得补测的边界包括：

- `turn_kind` 缺失但有 `draft_markdown`
- 同时返回 `questions` 和 `draft_markdown`
- `options` 数量过少或过多
- `plan_steps` 非法结构
- `requested_actions` 与 `blocked` 同时出现

这里的目标不是让模型“绝不出错”，而是保证解析逻辑在异常输出下仍然稳定。

## P1：优化 patch 与审阅体验

### 7. 继续改进 patch 分块策略

当前 patch 逻辑已经比最初更好，但还可以继续往“文稿结构优先”推进：

- 标题块优先
- 列表块单独处理
- 引用块 / 代码块 / 表格块不与普通段落混合
- 长段内部的微调尽量不要升级成整段替换

如果后续要支持更细粒度的 AI 修改，这一步很关键。

建议落点：

- `tools/narrative_lab/src/modules/narrative/narrativePatches.ts`
- `tools/narrative_lab/src/modules/narrative/narrativePatches.test.ts`

### 8. 让 patch 审阅支持“按标题分组”

现在 patch 虽然可逐个应用，但用户仍需要自己判断 patch 处在文稿的哪个结构区块。

可以考虑在 patch 元数据里加入：

- 所属 heading
- patch 影响的块标题
- patch 类型：replace / insert / delete

这样 UI 上的“建议 1 / 建议 2”会更可读。

### 9. 为“整篇应用”增加更明显的风险提示

`apply_all_suggestions` 很方便，但风险也最高。

建议：

- 当 patch 数较多时，加醒目的提示
- 当 AI 返回的是整篇重写而非稳定 patch 时，提示风险更高
- 可以考虑显示“整篇应用将覆盖 X 个区块”

## P1：上下文与提示质量

### 10. 上下文选择从“显式选择 + relatedDocSlugs”升级到可解释排序

目前上下文来源主要是：

- 主文档
- `selectedContextDocKeys`
- `relatedDocSlugs`
- 后端 `build_narrative_context(...)`

可继续优化的方向：

- 手动选中的上下文优先级最高
- 同类型上下文其次
- 仅在需要时补充 runtime/project context
- UI 上直接展示“本轮实际使用了哪些上下文”

目标是减少“为什么这轮 AI 提到了不相关文档”的困惑。

### 11. 对长上下文建立摘要缓存

如果文稿数量越来越多，每次都喂入大量原文既贵，也容易噪音过高。

后续可以考虑：

- 为文稿缓存短摘要
- AI 上下文优先使用摘要
- 只有当前文稿和手动选中的文稿才优先带原文

这一步能同时降低成本和提升稳定性。

## P1：会话持久化与恢复

### 12. 缩小持久化快照的体积

当前会话持久化已经能用，但随着：

- `chatMessages`
- `versionHistory`
- `actionHistory`
- `pendingDerivedDocuments`

不断增长，配置体积会越来越大。

可以考虑：

- 限制持久化的消息条数
- `versionHistory` 只保留摘要和 requestId
- 对调试信息、diff 预览做裁剪

目标是让“恢复上次会话”保持顺滑，而不是把 app settings 膨胀成重载瓶颈。

### 13. 区分“恢复展示状态”和“恢复执行状态”

目前已经会把恢复后的 `busy/inflightRequestId` 归零，这是对的。

后续可以再明确：

- 哪些状态允许恢复
- 哪些状态只用于临时 UI，不应持久化
- 哪些 review queue 项是根据 session 派生的，不必直接保存

## P2：菜单与回归验证工具化

### 14. 把回归验证用例抽成可扩展清单

目前回归套件已经可用，但仍然在组件附近维护。

建议后续把它抽成：

- 独立 case 定义
- 独立 runner
- 独立结果格式化

这样后面可以更方便扩展 Narrative Lab 的行为自测。

### 15. 为菜单桥接与 AI 命令增加更明确的 smoke test

当前已有菜单测试，但还可以补这类场景：

- 当前没有 active document 时，AI 命令禁用是否正确
- 有 pending action 时，命令可用性是否正确
- 设置窗口打开逻辑是否只触发单例窗口

## P2：工程与构建体验

### 16. 降低 Tauri `dist` 资源 hash 变动带来的测试摩擦

本轮已经碰到过一次：前端 build 后，`src-tauri/target` 里还缓存着旧的资源 hash 依赖，导致 `cargo test` 需要先 clean。

这不是逻辑 bug，但会拖慢迭代。

可考虑的方向：

- 在 Narrative Lab 的开发文档里明确“前端 build 后若 cargo test 报 dist 资源缺失，可先 `cargo clean -p cdc_narrative_lab`”
- 研究是否能让 Tauri 资源引用在本地测试中更稳
- 把这类步骤包装进开发脚本

## 建议实施顺序

建议按下面顺序继续推进：

1. 抽离文档状态流
2. 抽离 generation request 构建
3. 补强 `requested_actions.payload` 校验
4. 优化 patch 元数据与分块
5. 缩小持久化快照体积
6. 最后再考虑 reducer/store 级别重构

原因：

- 前四项最直接降低复杂度和回归风险
- 持久化优化会在会话越来越重时产生明显收益
- reducer/store 适合在 helper 足够稳定后再做，否则容易把重构风险放大

## 验收建议

后续每推进一项优化，建议都至少做以下验证：

- `npm run build`
- 相关 `vitest` 子集
- `cargo test` in `tools/narrative_lab/src-tauri`

如果改动涉及 AI 请求协议、patch 结构或会话恢复，建议额外做一次手动 smoke test：

- 打开一个已有会话文档
- 加入 1 到 2 个上下文文稿
- 发起 revise 请求
- 批准 1 个 action 或 patch
- 保存并重启 Narrative Lab
- 验证会话内容与上下文标签是否仍可恢复
