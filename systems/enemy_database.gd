extends Node
# EnemyDatabase - 敌人数据库
# 定义各种敌人的属性、行为和掉落

const ENEMIES = {
    # 普通僵尸
    "zombie_walker": {
        "name": "行尸",
        "description": "缓慢移动的普通僵尸",
        "level": 1,
        "stats": {
            "hp": 25,
            "max_hp": 25,
            "damage": 4,
            "defense": 1,
            "speed": 3,
            "accuracy": 60
        },
        "behavior": "passive",  # passive, aggressive, territorial
        "weaknesses": ["head", "fire"],
        "resistances": ["poison"],
        "loot": [
            {"item": "scrap_metal", "chance": 0.3, "min": 1, "max": 2},
            {"item": "rotten_flesh", "chance": 0.5, "min": 1, "max": 1}
        ],
        "xp": 10,
        "spawn_locations": ["street", "street_a", "street_b"],
        "spawn_rate": 0.4
    },
    
    # 快速僵尸
    "zombie_runner": {
        "name": "奔袭",
        "description": "移动速度快的僵尸，更难对付",
        "level": 2,
        "stats": {
            "hp": 20,
            "max_hp": 20,
            "damage": 5,
            "defense": 0,
            "speed": 7,
            "accuracy": 70
        },
        "behavior": "aggressive",
        "weaknesses": ["head", "leg"],
        "resistances": [],
        "loot": [
            {"item": "scrap_metal", "chance": 0.4, "min": 1, "max": 3},
            {"item": "water_bottle", "chance": 0.2, "min": 1, "max": 1}
        ],
        "xp": 15,
        "spawn_locations": ["street_a", "street_b"],
        "spawn_rate": 0.25
    },
    
    # 强壮僵尸
    "zombie_brute": {
        "name": "巨力",
        "description": "体型巨大，攻击力强的僵尸",
        "level": 3,
        "stats": {
            "hp": 50,
            "max_hp": 50,
            "damage": 8,
            "defense": 3,
            "speed": 2,
            "accuracy": 50
        },
        "behavior": "territorial",
        "weaknesses": ["head", "fire"],
        "resistances": ["physical"],
        "special_abilities": ["stun_attack"],
        "loot": [
            {"item": "scrap_metal", "chance": 0.6, "min": 2, "max": 4},
            {"item": "bandage", "chance": 0.3, "min": 1, "max": 2},
            {"item": "food_canned", "chance": 0.2, "min": 1, "max": 1}
        ],
        "xp": 30,
        "spawn_locations": ["street_b", "hospital"],
        "spawn_rate": 0.15
    },
    
    # 变异僵尸
    "zombie_mutant": {
        "name": "变异",
        "description": "高度变异的恐怖僵尸，有强力特殊攻",
        "level": 4,
        "stats": {
            "hp": 60,
            "max_hp": 60,
            "damage": 10,
            "defense": 2,
            "speed": 4,
            "accuracy": 75
        },
        "behavior": "aggressive",
        "weaknesses": ["fire", "explosive"],
        "resistances": ["poison", "physical"],
        "special_abilities": ["acid_spit", "regeneration"],
        "loot": [
            {"item": "first_aid_kit", "chance": 0.4, "min": 1, "max": 1},
            {"item": "antiseptic", "chance": 0.5, "min": 1, "max": 2},
            {"item": "key", "chance": 0.1, "min": 1, "max": 1}
        ],
        "xp": 50,
        "spawn_locations": ["hospital"],
        "spawn_rate": 0.1
    },
    
    # 僵尸医生
    "zombie_doctor": {
        "name": "医生僵尸",
        "description": "曾经是医生，变异后更聪明",
        "level": 2,
        "stats": {
            "hp": 30,
            "max_hp": 30,
            "damage": 5,
            "defense": 1,
            "speed": 4,
            "accuracy": 80
        },
        "behavior": "territorial",
        "weaknesses": ["head"],
        "resistances": ["poison"],
        "special_abilities": ["heal_nearby"],
        "loot": [
            {"item": "bandage", "chance": 0.5, "min": 1, "max": 3},
            {"item": "painkiller", "chance": 0.3, "min": 1, "max": 2},
            {"item": "first_aid_kit", "chance": 0.2, "min": 1, "max": 1}
        ],
        "xp": 20,
        "spawn_locations": ["hospital"],
        "spawn_rate": 0.2
    },
    
    # 人类敌人 - 强盗
    "bandit_scavenger": {
        "name": "拾荒强盗",
        "description": "为了生存不择手段的强",
        "level": 2,
        "stats": {
            "hp": 35,
            "max_hp": 35,
            "damage": 6,
            "defense": 2,
            "speed": 5,
            "accuracy": 70
        },
        "behavior": "aggressive",
        "weaknesses": ["head", "torso"],
        "resistances": [],
        "loot": [
            {"item": "scrap_metal", "chance": 0.5, "min": 1, "max": 3},
            {"item": "water_bottle", "chance": 0.3, "min": 1, "max": 1},
            {"item": "knife", "chance": 0.2, "min": 1, "max": 1}
        ],
        "xp": 25,
        "spawn_locations": ["street", "street_a", "street_b"],
        "spawn_rate": 0.2
    },
    
    # 人类敌人 - 强盗头目
    "bandit_leader": {
        "name": "强盗头目",
        "description": "装备精良的强盗首",
        "level": 5,
        "stats": {
            "hp": 80,
            "max_hp": 80,
            "damage": 12,
            "defense": 5,
            "speed": 5,
            "accuracy": 85
        },
        "behavior": "territorial",
        "weaknesses": ["head"],
        "resistances": ["physical"],
        "special_abilities": ["call_reinforcements", "taunt"],
        "loot": [
            {"item": "key", "chance": 0.8, "min": 1, "max": 1},
            {"item": "first_aid_kit", "chance": 0.5, "min": 1, "max": 2},
            {"item": "food_canned", "chance": 0.6, "min": 2, "max": 4},
            {"item": "water_bottle", "chance": 0.6, "min": 2, "max": 3}
        ],
        "xp": 100,
        "spawn_locations": ["street_b"],
        "spawn_rate": 0.05
    },
    
    # 动物敌人 - 变异犬
    "mutant_dog": {
        "name": "变异犬",
        "description": "被病毒感染的野狗，速度极快",
        "level": 2,
        "stats": {
            "hp": 22,
            "max_hp": 22,
            "damage": 6,
            "defense": 1,
            "speed": 8,
            "accuracy": 80
        },
        "behavior": "aggressive",
        "weaknesses": ["torso", "leg"],
        "resistances": ["poison"],
        "special_abilities": ["pack_hunter"],
        "loot": [
            {"item": "rotten_flesh", "chance": 0.7, "min": 1, "max": 2}
        ],
        "xp": 12,
        "spawn_locations": ["street", "street_a"],
        "spawn_rate": 0.2
    },
    
    # 特殊敌人 - 巨型变异体(Boss)
    "mutant_giant": {
        "name": "巨型变异体",
        "description": "由多个尸体融合而成的恐怖怪物",
        "level": 6,
        "stats": {
            "hp": 120,
            "max_hp": 120,
            "damage": 15,
            "defense": 5,
            "speed": 3,
            "accuracy": 70
        },
        "behavior": "territorial",
        "weaknesses": ["fire", "explosive"],
        "resistances": ["physical", "poison"],
        "special_abilities": ["ground_slam", "spore_cloud", "regeneration"],
        "loot": [
            {"item": "first_aid_kit", "chance": 0.8, "min": 2, "max": 4},
            {"item": "component_electronic", "chance": 0.6, "min": 2, "max": 3},
            {"item": "weapon_pipe", "chance": 0.3, "min": 1, "max": 1},
            {"item": "key", "chance": 1.0, "min": 1, "max": 1}
        ],
        "xp": 300,
        "spawn_locations": ["subway", "factory"],
        "spawn_rate": 0.05
    },
    
    # 夜行感染者
    "night_stalker": {
        "name": "夜行感染者",
        "description": "只在夜间活动的快速变异体",
        "level": 3,
        "stats": {
            "hp": 35,
            "max_hp": 35,
            "damage": 8,
            "defense": 2,
            "speed": 9,
            "accuracy": 85
        },
        "behavior": "aggressive",
        "weaknesses": ["light", "fire"],
        "resistances": ["physical"],
        "special_abilities": ["night_vision", "silent_move"],
        "loot": [
            {"item": "scrap_metal", "chance": 0.5, "min": 2, "max": 4},
            {"item": "component_electronic", "chance": 0.3, "min": 1, "max": 1}
        ],
        "xp": 45,
        "spawn_locations": ["street_b", "subway"],
        "spawn_rate": 0.15
    },
    
    # 辐射僵尸
    "irradiated_zombie": {
        "name": "辐射僵尸",
        "description": "被严重辐射污染的僵尸，靠近会受到辐射伤害",
        "level": 4,
        "stats": {
            "hp": 45,
            "max_hp": 45,
            "damage": 6,
            "defense": 3,
            "speed": 2,
            "accuracy": 60
        },
        "behavior": "passive",
        "weaknesses": ["fire"],
        "resistances": ["radiation", "poison"],
        "special_abilities": ["radiation_aura", "poison_touch"],
        "loot": [
            {"item": "antiseptic", "chance": 0.6, "min": 1, "max": 2},
            {"item": "component_electronic", "chance": 0.4, "min": 1, "max": 2}
        ],
        "xp": 60,
        "spawn_locations": ["factory", "subway"],
        "spawn_rate": 0.12
    }
}

