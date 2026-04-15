# Bevy 编辑器架构评审

## 范围

本文记录当前仓库内 Bevy 编辑器的结构性问题、风险等级和建议优化顺序，覆盖：

- `rust/apps/bevy_map_editor`
- `rust/apps/bevy_character_editor`
- `rust/apps/bevy_item_editor`
- `rust/apps/bevy_recipe_editor`
- `rust/apps/bevy_gltf_viewer`

本文主要基于本地代码结构检查，以及最近对 `bevy_item_editor`、`bevy_recipe_editor` 的实际 smoke 结果整理，不是完整的交互产品设计文档。

## 当前总体判断

当前这批编辑器已经形成了可用的 Bevy 路线：

- 有独立启动入口
- 有运行日志
- 有窗口尺寸持久化
- `item editor` / `recipe editor` 已经建立 AI proposal -> apply -> save 的工作流
- `item editor` 已经复用 glTF viewer 风格的模型预览

但结构层面已经出现几个明显问题：

- 编辑器壳层重复实现较多
- `UI / AI workflow / 工作区动作` 混在大文件中
- `item` / `recipe` 的 service 与 workspace 逻辑开始平行复制
- 编辑器间跳转仍是特例式实现
- 几个关键系统在壳层缺失时仍会直接 panic

这些问题如果不尽快收口，后面每新增一个编辑器，都会继续复制现有模式，维护成本会快速上升。

## 优先级结论

### P1：优先尽快处理

1. 抽共享的 Bevy 编辑器壳层
2. 拆分几个已经失控的大文件
3. 抽共享的文件型内容编辑 service / workspace 动作层
4. 把 item-only 的 handoff 扩展成通用 editor handoff

### P2：应尽快跟进

1. 把关键 `expect` / `panic` 改成更明确的错误界面或启动期失败信号
2. 为 AI-only 编辑器补更强的草稿恢复与 review 能力
3. 增加自动化 smoke，减少“能编译但打开就是坏的”问题

### P3：中期优化

1. 收口 Tauri 剩余主壳的启动和窗口路由职责
2. 继续统一编辑器的列表、工具栏、状态栏和日志体验

## 详细问题

### 1. 共享编辑器壳层没有收口

#### 现象

多个编辑器都各自实现了以下装配逻辑：

- 运行日志初始化
- `WindowSizePersistenceConfig`
- `build_persisted_primary_window`
- `EguiPlugin`
- `PrimaryEguiContext`
- `EguiPrimaryContextPass`
- 常用 `Update` / `Startup` system wiring

相关位置：

- `rust/apps/bevy_item_editor/src/app.rs`
- `rust/apps/bevy_recipe_editor/src/app.rs`
- `rust/apps/bevy_character_editor/src/app.rs`
- `rust/apps/bevy_map_editor/src/app.rs`

#### 风险

- 同类问题会在不同编辑器里反复出现
- 新编辑器容易忘掉某个必需装配步骤
- 这次 `recipe editor` 灰屏，本质就是壳层配置漂移导致 `PrimaryEguiContext` 不存在

#### 建议

在 `game_editor` 或 `game_bevy` 中抽一个共享壳层，例如：

- `BevyEditorShellPlugin`
- 或一组统一 builder/helper

至少收口以下内容：

- 日志初始化
- 主窗口构建
- 窗口尺寸持久化
- `PrimaryEguiContext` camera 创建
- `EguiPrimaryContextPass` 调度位置
- 常用 editor app 启动模板

目标不是把所有编辑器都塞进一个大插件，而是把“每个编辑器都必须正确装配的最小公共骨架”固定下来。

### 2. 大文件已经明显超出仓库约束

#### 现象

当前若干文件已经明显超出仓库中对模块规模的建议边界：

- `rust/apps/bevy_character_editor/src/ui/ai_tab.rs`
- `rust/apps/bevy_map_editor/src/map_ai.rs`
- `rust/apps/bevy_recipe_editor/src/ui.rs`
- `rust/apps/bevy_item_editor/src/ui.rs`

其中：

- `character_editor` 的 AI tab 已经承担多个完全不同的面板与分析视图
- `map_editor` 的 AI 文件同时包含 prompt payload、proposal review、delta 计算、UI render
- `recipe_editor` UI 同时承担列表、详情、导航、工作区动作、AI panel、settings panel
- `item_editor` UI 也已经开始出现同类趋势

