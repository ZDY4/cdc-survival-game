extends Node
## NPC模块 - 管理器中
## 负责管理所有NPC的生成、销毁和数据
## 注意: 作为Autoload单例，不使用class_name

# ========== 信号 ==========
signal npc_spawned(npc_id: String, npc: NPCBase)
signal npc_despawned(npc_id: String)
signal npc_died(npc_id: String)
signal npc_recruited(npc_id: String)
signal npc_mood_changed(npc_id: String, mood_type: String, new_value: int)
signal player_met_npc(npc_id: String, first_time: bool)

# ========== 核心数据 ==========

# 所有活跃的NPC实例（当前场景中的）
var active_npcs: Dictionary = {}  # npc_id -> NPCBase

# NPC数据库（所有可能的NPC定义）
var npc_database: Dictionary = {}  # npc_id -> NPCData

# NPC场景资源
var _npc_scene: PackedScene = null

# ========== 初始化 ==========

func _ready():
	print("[NPCModule] NPC系统已初始化")
	_load_npc_database()
	# 运行时加载场景文件，避免文件不存在时出错
	if FileAccess.file_exists("res://modules/npc/npc_base.tscn"):
		_npc_scene = load("res://modules/npc/npc_base.tscn")
	else:
		push_warning("[NPCModule] npc_base.tscn 不存在，NPC生成功能不可用")
	
	# 订阅事件
	if EventBus:
		EventBus.subscribe(EventBus.EventType.LOCATION_CHANGED, _on_player_changed_location)
		EventBus.subscribe(EventBus.EventType.DAY_NIGHT_CHANGED, _on_time_advanced)

# ========== 数据加载 ==========

func _load_npc_database():
	# 尝试从DataManager加载
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager:
		var data = data_manager.get_data("npcs")
		if not data.is_empty():
			npc_database = data
			print("[NPCModule] 从DataManager加载了 %d 个NPC数据" % npc_database.size())
			return
	
	# 加载默认数据
	_load_default_npcs()

func _load_default_npcs():
	# 默认创建一个示例商人NPC
	var trader_data = NPCData.new()
	trader_data.id = "trader_lao_wang"
	trader_data.name = "老王"
	trader_data.title = "废土商人"
	trader_data.description = "在这个区域经营多年的老商人，消息灵通，货物齐全。"
	trader_data.npc_type = NPCData.Type.TRADER
	trader_data.portrait_path = "res://assets/portraits/trader.png"
	trader_data.level = 5
	trader_data.attributes.charisma = 15
	trader_data.can_trade = true
	trader_data.can_give_quest = true
	trader_data.default_location = "safehouse"
	trader_data.current_location = "safehouse"
	
	# 设置交易数据
	trader_data.trade_data.inventory = [
		{"id": "medkit", "count": 3, "price": 50},
		{"id": "bandage", "count": 10, "price": 10},
		{"id": "ammo_pistol", "count": 50, "price": 5},
		{"id": "food_canned", "count": 5, "price": 15}
	]
	trader_data.trade_data.buy_price_modifier = 1.2
	trader_data.trade_data.sell_price_modifier = 0.8
	
	# 设置招募条件
	trader_data.recruitment.min_charisma = 10
	trader_data.recruitment.min_friendliness = 80
	trader_data.recruitment.cost_items = [{"id": "food_canned", "count": 20}]
	
	npc_database[trader_data.id] = trader_data
	print("[NPCModule] 加载了默认NPC数据")

# ========== NPC生成/销毁 ==========

