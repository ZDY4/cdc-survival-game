# CDC Survival Game - 负重系统设计文档 v1.0

## 概述
为游戏添加真实的负重机制，影响玩家在大地图中的移动和战斗表现。

---

## 核心机制

### 负重计算公式
```
最大负重 = 基础负重 + 力量加成 + 背包加成 + 装备加成

基础负重: 30 kg (固定)
力量加成: 力量 × 3 kg
背包加成: 取决于背包类型
装备加成: 某些护甲/配件提供的负重
```

### 计算示例
```
角色: 力量 5
装备: 军用背包 (+20kg), 战术背心 (+5kg)

最大负重 = 30 + (5×3) + 20 + 5 = 70 kg
```

---

## 重量来源

### 1. 装备重量
所有已装备的装备都有重量，包括：
- 头部装备 (头盔)
- 身体装备 (护甲)
- 手部装备 (手套)
- 腿部装备 (裤子)
- 脚部装备 (鞋子)
- 背部装备 (背包)
- 饰品

### 2. 武器重量
- 主手武器重量
- 副手武器重量
- 背包中存放的武器

### 3. 物品重量
所有背包中的物品按重量计算：
- 食物、水
- 弹药
- 材料
- 医疗用品

---

## 负重等级

负重率 = 当前重量 / 最大负重 × 100%

| 等级 | 范围 | 名称 | 颜色 |
|------|------|------|------|
| 1 | 0% - 50% | 轻载 | 白色 |
| 2 | 50% - 75% | 中载 | 黄色 |
| 3 | 75% - 90% | 重载 | 橙色 |
| 4 | 90% - 100% | 超载 | 红色 |
| 5 | >100% | 完全超载 | 深红闪烁 |

---

## 负面效果

### 移动惩罚（大地图）
| 负重等级 | 移动时间倍数 | 描述 |
|---------|-------------|------|
| 轻载 | ×1.0 | 正常移动 |
| 中载 | ×1.3 | 步伐稍慢 |
| 重载 | ×1.6 | 气喘吁吁 |
| 超载 | ×2.2 | 步履艰难 |
| 完全超载 | ×5.0 | 几乎无法移动 |

### 战斗惩罚
| 负重等级 | 效果 |
|---------|------|
| 中载 | 闪避率 -10% |
| 重载 | 闪避率 -20%, 先手值 -5 |
| 超载 | 闪避率 -40%, 先手值 -10 |
| 完全超载 | 无法战斗，只能逃跑 |

### 其他惩罚
- **耐力消耗**: 重载以上，移动和战斗额外消耗耐力
- **噪音**: 超载时移动会产生噪音，增加遭遇敌人概率

---

## 背包系统

**注意**: 背包只有负重加成，没有容量限制。

| 背包类型 | 负重加成 | 重量 | 描述 |
|---------|---------|------|------|
| 无背包 | +0 kg | 0 kg | 初始状态 |
| 简易布袋 | +5 kg | 0.5 kg | 轻量便携 |
| 登山包 | +10 kg | 1.2 kg | 户外运动 |
| 军用背包 | +20 kg | 2.0 kg | 军规标准 |
| 战术背包 | +25 kg | 2.5 kg | 顶级装备 |

---

## 装备负重加成

部分装备提供额外的负重能力：

| 装备 | 类型 | 负重加成 |
|------|------|---------|
| 战术背心 | 身体 | +5 kg |
| 负重腰带 | 腰部 | +3 kg |
| 军用靴 | 脚部 | +2 kg |

---

## UI显示

### 显示格式
```
当前重量/总负重

示例: "12.5/50 kg"
```

### 显示位置
- 背包界面顶部
- 状态栏

### 颜色编码
- 正常: 白色
- 超载时: 红色

### 超重警告
- 超载时文字变红
- 完全超载时弹窗提示

---

## 系统集成

### 存档集成
- 负重数据保存到存档
- 读取时重新计算当前重量

### 事件集成
```gdscript
weight_changed(current, max, ratio)  # 重量变化
overload_started(level)               # 开始超载
overload_ended()                      # 结束超载
encumbrance_changed(level)            # 负重等级变化
```

### 大地图移动集成
```gdscript
# 修改MapModule.travel()
func travel(destination: String) -> float:
    var base_time = get_travel_time(destination)
    var penalty = CarrySystem.get_movement_penalty()
    return base_time * penalty
```

---

## API接口

### CarrySystem 公共方法
```gdscript
get_current_weight() -> float                    # 获取当前重量
get_max_carry_weight() -> float                  # 获取最大负重
get_weight_ratio() -> float                      # 获取负重比例
can_carry_item(item_id, count) -> bool          # 检查是否可以拾取
get_movement_penalty() -> float                  # 获取移动惩罚倍数
get_dodge_penalty() -> float                     # 获取闪避惩罚
can_move() -> bool                              # 检查是否可以移动
can_fight() -> bool                             # 检查是否可以战斗
```

### WeaponSystem 接口
```gdscript
get_weapon_weight(weapon_id) -> float           # 获取武器重量
get_equipped_weapon_weight() -> float           # 获取装备武器重量
```

### EquipmentSystem 接口
```gdscript
get_equipment_weight(item_id) -> float          # 获取装备重量
get_total_weight() -> float                     # 获取已装备总重量
get_total_carry_bonus() -> float                # 获取总负重加成
get_backpack_type() -> String                   # 获取背包类型
```

### InventoryModule 接口
```gdscript
get_inventory_weight() -> float                 # 获取背包物品总重量
```

---

## 使用示例

### 获取当前负重状态
```gdscript
var current = CarrySystem.get_current_weight()
var max = CarrySystem.get_max_carry_weight()
print("负重: %.1f/%.1f kg" % [current, max])
```

### 检查是否可以拾取
```gdscript
if CarrySystem.can_carry_item("rifle", 1):
    InventoryModule.add_item("rifle", 1)
else:
    DialogModule.show_dialog("太重了，拿不动！")
```

### 监听重量变化
```gdscript
CarrySystem.weight_changed.connect(_on_weight_changed)

func _on_weight_changed(current, max, ratio):
    print("重量变化: %.1f/%.1f (%.0f%%)" % [current, max, ratio * 100])
```

---

## 平衡性考虑

### 早期游戏
- 初始负重较低 (40-50kg)
- 鼓励玩家做选择：带食物还是带武器
- 增加资源管理的策略性

### 中后期游戏
- 力量提升可增加负重
- 特殊装备/背包可以增加负重上限
- 基地储存解决物品管理问题

### 技巧性玩法
- 轻装快速探索
- 重装慢速但资源丰富
- 临时丢弃物品减重

---

## 文件清单

### 核心文件
- `systems/carry_system.gd` - 负重核心系统

### 集成文件
- `systems/weapon_system.gd` - 武器重量
- `systems/equipment_system.gd` - 装备重量和负重加成
- `modules/inventory/inventory_module.gd` - 物品重量
- `modules/map/map_module.gd` - 移动惩罚

### 配置
- `project.godot` - CarrySystem autoload

---

## 版本历史

### v1.0 (2026-02-18)
- 初始版本
- 实现5级负重系统
- 背包纯负重加成（无容量限制）
- 集成大地图移动惩罚

---

*设计日期: 2026-02-18*
