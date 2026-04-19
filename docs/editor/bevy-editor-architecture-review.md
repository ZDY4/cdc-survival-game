# Bevy 编辑器架构评审

## 范围

本文只记录当前仓库内 **仍值得继续优化** 的编辑器结构问题，覆盖：

- `rust/apps/bevy_map_editor`
- `rust/apps/bevy_character_editor`
- `rust/apps/bevy_item_editor`
- `rust/apps/bevy_recipe_editor`
- `rust/apps/bevy_gltf_viewer`
- `tools/tauri_editor`

已完成收口的部分不再重复记录。

## 当前判断

当前剩下的高价值问题已经收敛到两项：

- AI editor 的草稿恢复能力仍偏弱
- Tauri 主壳还有继续收口空间

## 下一轮做

### 1. 给 AI-only 编辑器补更强的草稿恢复与 review 能力

当前 `item editor` 和 `recipe editor` 已具备：

- AI 对话
- proposal review
- apply proposal
- save

但 proposal 的恢复与回看能力仍然偏弱。用户越依赖 AI，这个问题越明显。

建议补的能力保持轻量：

- 最近一次 proposal 缓存
- 最近几次 proposal 历史
- apply 前后的 diff 视图
- “恢复到上一个草稿” 按钮

这项很有价值，但优先级仍低于“拆剩余超大文件”和“补 smoke”，因为它更多是在增强体验，而不是先消掉当前最大的维护风险。

## 以后再做

### 2. 继续收口 `tools/tauri_editor/src/App.tsx`

`tools/tauri_editor/src/App.tsx` 目前仍承担：

- 启动 surface 判断
- 主窗口 bootstrap
- fallback workspace 加载
- window 路由
- 菜单桥接

这件事仍然有价值，但它更偏“预防后续膨胀”，而不是当前最急的结构风险。和 `map_ai.rs` / `ai_tab.rs` 相比，它的收益没有那么立刻。

后续可以继续拆：

- `startup bootstrap`
- `surface routing`
- `workspace loading`
- `menu bridge registration`

## 不建议的方向

- 不要在 Tauri 侧继续把 startup、window routing、workspace bootstrap 叠回 `App.tsx`

## 一句话总结

当前下一步最值得做的是补 AI 草稿恢复；Tauri 主壳收口继续放到后续中期整理。