## 在指定位置生成NPC
func spawn_npc(npc_id: String, location: String = "", show_message: bool = true) -> NPCBase:
	# 检查是否已存在
	if active_npcs.has(npc_id):
		push_warning("[NPCModule] NPC %s 已经存在，返回现有实例" % npc_id)
		return active_npcs[npc_id]
	
	# 获取NPC数据
	var npc_data = npc_database.get(npc_id)
	if not npc_data:
		push_error("[NPCModule] NPC数据不存在: %s" % npc_id)
		return null
	
	# 检查是否已死亡或被招募
	if not npc_data.state.is_alive:
		push_warning("[NPCModule] NPC %s 已死亡，无法生成" % npc_id)
		return null
	if npc_data.state.is_recruited:
		push_warning("[NPCModule] NPC %s 已被招募，无法生成" % npc_id)
		return null
	
	# 实例化NPC
	if not _npc_scene:
		if FileAccess.file_exists("res://modules/npc/npc_base.tscn"):
			_npc_scene = load("res://modules/npc/npc_base.tscn")
		else:
			push_error("[NPCModule] npc_base.tscn 不存在，无法生成NPC")
			return null
	
	var npc = _npc_scene.instantiate()
	if not npc:
		push_error("[NPCModule] 无法实例化NPC场景")
		return null
	
	# 初始化NPC
	npc.initialize(npc_data)
	
	# 设置位置
	if location.is_empty():
		location = npc_data.default_location
	npc.set_location(location)
	
	# 添加到场景
	get_tree().current_scene.add_child(npc)
	active_npcs[npc_id] = npc
	
	# 连接信号
	npc.npc_died.connect(_on_npc_died)
	npc.npc_recruited.connect(_on_npc_recruited)
	npc.interaction_started.connect(_on_npc_interaction_started)
	
	# 发送信号
	npc_spawned.emit(npc_id, npc)
	
	if show_message:
		print("[NPCModule] NPC %s 已在 %s 生成" % [npc_id, location])
	
	return npc

## 移除NPC（但不删除数据）
func despawn_npc(npc_id: String):
	if active_npcs.has(npc_id):
		var npc = active_npcs[npc_id]
		npc.queue_free()
		active_npcs.erase(npc_id)
		npc_despawned.emit(npc_id)
		print("[NPCModule] NPC %s 已移除" % npc_id)

## 移除某位置的所有NPC
func despawn_npcs_at_location(location: String):
	var to_remove: Array[String] = []
	for npc_id in active_npcs:
		if active_npcs[npc_id].current_location == location:
			to_remove.append(npc_id)
	
	for npc_id in to_remove:
		despawn_npc(npc_id)

# ========== NPC查询 ==========

## 获取活跃NPC
func get_npc(npc_id: String) -> NPCBase:
	return active_npcs.get(npc_id, null)

## 获取NPC数据
func get_npc_data(npc_id: String) -> NPCData:
	return npc_database.get(npc_id, null)

## 获取某位置的所有NPC
func get_npcs_at_location(location: String) -> Array[NPCBase]:
	var result: Array[NPCBase] = []
	for npc in active_npcs.values():
		if npc.current_location == location:
			result.append(npc)
	return result

## 获取某类型的所有NPC
func get_npcs_by_type(npc_type: NPCData.Type) -> Array[NPCBase]:
	var result: Array[NPCBase] = []
	for npc in active_npcs.values():
		if npc.npc_data.npc_type == npc_type:
			result.append(npc)
	return result

## 获取可交互的NPC
func get_interactable_npcs_at(location: String) -> Array[NPCBase]:
	var result: Array[NPCBase] = []
	for npc in active_npcs.values():
		if npc.current_location == location and npc.is_interactable():
			result.append(npc)
	return result

## 获取玩家已招募的队友
func get_recruited_npcs() -> Array[NPCData]:
	var result: Array[NPCData] = []
	for npc_data in npc_database.values():
		if npc_data.state.is_recruited:
			result.append(npc_data)
	return result

# ========== 交互功能 ==========

## 开始与NPC对话
func start_dialog(npc_id: String) -> bool:
	var npc = get_npc(npc_id)
	if not npc:
		push_warning("[NPCModule] 无法与不存在或不在当前场景的NPC对话: %s" % npc_id)
		return false
	
	if not npc.is_interactable():
		push_warning("[NPCModule] NPC %s 当前不可交互" % npc_id)
		return false
	
	var result = await npc.start_dialog()
	return result

## 开始与NPC交易
func start_trade(npc_id: String) -> bool:
	var npc = get_npc(npc_id)
	if not npc:
		return false
	
	if not npc.can_trade():
		push_warning("[NPCModule] NPC %s 不可交易" % npc_id)
		return false
	
	var result = await npc.open_trade_ui()
	return result

## 尝试招募NPC
func try_recruit(npc_id: String) -> Dictionary:
	var npc = get_npc(npc_id)
	if not npc:
		return {"success": false, "reason": "NPC不存在或不在当前场景"}
	
	return npc.check_recruitment_conditions()

