# CDC 末日生存游戏 - 测试框架使用指南

## 🎯 快速开始

### 运行所有测试
```bash
python run_tests.py --all
```

### 只运行冒烟测试
```bash
python run_tests.py --sanity
```

### 运行功能测试
```bash
python run_tests.py --functional
```

### 运行Agent测试
```bash
# 需要先启动游戏
python run_tests.py --agent
```

---

## 🏗️ 测试架构

### 三层测试模型

```
Sanity Test (30秒)
        ↓ PASS
Functional Test (5分钟)
        ↓ PASS
Agent Test (30分钟+)
```

**执行规则**:
- Sanity 失败 → 停止，修复基础问题
- Functional 失败 → 停止，修复功能bug
- Functional 通过 → 可以运行 Agent 测试

---

## 📝 测试类型说明

### 1. Sanity Test (冒烟测试)
**目的**: 快速验证项目完整性
**时间**: < 30秒
**检查项**:
- ✅ 项目文件存在
- ✅ 模块文件完整
- ✅ 场景文件正确
- ✅ Autoload配置正确

### 2. Functional Test (功能测试)
**目的**: 程序化验证所有功能
**时间**: 5-10分钟
**包含**:
- 单元测试 (每个模块独立测试)
- 集成测试 (模块间协作)
- 场景测试 (加载和切换)
- 数据测试 (存档/读档一致性)

### 3. Agent Test (AI测试)
**目的**: 智能探索发现潜在问题
**时间**: 30分钟-数小时
**特点**:
- 模拟真实玩家行为
- 发现边界情况
- 长期稳定性测试
- 随机探索游戏世界

---

## 📊 测试结果解读

### 通过标准

| 层级 | 通过标准 |
|------|---------|
| Sanity | 100% 通过 |
| Functional | P0: 100%, P1: >95%, P2: >80% |
| Agent | 无崩溃，发现的问题可接受 |

### 报告位置
```
tests/results/
├── sanity_report.json       # 冒烟测试报告
├── functional_report.json   # 功能测试报告
├── agent_report.json        # Agent测试报告
└── final_report.json        # 综合报告
```

---

## 🔧 添加新测试

### 添加单元测试
```gdscript
# tests/functional/unit/test_your_module.gd

static func run_tests(runner: TestRunner) -> void:
    runner.register_test(
        "test_name",
        TestRunner.TestLayer.FUNCTIONAL,
        TestRunner.TestPriority.P1_MAJOR,
        _test_function
    )

static func _test_function() -> void:
    # 测试代码
    assert(condition, "Error message")
```

### 添加Agent测试
```python
# tests/agent/test_custom_agent.py

from agent_base import CDCAgentBase, AgentAction

class CustomAgent(CDCAgentBase):
    def decide_next_action(self):
        # 自定义决策逻辑
        return AgentAction.SEARCH, {}
```

---

## 🚀 CI/CD 集成

### GitHub Actions 示例
```yaml
name: Test Pipeline
on: [push, pull_request]

jobs:
  sanity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Sanity Test
        run: python run_tests.py --sanity

  functional:
    needs: sanity
    runs-on: ubuntu-latest
    steps:
      - name: Functional Test
        run: python run_tests.py --functional

  agent:
    needs: functional
    runs-on: ubuntu-latest
    steps:
      - name: Agent Test
        run: python run_tests.py --agent --timeout 600
```

---

## 🐛 故障排除

### Sanity 测试失败
```bash
# 检查项目文件
ls -la project.godot
ls -la core/
ls -la modules/
```

### Functional 测试失败
```bash
# 在Godot中运行测试
# 1. 打开 Godot Editor
# 2. 运行项目
# 3. 查看 Debugger 输出
```

### Agent 测试无法连接
```bash
# 1. 确保游戏已运行
# 2. 检查端口 8080
curl http://localhost:8080/health

# 3. 检查 AITestBridge 是否启用
# 查看项目设置中的 Autoload
```

---

## 📈 性能指标

当前项目测试指标:
- **代码行数**: 2,749 行
- **模块数**: 12 个
- **场景数**: 7 个
- **预计功能测试时间**: 5 分钟
- **预计Agent测试时间**: 30 分钟

---

## ✅ 检查清单

发布前必须完成:
- [ ] Sanity 测试 100% 通过
- [ ] Functional 测试 P0 全部通过
- [ ] Functional 测试 P1 >95% 通过
- [ ] 无崩溃或阻塞性 bug
- [ ] Agent 测试运行 30 分钟无问题

---

## 🎮 手动测试场景

### 核心流程测试
1. 启动游戏 → 显示主菜单
2. 开始游戏 → 加载安全屋场景
3. 与床交互 → 睡觉存档
4. 与门交互 → 前往街道
5. 搜索物资 → 获得物品
6. 返回安全屋 → 状态保存

### 战斗流程测试
1. 进入街道
2. 遭遇敌人
3. 战斗胜利
4. 获得奖励
5. 检查状态变化

### 存档流程测试
1. 游戏内睡觉
2. 退出游戏
3. 重新启动
4. 检查存档存在
5. 继续游戏

---

## 📞 支持

测试框架问题? 检查:
1. `tests/TEST_FRAMEWORK.md` - 架构文档
2. `tests/results/*.json` - 测试报告
3. Godot 输出日志
