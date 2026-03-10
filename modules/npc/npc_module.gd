extends Node
## NPC模块 - 管理器中
## 负责管理所有NPC的生成、销毁和数据
## 注意: 作为Autoload单例，不使用class_name

const NPCData = preload("res://modules/npc/npc_data.gd")
const NPCTradeComponent = preload("res://modules/npc/components/npc_trade_component.gd")
const MovementComponent = preload("res://systems/movement_component.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")
const GameWorldMerchantTradeComponent = preload("res://modules/npc/components/game_world_merchant_trade_component.gd")

# ========== 信号 ==========
signal npc_spawned(npc_id: String, npc: Node)
signal npc_despawned(npc_id: String)
signal npc_died(npc_id: String)
signal npc_recruited(npc_id: String)
signal npc_mood_changed(npc_id: String, mood_type: String, new_value: int)
signal player_met_npc(npc_id: String, first_time: bool)

# ========== 核心数据 ==========

# 所有活跃的NPC实例（旧2D链路，已废弃）
var active_npcs: Dictionary = {}  # npc_id -> Node
var active_npc_actors: Dictionary = {}  # npc_id -> Node3D
var active_npc_trade_components: Dictionary = {}  # npc_id -> NPCTradeComponent

# NPC数据库（所有可能的NPC定义）
var npc_database: Dictionary = {}  # npc_id -> NPCData

# ========== 初始化 ==========

func _ready():
	print("[NPCModule] NPC系统已初始化")
	_load_npc_database()
	
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

## 统一生成入口（3D Runtime）
func spawn_actor(role_kind: String, role_id: String, world_pos: Vector3, context: Dictionary = {}) -> Node3D:
	if role_kind.to_lower() != "npc":
		return null
	if role_id.is_empty():
		return null

	if active_npc_actors.has(role_id):
		var existing: Node3D = active_npc_actors[role_id]
		if existing and is_instance_valid(existing):
			return existing
		active_npc_actors.erase(role_id)

	var npc_data: NPCData = _build_runtime_npc_data(role_id)
	if not npc_data:
		push_warning("[NPCModule] 无法生成NPC，数据不存在: %s" % role_id)
		return null

	var actor := CharacterActorScript.new()
	actor.name = "NPC_%s" % role_id
	actor.position = world_pos
	var npc_body_color := _get_npc_color(npc_data)
	actor.set_placeholder_colors(npc_body_color.lightened(0.20), npc_body_color)
	actor.collision_layer = 1 << 1
	actor.collision_mask = 0
	actor.set_meta("npc_id", role_id)
	actor.set_meta("role_kind", "npc")
	actor.set_meta("spawn_id", str(context.get("spawn_id", role_id)))
	actor.set_meta("npc_data", npc_data)
	actor.add_to_group("npc")

	var collision_shape := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.0
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, 1.0, 0.0)
	actor.add_child(collision_shape)

	var name_label := Label3D.new()
	name_label.text = npc_data.get_display_name()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 32
	name_label.position = Vector3(0.0, 2.2, 0.0)
	actor.add_child(name_label)

	var movement_component := MovementComponent.new()
	actor.add_child(movement_component)
	if GridMovementSystem and GridMovementSystem.grid_world:
		movement_component.initialize(actor, GridMovementSystem.grid_world)

	if npc_data.can_trade:
		var trade_component := GameWorldMerchantTradeComponent.new() as NPCTradeComponent
		actor.add_child(trade_component)
		trade_component.initialize_with_data(npc_data)
		active_npc_trade_components[role_id] = trade_component

	active_npc_actors[role_id] = actor
	return actor

## 由外部系统注册运行时NPC（AIManager统一入口）
func register_npc_actor(npc_id: String, actor: Node3D, trade_component: NPCTradeComponent = null) -> void:
	if npc_id.is_empty() or not actor:
		return
	active_npc_actors[npc_id] = actor
	if trade_component:
		active_npc_trade_components[npc_id] = trade_component
	npc_spawned.emit(npc_id, actor)

## 由外部系统注销运行时NPC（AIManager统一入口）
func unregister_npc_actor(npc_id: String) -> void:
	if npc_id.is_empty():
		return
	if active_npc_actors.has(npc_id):
		active_npc_actors.erase(npc_id)
	active_npc_trade_components.erase(npc_id)
	npc_despawned.emit(npc_id)