#### 风险

- 每加一个功能点，修改范围都会放大
- review 难度和回归风险显著上升
- 以后很难把“结构性复用”从这些文件中再抽出来

#### 建议

优先按职责拆分，而不是继续往原文件加代码。

推荐拆分方向：

- `item_editor/ui.rs`
  - `list_panel.rs`
  - `detail_panel.rs`
  - `toolbar.rs`
  - `workspace_actions.rs`
  - `ai_panel.rs`

- `recipe_editor/ui.rs`
  - `list_panel.rs`
  - `detail_panel.rs`
  - `item_links.rs`
  - `workspace_actions.rs`
  - `ai_panel.rs`

- `map_editor/map_ai.rs`
  - `prompt_payload.rs`
  - `proposal_parser.rs`
  - `proposal_review.rs`
  - `delta.rs`
  - `ui.rs`

- `character_editor/ui/ai_tab.rs`
  - `scene_controls.rs`
  - `goal_analysis.rs`
  - `action_analysis.rs`
  - `condition_trace.rs`
  - `diagnostics.rs`

### 3. `ItemEditorService` 和 `RecipeEditorService` 出现平行复制

#### 现象

这两个 service 的职责模型基本一致：

- 加载目录下所有文档
- 校验定义
- 保存定义
- 删除定义
- 处理 rename 后旧文件删除
- 返回操作摘要
- 维护相似的 `relative_to_root` / `temporary_path_for` / duplicate id 逻辑

相关位置：

- `rust/crates/game_data/src/item_edit.rs`
- `rust/crates/game_data/src/recipe_edit.rs`

#### 风险

- 继续新增 `quest`、`dialogue`、`effect`、`skill` 编辑器时，会继续复制同样结构
- 同类 bug 需要修多处
- 不同 service 容易在原子写盘、路径归一化、重复 id 处理上逐渐漂移

#### 建议

抽一个共享的文件型编辑 service 基础层，例如：

- `FileBackedContentEditorService<TDocument, TId>`
- 或一组更小的共享 helper：
  - `scan_json_documents`
  - `write_json_atomically`
  - `relative_path_from_data_root`
  - `detect_duplicate_ids`

建议让具体 service 只保留：

- schema 解析
- id 提取
- 领域校验 catalog 构建
- 领域特定 diagnostic 转换

### 4. `item` / `recipe` 的 workspace 动作层重复度高

#### 现象

`item editor` 和 `recipe editor` 都有一组高度相似的动作：

- `Reload`
- `Validate Current`
- `Save Current`
- `Save All Dirty`
- `Delete Current`

而且 UI 文件内都直接承担了：

- 当前选中 key 读取
- dirty 检查
- duplicate id 检查
- 重新插入 document map
- 更新 `selected_document_key`
- 更新 `last_save_message`

相关位置：

- `rust/apps/bevy_item_editor/src/ui.rs`
- `rust/apps/bevy_recipe_editor/src/ui.rs`

#### 风险

- 每个编辑器都要再写一遍 workspace 行为
- 状态切换逻辑更容易出现微妙分叉
- UI 层承载过多“文档事务”逻辑

#### 建议

抽一个通用工作区层，例如：

- `WorkingDocumentStore`
- `WorkspaceAction`
- `WorkspaceSaveResult`

让 UI 只负责发出动作，具体 document map 变更放到共享逻辑中。

### 5. 编辑器间跳转还是 item-only 特例

#### 现象

目前 `recipe editor -> item editor` 的跳转采用：

- 本地 JSON request 文件
- `run_bevy_item_editor.bat --select-item <id>`
- `WScript.Shell.AppActivate(pid)` 尝试前置窗口

相关位置：

- `rust/apps/bevy_recipe_editor/src/navigation.rs`
- `rust/crates/game_editor/src/editor_handoff.rs`

#### 风险

- 当前实现只适用于 `item editor`
- 后续如果 `map -> item`、`quest -> dialogue`、`character -> item` 也要跳转，会迅速出现点对点特例文件
- Windows 聚焦逻辑也会不断重复

#### 建议

把 handoff 协议升级为通用 editor navigation 层，例如：

- `editor_kind`
- `target_kind`
- `target_id`
- `action`

再由各编辑器注册自己的 consumer，而不是继续扩展 item-only API。

