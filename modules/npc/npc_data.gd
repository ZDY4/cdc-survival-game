extends "res://core/character_base.gd"
## NPCData - NPC数据类
## 继承自CharacterBase，添加NPC特有属性和状态

class_name NPCData

# ========== NPC类型枚举 ==========
enum Type {
	FRIENDLY,      # 友好 - 可交易、招募
	NEUTRAL,       # 中立 - 根据行为改变态度
	HOSTILE,       # 敌对 - 会攻击
	TRADER,        # 商人 - 专门交易
	QUEST_GIVER,   # 任务发布者
	RECRUITABLE    # 可招募
}

# ========== 基础信息（扩展） ==========
var npc_type: Type = Type.FRIENDLY
var title: String = ""                    # 称号，如"废土商人"

# ========== 表情立绘系统 ==========
# 表情类型: normal, happy, angry, sad, fear, surprised, cold, annoyed
var expression_paths: Dictionary = {}     # 表情立绘路径映射 {emotion: path}

# ========== 情绪系统 (0-100) ==========
var mood: Dictionary = {
	"friendliness": 50,   # 友好度（影响交易价格和招募）
	"trust": 30,          # 信任度（影响信息分享和任务）
	"fear": 0,            # 恐惧度（过高会逃跑或投降）
	"anger": 0            # 愤怒度（过高会攻击）
}

# ========== 位置 ==========
var current_location: String = "safehouse"
var default_location: String = "safehouse"  # 默认位置
var schedule: Array[Dictionary] = []         # 日程安排

# ========== 能力标志 ==========
var can_trade: bool = false
var can_recruit: bool = false
var can_give_quest: bool = false
var can_heal: bool = false
var can_repair: bool = false
var can_craft: bool = false

# ========== 交易数据 ==========
var trade_data: Dictionary = {
	"buy_price_modifier": 1.0,    # 购买价格倍率
	"sell_price_modifier": 1.0,   # 出售价格倍率
	"currency_preference": [],    # 偏好货币类型
	"restock_interval": 24,       # 补货间隔（游戏小时）
	"last_restock_time": 0,       # 上次补货时间
	"inventory": [],              # 库存物品 [{"id": "", "count": 1, "price": 10}]
	"max_trade_times": -1,        # 最大交易次数（-1无限）
	"trade_count_today": 0,       # 今日交易次数
	"money": 0                    # NPC拥有的货币
}

# ========== 招募条件 ==========
var recruitment: Dictionary = {
	"required_quests": [],        # 需要完成的任务
	"required_items": [],         # 需要给予的物品 [{"id": "", "count": 1}]
	"min_charisma": 0,            # 需要玩家魅力
	"min_friendliness": 70,       # 需要的友好度
	"min_trust": 50,              # 需要的信任度
	"cost_items": [],             # 招募消耗
	"cost_money": 0               # 招募消耗金钱
}

# ========== 对话树 ==========
var dialog_tree_id: String = ""             # 对话树ID
var current_dialog_node: String = "start"   # 当前对话节点

# ========== 记忆（影响对话） ==========
var memory: Dictionary = {
	"met_player": false,          # 是否见过玩家
	"interaction_count": 0,       # 交互次数
	"player_actions": [],         # 记住的玩家行为 [{"action": "helped", "time": 0}]
	"last_meeting_time": -1,      # 上次见面时间（游戏时间戳）
	"last_meeting_location": "",  # 上次见面地点
	"shared_secrets": [],         # 分享过的秘密
	"promises": [],               # 玩家做出的承诺
	"debt_items": []              # NPC欠玩家的物品
}

# ========== 当前状态 ==========
var state: Dictionary = {
	"is_alive": true,
	"is_recruited": false,
	"is_busy": false,             # 是否忙碌（不可交互）
	"is_hostile": false,          # 是否敌对
	"current_activity": "idle",   # 当前活动
	"active_quests": [],          # 当前发布的任务ID列表
	"completed_quests": [],       # 已完成的任务
	"trade_enabled": true         # 是否允许交易
}

# ========== 序列化/反序列化（扩展） ==========

