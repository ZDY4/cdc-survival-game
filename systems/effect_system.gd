extends Node
## EffectSystem - 游戏效果管理系统
## 管理所有 buffs/debuffs 和状态效果
## 支持持续时间、叠加、属性修改

# ========== 信号 ==========
signal effect_applied(entity_id: String, effect_id: String, stacks: int)
signal effect_removed(entity_id: String, effect_id: String)
signal effect_expired(entity_id: String, effect_id: String)
signal effect_tick(entity_id: String, effect_id: String, remaining_time: float)
signal stat_modified(entity_id: String, stat_name: String, new_value: float)

# ========== 常量 ==========
enum EffectCategory {
	BUFF,       # 增益
	DEBUFF,     # 减益
	NEUTRAL     # 中性
}

enum StackMode {
	REFRESH,    # 刷新持续时间
	EXTEND,     # 延长持续时间
	INTENSITY,  # 增强效果
	SEPARATE    # 独立实例
}

# ========== 数据 ==========
# 活跃效果: {entity_id: {effect_id: EffectInstance}}
var _active_effects: Dictionary = {}

# 效果定义缓存
var _effect_definitions: Dictionary = {}

# ========== 初始化 ==========
func _ready():
	print("[EffectSystem] 效果系统初始化")
	_load_effect_definitions()

func _load_effect_definitions():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		_effect_definitions = data_manager.get_data("effects")
		print("[EffectSystem] 加载了 %d 个效果定义" % _effect_definitions.size())

# ========== 公共 API ==========

## 对实体应用GameplayEffect
## @param effect: GameplayEffect实例
## @param entity_id: 实体ID（玩家、敌人等）
## @param stacks: 初始层数
## @return: 是否成功应用
func apply_gameplay_effect(effect: GameplayEffect, entity_id: String, stacks: int = 1) -> bool:
	if effect == null:
		return false
	if effect.id.is_empty():
		push_error("[EffectSystem] GameplayEffect 缺少 id")
		return false
	
	# 确保实体有记录
	if not _active_effects.has(entity_id):
		_active_effects[entity_id] = {}
	
	var entity_effects = _active_effects[entity_id]
	var effect_id = effect.id
	
	# 检查是否已存在该效果
	if entity_effects.has(effect_id):
		# 处理叠加
		_handle_stack(effect_id, entity_id, stacks)
	else:
		# 创建新效果实例
		_create_effect_instance(effect, entity_id, stacks)
	
	effect_applied.emit(entity_id, effect_id, stacks)
	return true

## 对实体应用效果（按ID从数据定义生成GameplayEffect）
## @param effect_id: 效果ID
## @param entity_id: 实体ID（玩家、敌人等）
## @param stacks: 初始层数
## @return: 是否成功应用
func apply_effect(effect_id: String, entity_id: String, stacks: int = 1) -> bool:
	var definition = _get_effect_definition(effect_id)
	if definition.is_empty():
		push_error("[EffectSystem] 未找到效果定义: %s" % effect_id)
		return false
	
	var effect := GameplayEffect.new()
	effect.configure(definition)
	return apply_gameplay_effect(effect, entity_id, stacks)

## 更新或插入GameplayEffect（用于技能等级变动等）
func upsert_gameplay_effect(effect: GameplayEffect, entity_id: String) -> bool:
	if effect == null:
		return false
	if effect.id.is_empty():
		push_error("[EffectSystem] GameplayEffect 缺少 id")
		return false
	
	if not _active_effects.has(entity_id):
		_active_effects[entity_id] = {}
	
	var entity_effects = _active_effects[entity_id]
	if entity_effects.has(effect.id):
		var instance: EffectInstance = entity_effects[effect.id]
		_remove_stat_modifiers(entity_id, instance.effect, instance.stacks)
		instance.effect = effect
		instance.is_infinite = effect.is_infinite
		instance.remaining_time = effect.duration
		instance.tick_timer = 0.0
		_apply_stat_modifiers(entity_id, effect, instance.stacks)
		return true
	
	return apply_gameplay_effect(effect, entity_id, 1)

