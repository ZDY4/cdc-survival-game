extends Node
# CombatSystem - 深度战斗系统
# 包含技能、武器、弱点、防御等

signal combat_started(enemy_data: Dictionary)
signal turn_started(turn_owner: String, turn_number: int)
signal player_action_executed(action: String, result: Dictionary)
signal enemy_action_executed(action: String, result: Dictionary)
signal damage_dealt(target: String, amount: int, is_critical: bool)
signal combat_ended(victory: bool, rewards: Dictionary)

enum CombatState { PLAYER_TURN, ENEMY_TURN, VICTORY, DEFEAT, FLED }

# 战斗配置
var _combat_state: CombatState = CombatState.PLAYER_TURN
var _current_enemy: Dictionary = {}
var _turn_count: int = 0
var _player_defending: bool = false
var _player_stunned: bool = false
var _enemy_stunned: bool = false

# 连击系统
var _player_combo: int = 0
var _enemy_combo: int = 0
const MAX_COMBO: int = 5

# 战斗增益/减益
var _player_buffs: Array = []
var _enemy_buffs: Array = []

func _ready():
    print("[CombatSystem] 深度战斗系统已初始化")

# 开始战斗
func start_combat(enemy_id: String):
    # 从敌人数据库获取数据
    var enemy_data: Dictionary = EnemyDatabase.get_enemy(enemy_id)
    if enemy_data.is_empty():
        push_error("[CombatSystem] 敌人数据不存在: %s" % enemy_id)
        return

    if not enemy_data.has("id"):
        enemy_data["id"] = enemy_id
    if not enemy_data.has("name"):
        enemy_data["name"] = "未知敌人"
    if not enemy_data.has("level"):
        enemy_data["level"] = 1

    var stats: Dictionary = {}
    if enemy_data.has("stats") and enemy_data["stats"] is Dictionary:
        stats = enemy_data["stats"]

    var hp: int = int(stats.get("hp", 10))
    stats["hp"] = hp
    stats["max_hp"] = int(stats.get("max_hp", hp))
    stats["damage"] = int(stats.get("damage", 3))
    stats["defense"] = int(stats.get("defense", 0))
    stats["speed"] = int(stats.get("speed", 5))
    enemy_data["stats"] = stats
    enemy_data["current_hp"] = hp

    _current_enemy = enemy_data
    
    _combat_state = CombatState.PLAYER_TURN
    _turn_count = 0
    _player_defending = false
    _player_stunned = false
    _enemy_stunned = false
    _player_combo = 0
    _enemy_combo = 0
    _player_buffs.clear()
    _enemy_buffs.clear()
    
    combat_started.emit(_current_enemy)
    
    # 显示敌人信息
    DialogModule.show_dialog(
        "遭遇 %s!\n等级: %d\nHP: %d" % [
            _current_enemy.name,
            _current_enemy.level,
            _current_enemy.stats.hp
        ],
        "战斗开始",
        ""
    )
    
    await get_tree().create_timer(1.5).timeout
    _start_player_turn()

# 玩家回合
func _start_player_turn():
    if _combat_state != CombatState.PLAYER_TURN:
        return
    
    _turn_count += 1
    turn_started.emit("player", _turn_count)
    
    # 检查眩晕
    if _player_stunned:
        DialogModule.show_dialog("你被眩晕了，无法行动", "状态", "")
        _player_stunned = false
        await get_tree().create_timer(1.0).timeout
        _end_player_turn()
        return
    
    # 处理增益效果
    _process_buffs("player")
    
    # 显示战斗UI（这里应该触发UI显示）
    EventBus.emit(EventBus.EventType.COMBAT_STARTED, {
        "enemy": _current_enemy,
        "turn": _turn_count
    })

