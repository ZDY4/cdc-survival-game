extends Node
# EncounterSystem - 遭遇系统
# 管理随机遭遇、选择-检"结果框架

# ===== 信号 =====
signal encounter_triggered(encounter_id: String, encounter_data: Dictionary)
signal encounter_resolved(encounter_id: String, result: Dictionary)
signal skill_check_requested(check_type: String, difficulty: int, callback: Callable)

# ===== 遭遇触发配置 =====
const ENCOUNTER_CHANCE_BASE: float = 0.15  # 基础遭遇概率
const ENCOUNTER_COOLDOWN: int = 3  # 最小间隔（游戏小时"
# ===== 当前状"=====
var _last_encounter_time: int = 0
var _active_encounter: Dictionary = {}
var _encounter_history: Array[String] = []

# ===== 遭遇数据"=====
var _encounter_database: Dictionary = {}

func _ready():
	print("[EncounterSystem] 遭遇系统已初始化")
	_load_encounters()
	
	# 连接信号
	var time_manager = get_node_or_null("/root/TimeManager")
	if time_manager:
		time_manager.time_advanced.connect(_on_time_advanced)

func _load_encounters():
	# 加载所有遭遇
	_encounter_database = EncounterDatabase.get_all_encounters()

# ===== 遭遇触发 =====

func _on_time_advanced(old_time: Dictionary, new_time: Dictionary):
	# 计算经过的时间
	var hours_passed = new_time.hour - old_time.hour
	if hours_passed < 0:
		hours_passed += 24
	
	# 检查是否可以触发遭遇
	var total_hours = new_time.day * 24 + new_time.hour
	if total_hours - _last_encounter_time < ENCOUNTER_COOLDOWN:
		return
	
	# 尝试触发遭遇
	if randf() < ENCOUNTER_CHANCE_BASE * hours_passed:
		_try_trigger_encounter()

func _try_trigger_encounter():
	var location = GameState.player_position
	var time_period = _get_time_period()
	var player_state = _get_player_state()
	
	# 获取可用的遭遇
	var available_encounters = _get_available_encounters(location, time_period, player_state)
	
	if available_encounters.is_empty():
		return
	
	# 根据权重选择遭遇
	var selected = _select_encounter_by_weight(available_encounters)
	_trigger_encounter(selected)

func _get_time_period() -> String:
	var hour = GameState.game_hour
	if hour >= 6 and hour < 18:
		return "day"
	return "night"

func _get_player_state() -> Dictionary:
	var survival = get_node_or_null("/root/SurvivalStatusSystem")
	
	return {
		"hp_percent": float(GameState.player_hp) / GameState.player_max_hp,
		"hunger": GameState.player_hunger,
		"stamina": GameState.player_stamina,
		"fatigue": survival.fatigue if survival else 0,
		"immunity": survival.immunity if survival else 100,
		"temperature": survival.body_temperature if survival else 37.0
	}

func _get_available_encounters(location: String, time_period: String, player_state: Dictionary) -> Array:
	var available = []
	
	for encounter_id in _encounter_database.keys():
		var encounter = _encounter_database[encounter_id]
		
		# 检查地点限制
		if encounter.has("locations"):
			var valid_locations = encounter.locations
			# 处理街道类地点
			if location.begins_with("street_") and "street" in valid_locations:
				pass  # 允许
			elif not location in valid_locations:
				continue
		
		# 检查时间限制
		if encounter.has("time_requirement"):
			if encounter.time_requirement != time_period:
				continue
		
		# 检查状态要求
		if encounter.has("min_hp_percent"):
			if player_state.hp_percent < encounter.min_hp_percent:
				continue
		
		# 检查冷"		if encounter_id in _encounter_history:
			continue
		
		available.append(encounter)
	
	return available

func _select_encounter_by_weight(encounters: Array) -> Dictionary:
	var total_weight = 0.0
	for enc in encounters:
		total_weight += enc.get("weight", 1.0)
	
	var roll = randf() * total_weight
	var current_weight = 0.0
	
	for enc in encounters:
		current_weight += enc.get("weight", 1.0)
		if roll <= current_weight:
			return enc
	
	return encounters[0] if not encounters.is_empty() else {}

