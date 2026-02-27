# 装备系统合并设计方案

## 现状分析

### WeaponSystem (武器系统)
**专属属性:**
- damage - 伤害值
- attack_speed - 攻击速度
- range - 攻击范围
- ammo_type, max_ammo - 弹药系统
- stamina_cost - 耐力消耗
- crit_chance, crit_multiplier - 暴击系统
- special_effects (bleeding, stun, knockback) - 战斗特效

**功能:**
- 武器装备/卸下
- 弹药管理
- 耐久度管理
- 战斗伤害计算

### EquipmentSystem (装备系统)
**专属属性:**
- slot (head, body, hands, legs, feet, back, accessory) - 装备槽位
- stats (defense, insulation, speed, etc.) - 属性加成
- carry_bonus - 负重加成

**功能:**
- 8个装备槽位管理
- 属性加成计算
- 耐久度管理
- 装备修复

### 共同点
- name, description
- weight
- durability, max_durability
- rarity
- required_level
- repair_materials

---

## 合并方案

### 方案1: 完全合并 (推荐)

**统一数据结构:**
```gdscript
const ITEMS = {
    # === 武器 (slot: "main_hand" / "off_hand") ===
    "knife": {
        "name": "小刀",
        "type": "weapon",           # 类型标识
        "slot": "main_hand",        # 武器槽位
        "weapon_data": {            # 武器专属数据
            "damage": 12,
            "attack_speed": 1.2,
            "range": 1,
            "subtype": "dagger",
            "ammo_type": "",
            "stamina_cost": 3
        },
        "weight": 0.3,
        "durability": 50,
        "special_effects": ["bleeding"],
        "rarity": "common"
    },
    
    "rifle": {
        "name": "步枪",
        "type": "weapon",
        "slot": "main_hand",
        "weapon_data": {
            "damage": 45,
            "attack_speed": 0.8,
            "range": 50,
            "subtype": "rifle",
            "ammo_type": "ammo_rifle",
            "max_ammo": 10,
            "reload_time": 2.5
        },
        "weight": 3.5,
        "durability": 90,
        "rarity": "rare"
    },
    
    # === 防具 (slot: head/body/hands/legs/feet/back/accessory) ===
    "helmet_makeshift": {
        "name": "简易头盔",
        "type": "armor",
        "slot": "head",
        "armor_data": {             # 防具专属数据
            "defense": 2,
            "insulation": 0.1
        },
        "weight": 1.5,
        "durability": 30,
        "rarity": "common"
    },
    
    "backpack_military": {
        "name": "军用背包",
        "type": "armor",
        "slot": "back",
        "armor_data": {
            "carry_bonus": 20.0
        },
        "weight": 2.0,
        "durability": 80,
        "rarity": "rare"
    }
}
```

**装备槽位扩展:**
```gdscript
enum EquipmentSlot {
    HEAD,       # 头部
    BODY,       # 身体
    HANDS,      # 手部
    LEGS,       # 腿部
    FEET,       # 脚部
    BACK,       # 背部
    MAIN_HAND,  # 主手（武器）- 新增
    OFF_HAND,   # 副手（武器/盾牌）- 新增
    ACCESSORY_1,# 饰品1
    ACCESSORY_2 # 饰品2
}
```

**统一接口:**
```gdscript
# 装备物品（统一接口）
func equip_item(item_id: String, slot: String) -> bool

# 卸下物品
func unequip_item(slot: String) -> bool

# 获取当前装备
func get_equipped(slot: String) -> Dictionary

# 计算战斗属性
func calculate_combat_stats() -> Dictionary:
    var stats = {
        "damage": 0,
        "attack_speed": 1.0,
        "defense": 0,
        "crit_chance": 0.05
    }
    
    # 主手武器
    var main_hand = get_equipped("main_hand")
    if main_hand and main_hand.type == "weapon":
        stats.damage += main_hand.weapon_data.damage
        stats.attack_speed = main_hand.weapon_data.attack_speed
        stats.crit_chance += main_hand.weapon_data.get("crit_chance", 0)
    
    # 防具加成
    for slot in ["head", "body", "hands", "legs", "feet"]:
        var armor = get_equipped(slot)
        if armor and armor.type == "armor":
            stats.defense += armor.armor_data.get("defense", 0)
    
    return stats
```

### 优点:
- ✅ 统一的数据结构
- ✅ 统一的装备界面
- ✅ 简化代码维护
- ✅ 10个装备槽位（8+2武器）

### 缺点:
- ⚠️ 需要重构现有代码
- ⚠️ 需要迁移存档数据

---

## 方案2: 保持分离但统一API (轻量级)

保持两个系统独立，但提供统一的外观接口:

```gdscript
# UnifiedEquipmentSystem - 统一外观
func equip(item_id: String, slot: String) -> bool:
    if slot in ["main_hand", "off_hand"]:
        return WeaponSystem.equip_weapon(item_id)
    else:
        return EquipmentSystem.equip(item_id, slot)

func unequip(slot: String) -> bool:
    if slot in ["main_hand", "off_hand"]:
        return WeaponSystem.unequip()
    else:
        return EquipmentSystem.unequip(slot)

func get_item_in_slot(slot: String) -> Dictionary:
    if slot in ["main_hand", "off_hand"]:
        return WeaponSystem.get_equipped_weapon_data()
    else:
        return EquipmentSystem.get_equipped_in_slot(slot)
```

### 优点:
- ✅ 最小改动
- ✅ 向后兼容
- ✅ 快速实现

### 缺点:
- ⚠️ 内部仍是两套系统
- ⚠️ 数据重复定义

---

## 推荐方案

**方案1: 完全合并**

理由:
1. 武器确实是装备的一种
2. 长远来看维护更简单
3. 可以支持双持武器、武器+盾牌组合
4. 背包界面可以统一显示所有装备

**实施步骤:**
1. 创建新的统一装备数据库
2. 迁移武器数据到新的格式
3. 更新装备界面支持10个槽位
4. 更新战斗系统使用新接口
5. 存档数据迁移

**工作量:** 约2-3小时

---

## 你的选择?

A) **完全合并** - 统一系统，更简洁但需要重构
B) **保持分离** - 当前状态，各自独立工作
C) **统一API** - 两套系统但提供统一接口

需要我实施合并方案吗？