# 玩家行动
func player_attack(attack_type: String = "normal", target_part: String = "body"):
    if _combat_state != CombatState.PLAYER_TURN:
        return
    
    var damage = _calculate_player_damage(attack_type, target_part)
    var is_critical = randf() < 0.15  # 15%暴击率
    
    if is_critical:
        damage = int(damage * 1.5)
    
    # 应用伤害
    _current_enemy.current_hp -= damage
    damage_dealt.emit("enemy", damage, is_critical)
    
    # 连击增加
    _player_combo = min(_player_combo + 1, MAX_COMBO)
    
    var result = {
        "damage": damage,
        "is_critical": is_critical,
        "combo": _player_combo,
        "target_hp": _current_enemy.current_hp
    }
    
    player_action_executed.emit("attack", result)
    
    # 显示攻击结果
    var attack_text = "攻击"
    if attack_type == "headshot":
        attack_text = "爆头"
    elif attack_type == "heavy":
        attack_text = "重击"
    
    var msg = "%s造成%d伤害" % [attack_text, damage]
    if is_critical:
        msg = "暴击" + msg
    
    DialogModule.show_dialog(msg, "战斗", "")
    
    _check_combat_end()
    if _combat_state == CombatState.PLAYER_TURN:
        _end_player_turn()

# 计算玩家伤害
func _calculate_player_damage(attack_type: String, target_part: String):
    var base_damage = 10  # 基础伤害
    
    # 武器加成（如果有装备）
    # base_damage += _get_weapon_damage()
    
    # 技能加成
    base_damage += SkillModule.get_total_damage_bonus()
    
    # 攻击类型修正
    match attack_type:
        "normal":
            pass  # 标准伤害
        "heavy":
            base_damage = int(base_damage * 1.5)
        "quick":
            base_damage = int(base_damage * 0.7)
        "headshot":
            base_damage = int(base_damage * 2.0)
    
    # 弱点加成
    if target_part in _current_enemy.get("weaknesses", []):
        base_damage = int(base_damage * 1.5)
    
    # 敌人防御减免
    var enemy_stats: Dictionary = _current_enemy.get("stats", {})
    var defense: int = int(enemy_stats.get("defense", 0))
    
    # 连击加成
    if _player_combo > 1:
        base_damage = int(base_damage * (1.0 + _player_combo * 0.1))
    
    # 随机波动 (±20%)
    var variance = randf_range(0.8, 1.2)
    
    return max(1, int((base_damage - defense) * variance))

# 玩家防御
func player_defend():
    if _combat_state != CombatState.PLAYER_TURN:
        return
    
    _player_defending = true
    _player_combo = 0  # 防御打断连击
    
    # 添加防御增益
    _add_buff("player", "defense_up", 2, 0.5)
    
    DialogModule.show_dialog("你采取了防御姿态，下回合受到伤害减少50%", "战斗", "")
    
    player_action_executed.emit("defend", {"defense_bonus": 0.5})
    _end_player_turn()

# 玩家使用技能
func player_use_skill(skill_id: String):
    if _combat_state != CombatState.PLAYER_TURN:
        return
    
    var skill = _get_combat_skill(skill_id)
    if not skill:
        return
    
    # 检查技能点/冷却
    if not _can_use_skill(skill):
        DialogModule.show_dialog("无法使用该技能！", "错误", "")
        return
    
    var result = _execute_skill(skill)
    player_action_executed.emit("skill", result)
    _end_player_turn()

# 玩家使用物品
func player_use_item(item_id: String):
    if _combat_state != CombatState.PLAYER_TURN:
        return
    
    var result = InventoryModule.use_item(item_id)
    if result:
        player_action_executed.emit("item", {"item": item_id})
        _end_player_turn()

# 玩家逃跑
func player_flee():
    if _combat_state != CombatState.PLAYER_TURN:
        return false
    
    # 逃跑成功率 = 基础50% + 速度差
    var player_speed = GameState.player_stamina / 10  # 体力影响速度
    var enemy_speed = _current_enemy.stats.speed
    var flee_chance = 0.5 + (player_speed - enemy_speed) * 0.05
    flee_chance = clamp(flee_chance, 0.1, 0.9)
    
    if randf() < flee_chance:
        _combat_state = CombatState.FLED
        DialogModule.show_dialog("成功逃脱", "逃跑", "")
        combat_ended.emit(false, {})  # 逃跑不算胜利
        return true
    else:
        DialogModule.show_dialog("逃跑失败", "逃跑", "")
        _end_player_turn()
        return false