## 确认招募NPC
func confirm_recruit(npc_id: String) -> bool:
	var npc = get_npc(npc_id)
	if not npc:
		return false
	
	return npc.on_recruited()

# ========== 事件处理 ==========

func _on_player_changed_location(data: Dictionary):
	var new_location = data.get("location", "")
	var old_location = data.get("old_location", "")
	
	# 移除旧位置的NPC（可选，取决于游戏设计）
	# despawn_npcs_at_location(old_location)
	
	# 生成新位置应该存在的NPC
	for npc_data in npc_database.values():
		if npc_data.default_location == new_location and npc_data.state.is_alive and not npc_data.state.is_recruited:
			# 检查是否应该生成（概率或剧情条件）
			if not active_npcs.has(npc_data.id):
				spawn_npc(npc_data.id, new_location, false)
	
	print("[NPCModule] 玩家移动到 %s，更新了NPC" % new_location)

func _on_time_advanced(data: Dictionary):
	var hours = data.get("hours", 0)
	
	# 更新所有NPC的日程
	for npc in active_npcs.values():
		npc.on_time_advanced(hours)
	
	# 处理补货
	for npc_data in npc_database.values():
		if npc_data.can_trade:
			npc_data.trade_data.last_restock_time += hours
			if npc_data.trade_data.last_restock_time >= npc_data.trade_data.restock_interval:
				_restock_npc_inventory(npc_data)

func _on_npc_died(npc_id: String):
	if npc_database.has(npc_id):
		npc_database[npc_id].state.is_alive = false
	npc_died.emit(npc_id)

func _on_npc_recruited(npc_id: String):
	if npc_database.has(npc_id):
		npc_database[npc_id].state.is_recruited = true
	
	# 从场景中移除
	if active_npcs.has(npc_id):
		active_npcs[npc_id].queue_free()
		active_npcs.erase(npc_id)
	
	npc_recruited.emit(npc_id)
	print("[NPCModule] NPC %s 已被招募" % npc_id)

func _on_npc_interaction_started(npc_id: String):
	var npc_data = npc_database.get(npc_id)
	if npc_data:
		var first_time = not npc_data.memory.met_player
		if first_time:
			npc_data.memory.met_player = true
		player_met_npc.emit(npc_id, first_time)

# ========== 数据管理 ==========

func _restock_npc_inventory(npc_data: NPCData):
	npc_data.trade_data.last_restock_time = 0
	npc_data.trade_data.trade_count_today = 0
	
	# 恢复默认库存
	# TODO: 从配置文件加载默认库存
	print("[NPCModule] NPC %s 的库存已补货" % npc_data.id)

## 添加新的NPC定义
func register_npc(npc_data: NPCData):
	npc_database[npc_data.id] = npc_data
	print("[NPCModule] 注册了新的NPC: %s" % npc_data.id)

## 获取所有NPC数据（用于编辑器）
func get_all_npc_data() -> Dictionary:
	return npc_database

## 保存所有NPC数据（用于存档）
func serialize_all_data() -> Dictionary:
	var result = {}
	for npc_id in npc_database:
		result[npc_id] = npc_database[npc_id].serialize()
	return result

## 加载NPC数据（用于读档）
func deserialize_all_data(data: Dictionary):
	for npc_id in data:
		if npc_database.has(npc_id):
			npc_database[npc_id].deserialize(data[npc_id])
		else:
			# 创建新的NPC数据
			var npc_data = NPCData.new()
			npc_data.deserialize(data[npc_id])
			npc_database[npc_id] = npc_data

## 重置所有NPC（用于新游戏）
func reset_all_npcs():
	for npc_data in npc_database.values():
		npc_data.state.is_alive = true
		npc_data.state.is_recruited = false
		npc_data.state.is_hostile = false
		npc_data.state.is_busy = false
		npc_data.memory.met_player = false
		npc_data.memory.interaction_count = 0
		npc_data.memory.player_actions.clear()
		npc_data.mood.friendliness = 50
		npc_data.mood.trust = 30
		npc_data.mood.fear = 0
		npc_data.mood.anger = 0
	
	# 清除所有活跃的NPC
	for npc_id in active_npcs.keys():
		despawn_npc(npc_id)
	
	print("[NPCModule] 所有NPC已重置")
