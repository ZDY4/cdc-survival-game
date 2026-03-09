extends Node
## NPC情绪组件
## 管理NPC的情绪变化和情绪影响

class_name NPCMoodComponent

signal mood_changed(mood_type: String, new_value: int, old_value: int)
signal attitude_changed(new_attitude: String)

var npc: Node

func initialize(parent_npc: Node):
	npc = parent_npc

## 改变情绪值
func change_mood(mood_type: String, delta: int) -> int:
	if not npc or not npc.npc_data:
		return 0
	
	if not npc.npc_data.mood.has(mood_type):
		push_warning("[NPCMoodComponent] 未知的情绪类型: %s" % mood_type)
		return 0
	
	var old_value = npc.npc_data.mood[mood_type]
	var new_value = clamp(old_value + delta, 0, 100)
	
	npc.npc_data.mood[mood_type] = new_value
	
	if old_value != new_value:
		mood_changed.emit(mood_type, new_value, old_value)
		
		# 检查态度变化
		_check_attitude_change()
	
	return new_value

## 设置情绪值
func set_mood(mood_type: String, value: int) -> int:
	if not npc or not npc.npc_data:
		return 0
	
	if not npc.npc_data.mood.has(mood_type):
		return 0
	
	var old_value = npc.npc_data.mood[mood_type]
	var new_value = clamp(value, 0, 100)
	
	npc.npc_data.mood[mood_type] = new_value
	
	if old_value != new_value:
		mood_changed.emit(mood_type, new_value, old_value)
		_check_attitude_change()
	
	return new_value

## 获取情绪值
func get_mood(mood_type: String) -> int:
	if not npc or not npc.npc_data:
		return 0
	
	return npc.npc_data.mood.get(mood_type, 0)

## 获取当前情绪状态（用于立绘）
func get_current_emotion() -> String:
	if not npc or not npc.npc_data:
		return "normal"
	
	var mood = npc.npc_data.mood
	
	# 优先级：愤怒 > 恐惧 > 其他
	if mood.anger > 70:
		return "angry"
	elif mood.fear > 70:
		return "fear"
	elif mood.anger > 40:
		return "annoyed"
	elif mood.friendliness > 70:
		return "happy"
	elif mood.friendliness > 40:
		return "normal"
	else:
		return "cold"

## 获取友好度等级
func get_friendlyness_level() -> String:
	if not npc or not npc.npc_data:
		return "一般"
	
	return npc.npc_data.get_friendlyness_level()

## 检查态度变化
func _check_attitude_change():
	if not npc or not npc.npc_data:
		return
	
	var mood = npc.npc_data.mood
	var current_attitude = npc.npc_data.state.get("attitude", "neutral")
	var new_attitude = current_attitude
	
	# 根据情绪判断态度
	if mood.anger > 60 or mood.friendliness < 20:
		new_attitude = "hostile"
	elif mood.fear > 60:
		new_attitude = "fearful"
	elif mood.friendliness > 70 and mood.trust > 50:
		new_attitude = "friendly"
	elif mood.friendliness > 40:
		new_attitude = "neutral"
	else:
		new_attitude = "cautious"
	
	if new_attitude != current_attitude:
		npc.npc_data.state.attitude = new_attitude
		attitude_changed.emit(new_attitude)
		
		# 根据态度改变交互行为
		_update_behavior_by_attitude(new_attitude)

## 根据态度更新行为
func _update_behavior_by_attitude(attitude: String):
	match attitude:
		"hostile":
			npc.npc_data.state.is_hostile = true
			npc.npc_data.can_trade = false
			npc.npc_data.can_recruit = false
		
		"friendly":
			npc.npc_data.state.is_hostile = false
			npc.npc_data.state.trade_enabled = true
		
		"fearful":
			npc.npc_data.state.is_hostile = false
			# 恐惧时可能给出更好的交易价格
			npc.npc_data.trade_data.buy_price_modifier = 0.8

## 随时间自然衰减/恢复
func on_time_passed(hours: int):
	if not npc or not npc.npc_data:
		return
	
	# 愤怒随时间降低
	if npc.npc_data.mood.anger > 0:
		change_mood("anger", -hours * 2)
	
	# 恐惧随时间降低
	if npc.npc_data.mood.fear > 0:
		change_mood("fear", -hours * 3)
	
	# 友好度缓慢趋向中性（50）
	var friendliness = npc.npc_data.mood.friendliness
	if friendliness > 50:
		change_mood("friendliness", -hours)
	elif friendliness < 50:
		change_mood("friendliness", hours)