# 特殊能力效果
const ABILITY_EFFECTS = {
    "stun_attack": {
        "name": "眩晕攻击",
        "description": "30%概率眩晕玩家一回合",
        "trigger_chance": 0.3,
        "effect": "stun",
        "duration": 1
    },
    "acid_spit": {
        "name": "酸液喷吐",
        "description": "喷吐酸液造成持续伤害",
        "damage": 3,
        "effect": "poison",
        "duration": 3
    },
    "regeneration": {
        "name": "再生",
        "description": "每回合恢复5点生命",
        "heal": 5,
        "trigger": "per_turn"
    },
    "heal_nearby": {
        "name": "治疗同伴",
        "description": "治疗附近的僵尸",
        "heal": 10,
        "range": "nearby",
        "cooldown": 3
    },
    "call_reinforcements": {
        "name": "呼叫增援",
        "description": "召唤更多强盗",
        "summon": "bandit_scavenger",
        "count": 2,
        "cooldown": 5
    },
    "taunt": {
        "name": "嘲讽",
        "description": "降低玩家命中",
        "effect": "accuracy_down",
        "value": 20,
        "duration": 2
    },
    "pack_hunter": {
        "name": "群体狩猎",
        "description": "如果有其他变异犬在场，伤害增加50%",
        "condition": "ally_present",
        "damage_bonus": 1.5
    },
    "ground_slam": {
        "name": "地面猛击",
        "description": "重击地面，造成范围伤害并可能眩晕",
        "damage": 10,
        "effect": "stun",
        "chance": 0.4,
        "duration": 1
    },
    "spore_cloud": {
        "name": "孢子",
        "description": "释放有毒孢子，造成持续中毒伤害",
        "damage": 4,
        "effect": "poison",
        "duration": 4
    },
    "night_vision": {
        "name": "夜视",
        "description": "夜间命中率提升30%",
        "condition": "night",
        "accuracy_bonus": 30
    },
    "silent_move": {
        "name": "无声移动",
        "description": "玩家难以察觉其接近",
        "effect": "stealth"
    },
    "radiation_aura": {
        "name": "辐射光环",
        "description": "每回合对玩家造成辐射伤害",
        "damage": 3,
        "effect": "radiation",
        "duration": 3
    },
    "poison_touch": {
        "name": "毒触",
        "description": "攻击有几率使玩家中毒",
        "chance": 0.3,
        "effect": "poison",
        "duration": 2
    }
}