# 结束玩家回合
func _end_player_turn():
    if _current_enemy.current_hp <= 0:
        _combat_state = CombatState.VICTORY
        _handle_victory()
        return
    
    _combat_state = CombatState.ENEMY_TURN
    _start_enemy_turn()

# 敌人回合
func _start_enemy_turn():
    if _combat_state != CombatState.ENEMY_TURN:
        return
    
    turn_started.emit("enemy", _turn_count)
    
    # 检查眩晕
    if _enemy_stunned:
        DialogModule.show_dialog("敌人被眩晕，无法行动", "战斗", "")
        _enemy_stunned = false
        _end_enemy_turn()
        return
    
    # 处理增益效果
    _process_buffs("enemy")
    
    # AI决策
    await get_tree().create_timer(1.0).timeout
    _enemy_ai_action()

# 敌人AI
func _enemy_ai_action():
    var behavior = _current_enemy.get("behavior", "passive")
    var hp_percent = float(_current_enemy.current_hp) / _current_enemy.stats.max_hp
    
    var action = "attack"
    var special_chance = 0.0
    
    # 根据行为模式选择行动
    match behavior:
        "passive":
            # 被动型：低血量时尝试逃跑（这里简化为防御"
            if hp_percent < 0.3:
                action = "defend" if randf() < 0.5 else "attack"
        
        "aggressive":
            # 好战型：更倾向于攻击，会使用特殊技"
            special_chance = 0.3
            if hp_percent < 0.5:
                special_chance = 0.5
        
        "territorial":
            # 领地型：生命值高时更激"
            if hp_percent > 0.7:
                special_chance = 0.4
    
    # 检查特殊能"
    var special_abilities = _current_enemy.get("special_abilities", [])
    if special_abilities.size() > 0 && randf() < special_chance:
        action = "special"
        var ability = special_abilities[randi() % special_abilities.size()]
        _execute_enemy_special(ability)
    else:
        _enemy_attack()

# 敌人攻击
func _enemy_attack():
    var damage = _calculate_enemy_damage()
    
    # 玩家防御减免
    if _player_defending:
        damage = int(damage * 0.5)
        _player_defending = false  # 防御只持续一回合
    
    # 应用伤害
    GameState.damage_player(damage)
    damage_dealt.emit("player", damage, false)
    
    # 连击增加
    _enemy_combo = min(_enemy_combo + 1, MAX_COMBO)
    
    var result = {
        "damage": damage,
        "combo": _enemy_combo,
        "player_hp": GameState.player_hp
    }
    
    enemy_action_executed.emit("attack", result)
    
    DialogModule.show_dialog(
        "%s攻击了你，造成%d伤害" % [_current_enemy.name, damage],
        "战斗",
        ""
    )
    
    _check_combat_end()
    if _combat_state == CombatState.ENEMY_TURN:
        _end_enemy_turn()

# 计算敌人伤害
func _calculate_enemy_damage():
    var base_damage = _current_enemy.stats.damage
    
    # 连击加成
    if _enemy_combo > 1:
        base_damage = int(base_damage * (1.0 + _enemy_combo * 0.1))
    
    # 玩家状态影响（疲劳降低防御"
    if GameState.player_stamina < 30:
        base_damage = int(base_damage * 1.2)
    
    # 随机波动
    var variance = randf_range(0.9, 1.1)
    
    return max(1, int(base_damage * variance))

