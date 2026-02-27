# CDC Survival Game - AI Agent 开发工作流

## 概述
本项目使用AI Agent自动化开发流程，从需求到交付的全自动化 pipeline。

---

## 开发流程 (带审批版)

```
你提出需求
    ↓
Step 1: Coordinator 解析需求
    ↓
Step 2: Designer 技术设计
    ↓
Step 3: Planner 详细规划
    ↓
🛑 【等待你确认】
    ↓
Step 4: Developer 开发代码
    ↓
Step 5: Tester 自动测试
    ↓
Step 6: Reviewer 验收
    ↓
通知你结果
```

---

## 使用方式

### 提出需求
直接告诉我想开发什么功能，例如：
- "添加一个商人NPC，可以交易物品"
- "创建一个新的敌人种类：变异狗"
- "修复背包容量显示的bug"

### 审批流程
我会给你详细的开发计划，包括：
- 新建文件清单
- 修改文件清单
- 预计开发时间
- 风险说明

**你的选项**:
- ✅ **"确认"** → 开始开发
- 📝 **"修改：XXX"** → 提出修改意见
- ❌ **"取消"** → 终止任务

---

## 各Agent职责

### Coordinator (协调员)
- 解析你的需求
- 分解任务
- 分配给其他Agent

### Designer (设计师)
- 设计数据结构
- 设计API接口
- 规划UI布局

### Planner (规划师)
- 生成详细开发计划
- 列出文件清单
- 预估时间和资源

### Developer (开发者)
- 编写代码
- 创建场景文件
- 更新配置文件

### Tester (测试员)
- 语法检查
- 文件完整性检查
- 功能逻辑测试
- 生成测试报告

### Reviewer (验收员)
- 代码质量评估
- 需求符合度检查
- 最终验收

---

## 测试体系 (8层)

1. **语法检查** - GDScript语法错误
2. **文件完整性** - 文件存在、引用有效
3. **场景加载测试** - 所有.tscn可加载
4. **代码规范检查** - 命名、注释规范
5. **单元测试** - 函数逻辑测试
6. **游戏流程测试** - 使用AITestBridge
7. **边界测试** - 极端条件处理
8. **性能测试** - 加载时间、帧率

---

## AITestBridge 自动化测试

### 功能
- 自动运行游戏测试序列
- 模拟玩家操作
- 验证游戏状态
- 生成测试报告

### 使用方式
```gdscript
# 运行主流程测试
await AITestBridge.run_main_flow_test()

# 自定义测试序列
await AITestBridge.run_test_sequence("my_test", [
    {"action": "click", "target": "Door"},
    {"action": "verify", "check": "scene", "expected": "street_a"}
])
```

---

## 文档位置

- **设计文档**: `docs/design/`
- **系统架构**: `docs/design/CORE_SYSTEMS.md`
- **API文档**: 各系统文件内联注释

---

## 版本历史

### v2.0 (2026-02-18)
- 新增审批流程（Planner步骤）
- 用户确认后才开发

### v1.0 (2026-02-16)
- 初始版本
- 6步自动化流程

---

*文档版本: v2.0*