func serialize() -> Dictionary:
	# 先获取基类的序列化数据
	var base_data = super.serialize()
	
	# 合并NPC特有数据
	base_data.merge({
		"npc_type": npc_type,
		"title": title,
		"expression_paths": expression_paths.duplicate(),
		"mood": mood.duplicate(),
		"current_location": current_location,
		"default_location": default_location,
		"schedule": schedule.duplicate(),
		"can_trade": can_trade,
		"can_recruit": can_recruit,
		"can_give_quest": can_give_quest,
		"can_heal": can_heal,
		"can_repair": can_repair,
		"can_craft": can_craft,
		"trade_data": {
			"buy_price_modifier": trade_data.buy_price_modifier,
			"sell_price_modifier": trade_data.sell_price_modifier,
			"currency_preference": trade_data.currency_preference.duplicate(),
			"restock_interval": trade_data.restock_interval,
			"last_restock_time": trade_data.last_restock_time,
			"inventory": trade_data.inventory.duplicate(),
			"max_trade_times": trade_data.max_trade_times,
			"trade_count_today": trade_data.trade_count_today,
			"money": trade_data.money
		},
		"recruitment": {
			"required_quests": recruitment.required_quests.duplicate(),
			"required_items": recruitment.required_items.duplicate(),
			"min_charisma": recruitment.min_charisma,
			"min_friendliness": recruitment.min_friendliness,
			"min_trust": recruitment.min_trust,
			"cost_items": recruitment.cost_items.duplicate(),
			"cost_money": recruitment.cost_money
		},
		"dialog_tree_id": dialog_tree_id,
		"current_dialog_node": current_dialog_node,
		"memory": {
			"met_player": memory.met_player,
			"interaction_count": memory.interaction_count,
			"player_actions": memory.player_actions.duplicate(),
			"last_meeting_time": memory.last_meeting_time,
			"last_meeting_location": memory.last_meeting_location,
			"shared_secrets": memory.shared_secrets.duplicate(),
			"promises": memory.promises.duplicate(),
			"debt_items": memory.debt_items.duplicate()
		},
		"state": {
			"is_alive": state.is_alive,
			"is_recruited": state.is_recruited,
			"is_busy": state.is_busy,
			"is_hostile": state.is_hostile,
			"current_activity": state.current_activity,
			"active_quests": state.active_quests.duplicate(),
			"completed_quests": state.completed_quests.duplicate(),
			"trade_enabled": state.trade_enabled
		}
	})
	
	return base_data

func deserialize(data: Dictionary):
	# 先调用基类的反序列化
	super.deserialize(data)
	
	npc_type = data.get("npc_type", Type.FRIENDLY)
	title = data.get("title", "")
	
	if data.has("expression_paths"):
		expression_paths = data.expression_paths.duplicate()
	if data.has("mood"):
		mood.merge(data.mood, true)
	
	current_location = data.get("current_location", default_location)
	default_location = data.get("default_location", "safehouse")
	if data.has("schedule"):
		schedule = data.schedule.duplicate()
	
	can_trade = data.get("can_trade", false)
	can_recruit = data.get("can_recruit", false)
	can_give_quest = data.get("can_give_quest", false)
	can_heal = data.get("can_heal", false)
	can_repair = data.get("can_repair", false)
	can_craft = data.get("can_craft", false)
	
	if data.has("trade_data"):
		trade_data.merge(data.trade_data, true)
	if data.has("recruitment"):
		recruitment.merge(data.recruitment, true)
	
	dialog_tree_id = data.get("dialog_tree_id", "")
	current_dialog_node = data.get("current_dialog_node", "start")
	
	if data.has("memory"):
		memory.merge(data.memory, true)
	if data.has("state"):
		state.merge(data.state, true)

# ========== 便捷方法 ==========

func get_display_name() -> String:
	if title.is_empty():
		return name
	return "%s·%s" % [title, name]

func get_type_string() -> String:
	match npc_type:
		Type.FRIENDLY:
			return "友好"
		Type.NEUTRAL:
			return "中立"
		Type.HOSTILE:
			return "敌对"
		Type.TRADER:
			return "商人"
		Type.QUEST_GIVER:
			return "任务"
		Type.RECRUITABLE:
			return "可招募"
		_:
			return "未知"

func is_interactable() -> bool:
	return state.is_alive and not state.is_recruited and not state.is_busy

func get_friendlyness_level() -> String:
	var value = mood.friendliness
	if value >= 80:
		return "亲密"
	elif value >= 60:
		return "友好"
	elif value >= 40:
		return "一般"
	elif value >= 20:
		return "冷淡"
	else:
		return "敌对"

func change_mood(mood_type: String, delta: int):
	if mood.has(mood_type):
		mood[mood_type] = clamp(mood[mood_type] + delta, 0, 100)

## 获取指定表情的立绘路径
func get_expression_path(emotion: String) -> String:
	# 如果指定了该表情的立绘，使用它
	if expression_paths.has(emotion) and not expression_paths[emotion].is_empty():
		return expression_paths[emotion]
	# 否则返回默认立绘
	return portrait_path

## 设置表情立绘路径
func set_expression_path(emotion: String, path: String):
	expression_paths[emotion] = path

func record_player_action(action: String, details: Dictionary = {}):
	var record = {
		"action": action,
		"time": TimeManager.current_game_time if TimeManager else 0,
		"details": details
	}
	memory.player_actions.append(record)
	# 只保留最近20个行为
	if memory.player_actions.size() > 20:
		memory.player_actions.pop_front()