### 6. 关键 UI 系统仍会在壳层错误时直接 panic

#### 现象

多个编辑器在获取 `EguiContexts::ctx_mut()` 时依赖 `expect(...)`：

- `rust/apps/bevy_item_editor/src/ui.rs`
- `rust/apps/bevy_recipe_editor/src/ui.rs`
- `rust/apps/bevy_map_editor/src/ui.rs`
- `rust/apps/bevy_character_editor/src/ui.rs`

#### 风险

- 启动配置稍有错误就会直接崩
- 失败体验过于生硬
- 如果 stdout/stderr 没被用户直接看到，只会表现成“打开后灰屏/消失”

#### 建议

保留开发期强校验，但把表现方式改成更明确的失败信号：

- 启动时显式检查 shell 是否正确装配
- 写入结构化日志
- 必要时显示错误面板，而不是直接进入无内容窗口

对于运行期错误，优先显示可操作的错误状态，而不是只依赖 panic。

### 7. 缺少最小自动化 smoke

#### 现象

当前虽然已经有：

- `cargo check`
- 运行日志
- bat 启动入口

但还缺最小自动 smoke，用来验证：

- 进程能否启动并维持存活
- 主窗口是否存在
- 日志是否生成
- 关键编辑器是否能进入基本可见状态

#### 风险

- 会反复出现“编译通过，但打开就是坏的”问题
- UI 壳层错误只能靠人工点开后发现

#### 建议

先加最小版本，不需要一开始就做复杂 UI 自动化：

- 启动目标编辑器
- 等待几秒
- 检查进程未退出
- 检查最新日志文件存在
- 记录截图到 `.local/smoke`

优先覆盖：

- `bevy_item_editor`
- `bevy_recipe_editor`
- `bevy_character_editor`
- `bevy_map_editor`

### 8. AI-only 编辑器还缺更强的草稿恢复能力

#### 现象

当前 `item editor` 和 `recipe editor` 已经具备：

- AI 对话
- proposal review
- apply proposal
- save

但草稿恢复能力还偏弱，proposal 一旦被下一轮结果覆盖，回滚成本较高。

#### 风险

- 用户更依赖 AI 时，proposal 的可追溯性会变得更重要
- 编辑器不像手工表单那样可以逐字段回退

#### 建议

考虑增加轻量恢复能力：

- 最近一次 proposal 缓存
- 最近几次 proposal 历史
- apply 前后的 diff 视图
- “恢复到上一个草稿” 按钮

这比补手工字段编辑更符合当前设计方向。

### 9. Tauri 剩余主壳仍需继续收口

#### 现象

`tools/tauri_editor/src/App.tsx` 目前仍承担较多职责：

- 启动 surface 判断
- 主窗口 bootstrap
- fallback workspace 加载
- window 路由
- 菜单桥接

目前问题不算最急，但结构上已经偏重。

#### 建议

后续继续拆：

- `startup bootstrap`
- `surface routing`
- `workspace loading`
- `menu bridge registration`

避免 `App.tsx` 再次膨胀成新的中心文件。

## 建议的实施顺序

### 第一阶段：先处理最容易继续制造 bug 的部分

1. 抽共享 `BevyEditorShell`
2. 补基础 smoke
3. 去掉关键 UI 的直接 `expect` 崩溃路径

### 第二阶段：开始真正收口重复逻辑

1. 抽通用 workspace action 层
2. 抽共享文件型内容编辑 service
3. 升级 editor handoff 为通用协议

### 第三阶段：拆大文件

1. 先拆 `map_ai.rs`
2. 再拆 `character_editor/ui/ai_tab.rs`
3. 再拆 `recipe_editor/ui.rs`
4. 最后拆 `item_editor/ui.rs`

## 不建议的方向

以下做法不建议继续推进：

- 不要把新的复杂编辑器逻辑继续堆进当前几个超大 UI 文件
- 不要为每个新编辑器重复写一套启动壳、日志壳、egui 主上下文装配
- 不要继续新增 item-only、recipe-only 的 handoff 临时协议
- 不要把共享数据读写和校验逻辑再塞回各编辑器 UI 层

## 一句话总结

当前这批 Bevy 编辑器方向是对的，但下一步不该继续“加功能”，而应该优先“收壳、拆文件、抽复用层”，否则未来每新增一个编辑器都会把现在的重复问题再复制一遍。