# 获取敌人数据
static func get_enemy(enemy_id: String):
    if ENEMIES.has(enemy_id):
        return ENEMIES[enemy_id].duplicate(true)
    return ENEMIES["zombie_walker"].duplicate(true)

# 根据地点生成敌人
static func spawn_enemy_for_location(location: String, player_level: int = 1):
    var possible_enemies = []
    
    for enemy_id in ENEMIES.keys():
        var enemy = ENEMIES[enemy_id]
        if location in enemy.spawn_locations:
            # 根据玩家等级调整出现概率
            if enemy.level <= player_level + 2:
                possible_enemies.append({
                    "id": enemy_id,
                    "enemy": enemy,
                    "weight": enemy.spawn_rate
                })
    
    if possible_enemies.size() == 0:
        return get_enemy("zombie_walker")
    
    # 加权随机选择
    var total_weight = 0.0
    for entry in possible_enemies:
        total_weight += entry.weight
    
    var roll = randf() * total_weight
    var current_weight = 0.0
    
    for entry in possible_enemies:
        current_weight += entry.weight
        if roll <= current_weight:
            var result = entry.enemy.duplicate(true)
            result["id"] = entry.id
            return result
    
    var result = possible_enemies[0].enemy.duplicate(true)
    result["id"] = possible_enemies[0].id
    return result

# 计算掉落
static func calculate_loot(enemy_id: String):
    var enemy = ENEMIES[enemy_id]
    var loot = []
    
    if enemy.has("loot"):
        for item_data in enemy.loot:
            if randf() <= item_data.chance:
                var amount = randi_range(item_data.min, item_data.max)
                loot.append({
                    "item": item_data.item,
                    "amount": amount
                })
    
    return loot

# 获取所有敌人ID
static func get_all_enemy_ids():
    return ENEMIES.keys()

# 获取地点可能遇到的敌人
static func get_enemies_for_location(location: String):
    var result = []
    for enemy_id in ENEMIES.keys():
        if location in ENEMIES[enemy_id].spawn_locations:
            result.append({
                "id": enemy_id,
                "name": ENEMIES[enemy_id].name,
                "level": ENEMIES[enemy_id].level
            })
    return result