func _trigger_encounter(encounter_data: Dictionary):
	_active_encounter = encounter_data
	_last_encounter_time = GameState.game_day * 24 + GameState.game_hour
	_encounter_history.append(encounter_data.id)
	
	# 限制历史记录长度
	if _encounter_history.size() > 10:
		_encounter_history.remove_at(0)
	
	encounter_triggered.emit(encounter_data.id, encounter_data)
	
	print("[EncounterSystem] 触发遭遇: %s" % encounter_data.name)

# ===== 技能检定 =====

## 执行技能检定
## 公式: 基础50% + 技能加成 + 属性加成 - 状态惩罚
func perform_skill_check(check_type: String, difficulty: int = 10) -> Dictionary:
	var base_chance = 0.5
	var skill_bonus = 0.0
	var attribute_bonus = 0.0
	var status_penalty = 0.0
	
	# 获取技能和属性
	var attr_system = get_node_or_null("/root/AttributeSystem")
	var skill_system = get_node_or_null("/root/SkillSystem")
	var survival_system = get_node_or_null("/root/SurvivalStatusSystem")
	
	# 根据检定类型获取加成
	match check_type:
		"strength", "athletics":
			if attr_system:
				attribute_bonus = (attr_system.strength - 5) * 0.05
			if skill_system and skill_system.has_method("get_skill_level"):
				skill_bonus = skill_system.get_skill_level("athletics") * 0.1
		
		"agility", "stealth", "dodge":
			if attr_system:
				attribute_bonus = (attr_system.agility - 5) * 0.05
			if skill_system:
				skill_bonus = skill_system.get_skill_level("stealth") * 0.1
		
		"intelligence", "perception", "investigation":
			# 智力相关检"			if skill_system:
				skill_bonus = skill_system.get_skill_level("perception") * 0.1
		
		"lockpicking":
			if skill_system:
				skill_bonus = skill_system.get_skill_level("lockpicking") * 0.15
		
		"survival", "nature":
			if skill_system:
				skill_bonus = skill_system.get_skill_level("survival") * 0.1
		
		"medicine", "healing":
			if skill_system:
				skill_bonus = skill_system.get_skill_level("medicine") * 0.1
		
		"combat", "melee", "ranged":
			if attr_system:
				attribute_bonus = (attr_system.strength + attr_system.agility - 10) * 0.025
			if skill_system:
				skill_bonus = skill_system.get_skill_level("combat") * 0.1
		
		"negotiation", "persuasion":
			if skill_system:
				skill_bonus = skill_system.get_skill_level("negotiation") * 0.1
		
		"luck":
			# 纯运气检定，无加成
			pass
	
	# 状态惩罚
	if survival_system:
		var fatigue_status = survival_system.get_fatigue_status()
		match fatigue_status:
			"疲劳":
				status_penalty = 0.1
			"精疲力竭":
				status_penalty = 0.2
		
		var temp_status = survival_system.get_temperature_status()
		if temp_status != "体温正常":
			status_penalty += 0.15
	
	# 饥饿惩罚
	if GameState.player_hunger < 30:
		status_penalty += 0.1
	
	# 计算最终成功率
	var final_chance = base_chance + skill_bonus + attribute_bonus - status_penalty
	final_chance -= (difficulty - 10) * 0.05  # 难度调整
	final_chance = clampf(final_chance, 0.05, 0.95)  # 限制5%-95%
	
	# 执行检定
	var roll = randf()
	var success = roll < final_chance
	
	# 判定成功等级
	var success_level = "normal"
	if success:
		if roll < final_chance * 0.3:
			success_level = "critical"
		elif roll < final_chance * 0.7:
			success_level = "good"
	else:
		if roll > final_chance + (1.0 - final_chance) * 0.7:
			success_level = "critical_fail"
		elif roll > final_chance + (1.0 - final_chance) * 0.3:
			success_level = "bad_fail"
	
	return {
		"success": success,
		"success_level": success_level,
		"roll": roll,
		"target": final_chance,
		"breakdown": {
			"base": base_chance,
			"skill": skill_bonus,
			"attribute": attribute_bonus,
			"penalty": status_penalty,
			"difficulty": (difficulty - 10) * 0.05
		}
	}

# ===== 遭遇处理 =====

