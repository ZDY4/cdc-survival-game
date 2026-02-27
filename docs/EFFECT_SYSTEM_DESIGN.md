# 效果系统设计文档

## 概述
游戏中效果（Effect）系统用于管理所有临时或永久的属性修改，包括 Buffs、Debuffs 和特殊状态。

## 效果数据结构

```json
{
  "effect_id": {
    "id": "effect_id",              // 唯一标识
    "name": "效果名称",            // 显示名称
    "description": "效果描述",     // 详细描述
    "category": "buff",            // 类别: buff, debuff, neutral
    "icon_path": "res://...",      // 图标路径
    
    // 持续时间
    "duration": 60.0,              // 持续时间(秒), -1表示永久
    "is_infinite": false,          // 是否无限持续时间
    
    // 叠加设置
    "is_stackable": false,         // 是否可叠加
    "max_stacks": 1,               // 最大叠加层数
    "stack_mode": "refresh",       // 叠加模式: refresh(刷新), extend(延长), intensity(增强)
    
    // 属性影响
    "stat_modifiers": {
      "strength": 5,               // 力量 +5
      "agility": -2,               // 敏捷 -2
      "max_hp": 0.1,               // 最大生命值 +10%
      "damage_mult": 0.15,         // 伤害 +15%
      "defense": -3                // 防御 -3
    },
    
    // 特殊效果
    "special_effects": [
      "regeneration",              // 生命恢复
      "poison",                    // 中毒
      "stun",                      // 眩晕
      "invisible"                  // 隐身
    ],
    
    // 触发设置
    "trigger_conditions": [],      // 触发条件
    "tick_interval": 1.0,          // 周期性效果触发间隔(秒)
    
    // 视觉表现
    "visual_effect": "",           // 视觉特效路径
    "color_tint": "#FF0000"        // 屏幕色调
  }
}
```

## 属性修饰符说明

### 基础属性 (直接加减)
- `strength`, `agility`, `constitution` - 基础属性
- `max_hp`, `hp` - 生命值
- `max_stamina`, `stamina` - 体力
- `damage`, `defense` - 伤害/防御

### 百分比修饰符 (乘法)
- `damage_mult` - 伤害倍率 (1.0 = 100%)
- `defense_mult` - 防御倍率
- `speed_mult` - 速度倍率
- `exp_mult` - 经验倍率

## 效果类别

### Buffs (增益)
- 攻击力提升
- 防御力提升
- 速度提升
- 经验加成
- 生命恢复

### Debuffs (减益)
- 中毒
- 减速
- 攻击力降低
- 防御力降低
- 眩晕

### Neutral (中性)
- 隐身
- 无敌
- 变身

## 叠加模式

1. **refresh** - 刷新持续时间 (默认)
2. **extend** - 延长持续时间
3. **intensity** - 增强效果强度
4. **separate** - 独立计算 (多个实例)

## 系统架构

```
EffectData          // 效果数据定义
EffectInstance      // 运行时效果实例
EffectSystem        // 效果管理器 (autoload)
EffectEditor        // 编辑器插件
```

## API 使用示例

```gdscript
# 添加效果
EffectSystem.apply_effect("strength_boost", GameState.player_id)

# 添加带层数的效果
EffectSystem.apply_effect("bleeding", GameState.player_id, 3)

# 移除效果
EffectSystem.remove_effect("strength_boost", GameState.player_id)

# 查询效果
var active_effects = EffectSystem.get_active_effects(GameState.player_id)
```
