extends Node

# 定义事件类型
enum EventType {
	# 系统事件
	GAME_STARTED,
	GAME_SAVED,
	GAME_LOADED,
	STATUS_CHANGED,
	STATUS_WARNING,
	
	# 玩家事件
	PLAYER_HURT,
	PLAYER_HEALED,
	PLAYER_DIED,
	INVENTORY_CHANGED,
	
	# 场景事件
	LOCATION_CHANGED,
	SCENE_INTERACTION,
	
	# 对话事件
	DIALOG_STARTED,
	DIALOG_CHOICE_MADE,
	DIALOG_ENDED,
	
	# 战斗事件
	COMBAT_STARTED,
	COMBAT_ENDED,
	ENEMY_DEFEATED,
	ENEMY_ENCOUNTER,
	
	# 资源事件
	ITEM_ACQUIRED,
	ITEM_CONSUMED,
	CRAFTING_COMPLETED,
	
	# 天气事件
	WEATHER_CHANGED,
	DAY_NIGHT_CHANGED,
	
	# 任务事件
	QUEST_STARTED,
	QUEST_UPDATED,
	QUEST_COMPLETED,
	
	# NPC事件
	NPC_RECRUITED,
	NPC_DIED,
	NPC_TRADE_COMPLETED,
	
	# 网格移动事件
	PLAYER_MOVED,
	GRID_CLICKED,
	MOVEMENT_STARTED,
	MOVEMENT_FINISHED,
	PATH_PREVIEW_UPDATED
}

var _event_listeners: Dictionary = {}

func _ready():
	# 初始化事件监听字典
	for i in EventType.size():
		_event_listeners[i] = []

# 发布事件
func emit(event_type: EventType, data: Dictionary = {}):
	if _event_listeners.has(event_type):
		for listener in _event_listeners[event_type]:
			listener.call(data)

# 订阅事件
func subscribe(event_type: EventType, callback: Callable):
	if not _event_listeners.has(event_type):
		_event_listeners[event_type] = []
	_event_listeners[event_type].append(callback)

# 取消订阅
func unsubscribe(event_type: EventType, callback: Callable):
	if _event_listeners.has(event_type) && callback in _event_listeners[event_type]:
		_event_listeners[event_type].erase(callback)