func resolve_encounter_choice(choice_index: int) -> Dictionary:
	if _active_encounter.is_empty():
		return {"success": false, "reason": "没有活跃的遭"}
	
	if not _active_encounter.has("choices"):
		return {"success": false, "reason": "遭遇没有选项"}
	
	if choice_index >= _active_encounter.choices.size():
		return {"success": false, "reason": "无效的选择"}
	
	var choice = _active_encounter.choices[choice_index]
	var result = _process_choice(choice)
	
	encounter_resolved.emit(_active_encounter.id, result)
	_active_encounter = {}
	
	return result

func _process_choice(choice: Dictionary) -> Dictionary:
	var result = {
		"success": true,
		"outcome": "",
		"rewards": [],
		"penalties": [],
		"follow_up": null
	}
	
	# 检查是否需要技能检定
	if choice.has("skill_check"):
		var check_type = choice.skill_check
		var difficulty = choice.get("difficulty", 10)
		var check_result = perform_skill_check(check_type, difficulty)
		
		result["check_result"] = check_result
		
		# 根据检定结果选择结果
		if check_result.success:
			var outcome_key = "success_" + check_result.success_level
			if choice.has(outcome_key):
				_apply_outcome(choice[outcome_key], result)
			elif choice.has("success_outcome"):
				_apply_outcome(choice.success_outcome, result)
		else:
			var outcome_key = "fail_" + check_result.success_level
			if choice.has(outcome_key):
				_apply_outcome(choice[outcome_key], result)
			elif choice.has("fail_outcome"):
				_apply_outcome(choice.fail_outcome, result)
			else:
				result.outcome = "你失败了，但没有造成严重后果"
	else:
		# 无检定，直接应用结果
		if choice.has("outcome"):
			_apply_outcome(choice.outcome, result)
	
	# 应用消耗
	if choice.has("cost"):
		_apply_costs(choice.cost, result)
	
	return result

func _apply_outcome(outcome: Dictionary, result: Dictionary):
	result.outcome = outcome.get("text", "")
	
	# 添加奖励
	if outcome.has("items"):
		for item in outcome.items:
			GameState.add_item(item.id, item.get("count", 1))
			result.rewards.append(item)
	
	if outcome.has("xp"):
		var xp_result = GameState.add_xp(outcome.xp, "encounter")
		result.rewards.append({"type": "xp", "amount": outcome.xp})
	
	if outcome.has("heal"):
		GameState.heal_player(outcome.heal)
		result.rewards.append({"type": "heal", "amount": outcome.heal})
	
	if outcome.has("hp_loss"):
		GameState.damage_player(outcome.hp_loss)
		result.penalties.append({"type": "damage", "amount": outcome.hp_loss})
	
	if outcome.has("time_cost"):
		TimeManager.advance_hours(outcome.time_cost)
		result.penalties.append({"type": "time", "amount": outcome.time_cost})
	
	if outcome.has("follow_up"):
		result.follow_up = outcome.follow_up

func _apply_costs(costs: Dictionary, result: Dictionary):
	if costs.has("hp"):
		GameState.damage_player(costs.hp)
		result.penalties.append({"type": "damage", "amount": costs.hp})
	
	if costs.has("stamina"):
		GameState.player_stamina = maxi(0, GameState.player_stamina - costs.stamina)
	
	if costs.has("hunger"):
		GameState.player_hunger = maxi(0, GameState.player_hunger - costs.hunger)
	
	if costs.has("items"):
		for item in costs.items:
			GameState.remove_item(item.id, item.get("count", 1))
			result.penalties.append({"type": "item", "item": item.id, "count": item.get("count", 1)})

# ===== 公共接口 =====

func get_active_encounter() -> Dictionary:
	return _active_encounter

func has_active_encounter() -> bool:
	return not _active_encounter.is_empty()

func force_encounter(encounter_id: String) -> bool:
	if not _encounter_database.has(encounter_id):
		return false
	
	_trigger_encounter(_encounter_database[encounter_id])
	return true

func get_encounter_history() -> Array[String]:
	return _encounter_history.duplicate()

# ===== 序列化 =====
func serialize() -> Dictionary:
	return {
		"last_encounter_time": _last_encounter_time,
		"encounter_history": _encounter_history,
		"active_encounter": _active_encounter.get("id", "")
	}

func deserialize(data: Dictionary):
	_last_encounter_time = data.get("last_encounter_time", 0)
	_encounter_history = data.get("encounter_history", [])
	
	var active_id = data.get("active_encounter", "")
	if active_id and _encounter_database.has(active_id):
		_active_encounter = _encounter_database[active_id]