func despawn_actor(role_id: String) -> void:
	if not active_npc_actors.has(role_id):
		return
	var actor: Node3D = active_npc_actors[role_id]
	active_npc_actors.erase(role_id)
	active_npc_trade_components.erase(role_id)
	if actor and is_instance_valid(actor):
		actor.queue_free()

## 在指定位置生成NPC
func spawn_npc(npc_id: String, _location: String = "", _show_message: bool = true) -> Node:
	push_warning("[NPCModule] spawn_npc 已废弃：旧2D NPC链路已移除 (%s)" % npc_id)
	return null

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
func get_npc(npc_id: String) -> Node:
	return active_npcs.get(npc_id, null)

## 获取NPC数据
func get_npc_data(npc_id: String) -> NPCData:
	return npc_database.get(npc_id, null)

## 获取某位置的所有NPC
func get_npcs_at_location(location: String) -> Array[Node]:
	var result: Array[Node] = []
	for npc in active_npcs.values():
		if npc.current_location == location:
			result.append(npc)
	return result

## 获取某类型的所有NPC
func get_npcs_by_type(npc_type: NPCData.Type) -> Array[Node]:
	var result: Array[Node] = []
	for npc in active_npcs.values():
		if npc.npc_data.npc_type == npc_type:
			result.append(npc)
	return result

## 获取可交互的NPC
func get_interactable_npcs_at(location: String) -> Array[Node]:
	var result: Array[Node] = []
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

## 3D场景中的统一交互入口
func start_npc_interaction(npc_id: String) -> bool:
	var npc_data: NPCData = _build_runtime_npc_data(npc_id)
	if not npc_data:
		return false

	var speaker := npc_data.name if not npc_data.name.is_empty() else npc_id
	var greeting := "你好，我是%s。" % speaker
	if npc_data.can_trade:
		greeting = "需要补给吗？我这里还能交易。"
	DialogModule.show_dialog(greeting, speaker)
	await DialogModule.dialog_finished

	if npc_data.can_trade:
		var choice: int = await DialogModule.show_choices(["交易", "闲聊", "离开"])
		match choice:
			0:
				var trade_component: NPCTradeComponent = active_npc_trade_components.get(npc_id, null)
				if trade_component:
					var opened: bool = await trade_component.open_trade_ui()
					if not opened:
						DialogModule.show_dialog("现在无法交易。", speaker)
						await DialogModule.dialog_finished
			1:
				DialogModule.show_dialog("夜晚外出要小心。", speaker)
				await DialogModule.dialog_finished
			_:
				DialogModule.show_dialog("保重。", speaker)
				await DialogModule.dialog_finished
	else:
		var lines: Array[String] = [
			"别走太远，外面很危险。",
			"活着回来就好。",
			"如果你发现线索，记得告诉我。"
		]
		DialogModule.show_dialog(lines[randi() % lines.size()], speaker)
		await DialogModule.dialog_finished

	return true

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

func _on_player_changed_location(_data: Dictionary):
	# 旧2D按地点刷NPC链路已移除。3D场景由AISpawnSystem负责。
	return

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

func _build_runtime_npc_data(npc_id: String) -> NPCData:
	var record = npc_database.get(npc_id, null)
	if not record:
		return null

	if record is NPCData:
		return record as NPCData

	var npc_data := NPCData.new()
	if record is Dictionary:
		npc_data.deserialize(record)
		npc_data.id = str(record.get("id", npc_id))
		npc_data.name = str(record.get("name", npc_data.name))
		if npc_data.default_location.is_empty():
			npc_data.default_location = str(record.get("default_location", ""))
		if npc_data.current_location.is_empty():
			npc_data.current_location = npc_data.default_location
	return npc_data

## 提供运行时数据给AI系统
func get_runtime_npc_data(npc_id: String) -> NPCData:
	return _build_runtime_npc_data(npc_id)

## 提供NPC颜色给AI系统
func get_npc_color(npc_data: NPCData) -> Color:
	return _get_npc_color(npc_data)

func _get_npc_color(npc_data: NPCData) -> Color:
	if npc_data.can_trade:
		return Color(0.86, 0.73, 0.33, 1.0)
	if npc_data.npc_type == NPCData.Type.HOSTILE:
		return Color(0.78, 0.28, 0.28, 1.0)
	return Color(0.58, 0.72, 0.88, 1.0)

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