## 移除实体的效果
## @param effect_id: 效果ID，空字符串表示移除所有
func remove_effect(effect_id: String, entity_id: String) -> bool:
	if not _active_effects.has(entity_id):
		return false
	
	var entity_effects = _active_effects[entity_id]
	
	if effect_id.is_empty():
		# 移除所有效果
		for id in entity_effects.keys():
			_remove_single_effect(id, entity_id)
		return true
	
	if entity_effects.has(effect_id):
		_remove_single_effect(effect_id, entity_id)
		effect_removed.emit(entity_id, effect_id)
		return true
	
	return false

## 获取实体的所有活跃效果
func get_active_effects(entity_id: String) -> Array:
	if not _active_effects.has(entity_id):
		return []
	
	var result = []
	for effect_id in _active_effects[entity_id].keys():
		var instance = _active_effects[entity_id][effect_id]
		result.append({
			"effect_id": effect_id,
			"stacks": instance.stacks,
			"remaining_time": instance.remaining_time,
			"definition": instance.effect
		})
	return result

## 获取实体特定属性的总修饰值
func get_stat_modifier(entity_id: String, stat_name: String) -> float:
	var total = 0.0
	
	if not _active_effects.has(entity_id):
		return total
	
	for effect_id in _active_effects[entity_id].keys():
		var instance = _active_effects[entity_id][effect_id]
		var modifiers = instance.effect.get_modifiers()
		
		if modifiers.has(stat_name):
			var value = float(modifiers[stat_name])
			# 百分比修饰符
			if stat_name.ends_with("_mult"):
				total += (value - 1.0) * instance.stacks
			else:
				total += value * instance.stacks
	
	return total

## 获取实体所有修饰符汇总
func get_total_modifiers(entity_id: String) -> Dictionary:
	var totals: Dictionary = {}
	if not _active_effects.has(entity_id):
		return totals
	
	for effect_id in _active_effects[entity_id].keys():
		var instance = _active_effects[entity_id][effect_id]
		var modifiers = instance.effect.get_modifiers()
		for stat_name in modifiers.keys():
			var value = float(modifiers.get(stat_name, 0.0))
			var current = float(totals.get(stat_name, 0.0))
			totals[stat_name] = current + value * instance.stacks
	
	return totals

## 检查实体是否有特定效果
func has_effect(effect_id: String, entity_id: String) -> bool:
	return _active_effects.has(entity_id) and _active_effects[entity_id].has(effect_id)

## 获取效果剩余时间
func get_remaining_time(effect_id: String, entity_id: String) -> float:
	if not has_effect(effect_id, entity_id):
		return 0.0
	return _active_effects[entity_id][effect_id].remaining_time

## 获取效果层数
func get_stacks(effect_id: String, entity_id: String) -> int:
	if not has_effect(effect_id, entity_id):
		return 0
	return _active_effects[entity_id][effect_id].stacks

# ========== 内部方法 ==========

func _get_effect_definition(effect_id: String) -> Dictionary:
	return _effect_definitions.get(effect_id, {})

func _create_effect_instance(effect: GameplayEffect, entity_id: String, stacks: int):
	var instance = EffectInstance.new()
	instance.entity_id = entity_id
	instance.effect = effect
	instance.stacks = mini(stacks, effect.max_stacks)
	instance.remaining_time = effect.duration
	instance.is_infinite = effect.is_infinite
	
	_active_effects[entity_id][effect.id] = instance
	
	# 应用属性修饰
	_apply_stat_modifiers(entity_id, effect, instance.stacks)
	effect.on_apply(entity_id)
	
	print("[EffectSystem] 效果已应用: %s -> %s (层数: %d)" % [effect.id, entity_id, instance.stacks])

func _handle_stack(effect_id: String, entity_id: String, additional_stacks: int):
	var instance = _active_effects[entity_id][effect_id]
	var effect: GameplayEffect = instance.effect
	var stack_mode = effect.stack_mode
	var max_stacks = effect.max_stacks
	
	match stack_mode:
		"refresh":
			# 刷新持续时间
			instance.remaining_time = effect.duration
			instance.stacks = mini(instance.stacks + additional_stacks, max_stacks)
			
		"extend":
			# 延长持续时间
			instance.remaining_time += effect.duration
			instance.stacks = mini(instance.stacks + additional_stacks, max_stacks)
			
		"intensity":
			# 增强效果（增加层数）
			var old_stacks = instance.stacks
			instance.stacks = mini(instance.stacks + additional_stacks, max_stacks)
			# 重新计算属性修饰
			if instance.stacks > old_stacks:
				_apply_stat_modifiers(entity_id, effect, instance.stacks - old_stacks)
			
		"separate":
			# 创建独立实例（这里简化处理，只增加层数）
			instance.stacks = mini(instance.stacks + additional_stacks, max_stacks)