# 敌人特殊技"
func _execute_enemy_special(ability: String):
    var ability_data = {}  # 从数据库获取
    
    match ability:
        "stun_attack":
            if randf() < 0.3:
                _player_stunned = true
                DialogModule.show_dialog(
                    "%s使用了眩晕攻击！你被眩晕了！" % _current_enemy.name,
                    "特殊攻击",
                    ""
                )
            else:
                _enemy_attack()  # 失败时普通攻"
        
        "acid_spit":
            GameState.damage_player(3)
            DialogModule.show_dialog(
                "%s喷出酸液！你受到了持续伤害！" % _current_enemy.name,
                "特殊攻击",
                ""
            )
        
        "regeneration":
            var heal = 5
            _current_enemy.current_hp = min(_current_enemy.current_hp + heal, _current_enemy.stats.max_hp)
            DialogModule.show_dialog(
                "%s再生%d生命值！" % [_current_enemy.name, heal],
                "特殊能力",
                ""
            )
        
        _:
            _enemy_attack()
    
    _end_enemy_turn()

# 结束敌人回合
func _end_enemy_turn():
    if GameState.player_hp <= 0:
        _combat_state = CombatState.DEFEAT
        _handle_defeat()
        return
    
    _combat_state = CombatState.PLAYER_TURN
    _start_player_turn()

# 检查战斗结"
func _check_combat_end():
    if _current_enemy.current_hp <= 0:
        _combat_state = CombatState.VICTORY
        _handle_victory()
    elif GameState.player_hp <= 0:
        _combat_state = CombatState.DEFEAT
        _handle_defeat()

# 处理胜利
func _handle_victory(type: String = ""):
    var xp = _current_enemy.get("xp", 10)
    var loot = EnemyDatabase.calculate_loot(_current_enemy.id)
    
    # 给予经验（如果有经验系统"
    # ExperienceSystem.add_xp(xp)
    
    # 给予掉落
    for item in loot:
        InventoryModule.add_item(item.item, item.amount)
    
    var rewards = {
        "xp": xp,
        "loot": loot,
        "turns": _turn_count
    }
    
    DialogModule.show_dialog(
        "战斗胜利！\n获得 %d 经验\n战利品: %s" % [
            xp,
            _format_loot(loot)
        ],
        "胜利",
        ""
    )
    
    combat_ended.emit(true, rewards)

# 处理失败
func _handle_defeat():
    DialogModule.show_dialog(
        "你被%s击败了" % _current_enemy.name,
        "失败",
        ""
    )
    
    combat_ended.emit(false, {})

# 辅助方法
func _format_loot(loot: Array):
    if loot.size() == 0:
        return ""
    
    var items = []
    for item in loot:
        items.append("%s x%d" % [item.item, item.amount])
    
    return ", ".join(items)

func _get_combat_skill(skill_id: String):
    # 返回技能数"
    var skills = {
        "power_strike": {
            "name": "强力打击",
            "damage_mult": 2.0,
            "cooldown": 3
        },
        "heal": {
            "name": "急救",
            "heal_amount": 30,
            "cooldown": 5
        }
    }
    return skills.get(skill_id, {})

func _can_use_skill(skill: Dictionary):
    # 检查是否可以使用技"
    return true  # 简化实"

func _execute_skill(skill: Dictionary):
    return {"skill": skill.name}

func _add_buff(target: String, buff_type: String, duration: int, value: float):
    var buff = {
        "type": buff_type,
        "duration": duration,
        "value": value
    }
    
    if target == "player":
        _player_buffs.append(buff)
    else:
        _enemy_buffs.append(buff)

func _process_buffs(target: String):
    var buffs = _player_buffs if target == "player" else _enemy_buffs
    
    for i in range(buffs.size() - 1, -1, -1):
        buffs[i].duration -= 1
        if buffs[i].duration <= 0:
            buffs.remove_at(i)

# 公共接口
func is_in_combat():
    return _combat_state in [CombatState.PLAYER_TURN, CombatState.ENEMY_TURN]

func get_combat_state():
    match _combat_state:
        CombatState.PLAYER_TURN: return "player_turn"
        CombatState.ENEMY_TURN: return "enemy_turn"
        CombatState.VICTORY: return "victory"
        CombatState.DEFEAT: return "defeat"
        CombatState.FLED: return "fled"
        _: return "unknown"

func get_enemy_info():
    return {
        "name": _current_enemy.name,
        "hp": _current_enemy.current_hp,
        "max_hp": _current_enemy.stats.max_hp,
        "level": _current_enemy.level
    }

