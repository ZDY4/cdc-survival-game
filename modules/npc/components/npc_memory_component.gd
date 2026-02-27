extends Node
## NPC记忆组件
## 记录与玩家的交互历史，影响对话和行为

class_name NPCMemoryComponent

signal memory_updated(key: String, value: Variant)

var npc: NPCBase
var memory: Dictionary:
	get:
		return npc.npc_data.memory if npc and npc.npc_data else {}

func initialize(parent_npc: NPCBase):
	npc = parent_npc

## 记录玩家见面
func on_player_met():
	if not npc or not npc.npc_data:
		return
	
	var first_time = not memory.met_player
	
	memory.met_player = true
	memory.interaction_count += 1
	memory.last_meeting_time = _get_current_game_time()
	memory.last_meeting_location = npc.current_location
	
	if first_time:
		print("[NPCMemoryComponent] NPC %s 首次见到玩家" % npc.npc_name)
	else:
		print("[NPCMemoryComponent] NPC %s 第%d次见到玩家" % [npc.npc_name, memory.interaction_count])
	
	memory_updated.emit("met_player", true)

## 记录玩家行为
func record_player_action(action: String, details: Dictionary = {}):
	if not npc or not npc.npc_data:
		return
	
	var record = {
		"action": action,
		"time": _get_current_game_time(),
		"location": npc.current_location,
		"details": details
	}
	
	memory.player_actions.append(record)
	
	# 只保留最近20个行为
	while memory.player_actions.size() > 20:
		memory.player_actions.pop_front()
	
	memory_updated.emit("player_actions", memory.player_actions)
	
	print("[NPCMemoryComponent] NPC %s 记录了玩家行为: %s" % [npc.npc_name, action])

## 记录对话选择
func record_dialog_choice(choice_text: String):
	record_player_action("dialog_choice", {"text": choice_text})

## 记录分享的秘密
func record_shared_secret(secret: String):
	if not memory.shared_secrets.has(secret):
		memory.shared_secrets.append(secret)
		memory_updated.emit("shared_secrets", memory.shared_secrets)

## 记录承诺
func record_promise(promise: String):
	memory.promises.append({
		"promise": promise,
		"time": _get_current_game_time(),
		"fulfilled": false
	})
	memory_updated.emit("promises", memory.promises)

## 履行承诺
func fulfill_promise(promise_index: int):
	if promise_index >= 0 and promise_index < memory.promises.size():
		memory.promises[promise_index].fulfilled = true
		memory_updated.emit("promises", memory.promises)
		
		# 大幅提升信任度
		if npc.mood_component:
			npc.change_mood("trust", 20)
			npc.change_mood("friendliness", 15)

## 检查是否有未履行的承诺
func has_unfulfilled_promises() -> bool:
	for promise in memory.promises:
		if not promise.fulfilled:
			return true
	return false

## 获取记忆文本（用于对话）
func get_memory_text() -> String:
	if not npc or not npc.npc_data:
		return ""
	
	var texts: Array[String] = []
	
	# 根据记忆生成对话文本
	if memory.interaction_count == 1:
		texts.append("这是我们第一次见面。")
	elif memory.interaction_count <= 3:
		texts.append("我们又见面了。")
	else:
		texts.append("很高兴再次见到你，我们已经见过%d次了。" % memory.interaction_count)
	
	# 提及上次见面
	if memory.last_meeting_location and memory.last_meeting_location != npc.current_location:
		texts.append("上次我们在%s见面。" % memory.last_meeting_location)
	
	# 提及玩家行为
	var important_actions = _get_important_actions()
	if not important_actions.is_empty():
		var action = important_actions[0]
		match action.action:
			"helped":
				texts.append("你上次帮了我大忙，我很感激。")
			"attacked":
				texts.append("你之前攻击过我，我记忆犹新。")
			"traded":
				texts.append("上次的交易很愉快。")
	
	return " ".join(texts)

## 获取重要行为记录
func _get_important_actions() -> Array:
	var important: Array = []
	
	for action in memory.player_actions:
		if action.action in ["helped", "attacked", "saved", "betrayed"]:
			important.append(action)
	
	return important

## 检查是否记得特定事件
func remembers_event(event_type: String) -> bool:
	for action in memory.player_actions:
		if action.action == event_type:
			return true
	return false

## 获取上次行为
func get_last_action() -> Dictionary:
	if memory.player_actions.is_empty():
		return {}
	return memory.player_actions[-1]

## 清除所有记忆（用于测试或特殊事件）
func clear_memory():
	memory.met_player = false
	memory.interaction_count = 0
	memory.player_actions.clear()
	memory.shared_secrets.clear()
	memory.promises.clear()
	memory.last_meeting_time = -1
	memory.last_meeting_location = ""
	memory_updated.emit("cleared", true)

func _get_current_game_time() -> int:
	if TimeManager:
		return TimeManager.current_game_time
	return 0