func _remove_single_effect(effect_id: String, entity_id: String):
	if not _active_effects.has(entity_id) or not _active_effects[entity_id].has(effect_id):
		return
	
	var instance = _active_effects[entity_id][effect_id]
	
	# 移除属性修饰（取反）
	_remove_stat_modifiers(entity_id, instance.effect, instance.stacks)
	instance.effect.on_remove(entity_id)
	
	_active_effects[entity_id].erase(effect_id)
	
	# 清理空实体记录
	if _active_effects[entity_id].is_empty():
		_active_effects.erase(entity_id)
	
	print("[EffectSystem] 效果已移除: %s -> %s" % [effect_id, entity_id])

func _apply_stat_modifiers(entity_id: String, effect: GameplayEffect, stacks: int):
	var modifiers = effect.get_modifiers()
	for stat_name in modifiers.keys():
		var value = float(modifiers[stat_name])
		var final_value = value * stacks
		stat_modified.emit(entity_id, stat_name, final_value)

func _remove_stat_modifiers(entity_id: String, effect: GameplayEffect, stacks: int):
	var modifiers = effect.get_modifiers()
	for stat_name in modifiers.keys():
		var value = float(modifiers[stat_name])
		var final_value = -value * stacks  # 取反
		stat_modified.emit(entity_id, stat_name, final_value)

# ========== 游戏循环 ==========

func _process(delta: float):
	# 更新所有效果的持续时间
	_update_effects(delta)

func _update_effects(delta: float):
	var expired_effects = []
	
	for entity_id in _active_effects.keys():
		for effect_id in _active_effects[entity_id].keys():
			var instance = _active_effects[entity_id][effect_id]
			
			# 跳过无限持续时间的效果
			if instance.is_infinite:
				continue
			
			instance.remaining_time -= delta
			
			# 触发周期性效果
			var tick_interval = instance.effect.tick_interval
			if tick_interval > 0:
				instance.tick_timer += delta
				if instance.tick_timer >= tick_interval:
					instance.tick_timer = 0.0
					instance.effect.on_tick(entity_id, {"remaining_time": instance.remaining_time})
					effect_tick.emit(entity_id, effect_id, instance.remaining_time)
			
			# 检查过期
			if instance.remaining_time <= 0:
				expired_effects.append({"entity_id": entity_id, "effect_id": effect_id})
	
	# 移除过期效果
	for item in expired_effects:
		_remove_single_effect(item.effect_id, item.entity_id)
		effect_expired.emit(item.entity_id, item.effect_id)

# ========== 序列化 ==========

func serialize_entity_effects(entity_id: String) -> Array:
	if not _active_effects.has(entity_id):
		return []
	
	var result = []
	for effect_id in _active_effects[entity_id].keys():
		var instance = _active_effects[entity_id][effect_id]
		result.append({
			"effect_id": effect_id,
			"stacks": instance.stacks,
			"remaining_time": instance.remaining_time
		})
	return result

func deserialize_entity_effects(entity_id: String, data: Array):
	for item in data:
		var effect_id = item.get("effect_id", "")
		var stacks = item.get("stacks", 1)
		var remaining_time = item.get("remaining_time", 0.0)
		
		if apply_effect(effect_id, entity_id, stacks):
			# 恢复剩余时间
			if _active_effects.has(entity_id) and _active_effects[entity_id].has(effect_id):
				_active_effects[entity_id][effect_id].remaining_time = remaining_time

# ========== 效果实例类 ==========
class EffectInstance:
	var entity_id: String
	var effect: GameplayEffect
	var stacks: int = 1
	var remaining_time: float = 0.0
	var is_infinite: bool = false
	var tick_timer: float = 0.0
