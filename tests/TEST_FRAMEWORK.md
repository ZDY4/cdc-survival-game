# CDC 末日生存游戏 - 测试框架架构

## 🎯 测试分层架构

```
┌─────────────────────────────────────────┐
│           AGENT TEST LAYER              │
│  (AI-driven exploratory testing)        │
│  - 智能探索游戏世界                     │
│  - 发现边界情况和bug                    │
│  - 模拟真实玩家行为                     │
│  - 长期稳定性测试                       │
└─────────────────────────────────────────┘
                    ↑
            功能测试通过后执行
                    ↓
┌─────────────────────────────────────────┐
│        FUNCTIONAL TEST LAYER            │
│  (Programmatic unit/integration tests)  │
│  - 模块单元测试                         │
│  - 系统集成测试                         │
│  - 场景流程测试                         │
│  - 数据一致性测试                       │
└─────────────────────────────────────────┘
                    ↑
            基础功能验证
                    ↓
┌─────────────────────────────────────────┐
│         SANITY TEST LAYER               │
│  (Quick smoke tests)                    │
│  - 文件完整性检查                       │
│  - 基础语法验证                         │
│  - 配置正确性检查                       │
│  - 资源存在性验证                       │
└─────────────────────────────────────────┘
```

## 📋 测试执行流程

```
1. SANITY TEST (30秒)
   └── 通过? → 2. FUNCTIONAL TEST (5分钟)
                    └── 全部通过? → 3. AGENT TEST (30分钟+)
                                          └── 生成报告
                    └── 有失败? → 修复后重新运行
   └── 失败? → 终止，报告基础错误
```

## 🧪 各层详细说明

### Layer 1: Sanity Test (冒烟测试)
**目的**: 快速验证项目基础完整性
**执行时间**: < 30秒
**触发时机**: 每次构建后

**测试项**:
- [x] 所有GDScript文件语法正确
- [x] 所有场景文件可解析
- [x] 项目配置完整(project.godot)
- [x] 自动加载模块无缺失
- [x] 资源文件存在且有效

### Layer 2: Functional Test (功能测试)
**目的**: 程序化验证所有功能模块
**执行时间**: 5-10分钟
**触发时机**: Sanity通过后

**测试分类**:

#### 2.1 单元测试 (Unit Tests)
- 每个模块独立测试
- Mock依赖，隔离测试
- 验证输入输出正确性

#### 2.2 集成测试 (Integration Tests)
- 模块间协作测试
- 数据流验证
- 事件系统测试

#### 2.3 场景测试 (Scene Tests)
- 场景加载测试
- 场景切换流程
- 物体交互流程

#### 2.4 数据测试 (Data Tests)
- 存档/读档一致性
- 状态序列化正确性
- 数据边界条件

### Layer 3: Agent Test (AI测试)
**目的**: 智能探索发现潜在问题
**执行时间**: 30分钟-数小时
**触发时机**: 功能测试全部通过后

**测试类型**:
- 探索性测试
- 压力测试
- 边界情况发现
- 长期稳定性

---

## 📁 测试框架目录结构

```
tests/
├── config/
│   └── test_config.json          # 测试配置
│
├── sanity/                       # 冒烟测试
│   ├── test_file_integrity.gd    # 文件完整性
│   ├── test_syntax_validation.gd # 语法验证
│   └── test_configuration.gd     # 配置检查
│
├── functional/                   # 功能测试
│   ├── unit/                     # 单元测试
│   │   ├── test_event_bus.gd
│   │   ├── test_game_state.gd
│   │   ├── test_dialog_module.gd
│   │   ├── test_combat_module.gd
│   │   ├── test_inventory_module.gd
│   │   └── ...
│   │
│   ├── integration/              # 集成测试
│   │   ├── test_dialog_to_quest.gd
│   │   ├── test_combat_to_inventory.gd
│   │   ├── test_save_load_cycle.gd
│   │   └── ...
│   │
│   ├── scene/                    # 场景测试
│   │   ├── test_scene_loading.gd
│   │   ├── test_location_travel.gd
│   │   ├── test_interaction_flow.gd
│   │   └── ...
│   │
│   └── data/                     # 数据测试
│       ├── test_save_format.gd
│       ├── test_state_consistency.gd
│       └── ...
│
├── agent/                        # Agent测试
│   ├── agent_base.py             # Agent基类
│   ├── test_exploration.py       # 探索测试
│   ├── test_stress.py            # 压力测试
│   └── test_long_running.py      # 长期测试
│
├── utils/                        # 测试工具
│   ├── test_runner.gd            # 测试运行器
│   ├── test_assertions.gd        # 断言库
│   ├── mock_objects.gd           # Mock对象
│   └── test_reporter.gd          # 报告生成
│
└── results/                      # 测试结果
    ├── sanity_report.json
    ├── functional_report.json
    └── agent_report.json
```

---

## 🎮 测试运行器使用

### 命令行接口

```bash
# 当前仓库暂无 run_tests.sh 统一入口
# Agent smoke
python tests/agent_test_runner.py

# API smoke
python tests/test_via_api.py

# 启动游戏（用于 API/Agent 测试）
godot --path . --scene scenes/ui/main_menu.tscn
```

### Godot编辑器内运行

```gdscript
# 在编辑器中运行测试
TestRunner.run_sanity_tests()
TestRunner.run_functional_tests()
TestRunner.run_all_tests()
```

---

## 📊 测试报告格式

```json
{
  "test_run": {
    "timestamp": "2026-02-15T19:30:00Z",
    "duration": 360,
    "total_tests": 50,
    "passed": 48,
    "failed": 2,
    "skipped": 0
  },
  "layers": [
    {
      "name": "sanity",
      "status": "passed",
      "duration": 15,
      "tests": [
        {"name": "file_integrity", "status": "passed", "duration": 5},
        {"name": "syntax_validation", "status": "passed", "duration": 8}
      ]
    },
    {
      "name": "functional",
      "status": "passed",
      "duration": 180,
      "tests": [...]
    }
  ],
  "failures": [
    {
      "test": "test_combat_damage",
      "layer": "functional",
      "error": "Damage calculation incorrect",
      "stack_trace": "..."
    }
  ]
}
```

---

## 🔧 测试优先级

### P0 - 核心功能 (必须通过)
- EventBus 事件分发
- GameState 状态管理
- Save/Load 存档系统
- 场景加载和切换

### P1 - 主要功能 (应该通过)
- Dialog 对话框系统
- Combat 战斗系统
- Inventory 背包系统
- Map 地图系统

### P2 - 次要功能 (最好通过)
- Crafting 制作系统
- BaseBuilding 基地建设
- Skills 技能系统
- Weather 天气系统

### P3 - 高级功能 (可选)
- AI Test Bridge
- 调试工具
- 性能优化

---

## ✅ 通过标准

### Sanity Test通过标准
- 100% 测试通过
- 无错误日志
- 所有模块可加载

### Functional Test通过标准
- P0测试: 100%通过
- P1测试: >95%通过
- P2测试: >80%通过
- 无阻塞性bug

### Agent Test执行条件
- Functional Test全部P0通过
- 核心功能无已知bug
- 测试环境稳定

---

## 🚀 CI/CD集成

```yaml
# .github/workflows/test.yml
name: Test Pipeline

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Sanity Test
        run: python tests/test_via_api.py
        
      - name: Functional Test
        if: success()
        run: python tests/test_via_api.py
        
      - name: Agent Test
        if: success()
        run: python tests/agent_test_runner.py
```
