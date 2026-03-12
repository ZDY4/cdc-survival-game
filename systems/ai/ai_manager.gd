extends Node
## AIManager - Unified runtime actor provider and NPC runtime registry for 3D scenes.

class_name AIManager

const MovementComponent = preload("res://systems/movement_component.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")
const AIController = preload("res://systems/ai/ai_controller.gd")
const GameWorldMerchantTradeComponent = preload("res://modules/npc/components/game_world_merchant_trade_component.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")
const Interactable = preload("res://modules/interaction/interactable.gd")
const NPCInteractionOption = preload("res://modules/interaction/options/npc_interaction_option.gd")
const NPCData = preload("res://modules/npc/npc_data.gd")
const NPCTradeComponent = preload("res://modules/npc/components/npc_trade_component.gd")

signal actor_spawned(spawn_id: String, actor: Node3D)
signal actor_despawned(spawn_id: String)
signal enemy_spawned(enemy_id: String, enemy_instance: Node3D)
signal enemy_despawned(spawn_id: String)
signal npc_spawned(npc_id: String, npc: Node3D)
signal npc_despawned(npc_id: String)

static var current: AIManager = null

const DEFAULT_AI_BY_BEHAVIOR := {
	"passive": {
		"aggro_range": 4.0,
		"attack_range": 1.2,
		"wander_radius": 3.0,
		"leash_distance": 6.0,
		"decision_interval": 0.8,
		"attack_cooldown": 2.0
	},
	"territorial": {
		"aggro_range": 6.0,
		"attack_range": 1.3,
		"wander_radius": 4.0,
		"leash_distance": 8.0,
		"decision_interval": 0.6,
		"attack_cooldown": 1.6
	},
	"aggressive": {
		"aggro_range": 10.0,
		"attack_range": 1.5,
		"wander_radius": 5.0,
		"leash_distance": 15.0,
		"decision_interval": 0.4,
		"attack_cooldown": 1.2
	}
}

const DEFAULT_NPC_AI := {
	"wander_radius": 3.0,
	"leash_distance": 5.0,
	"decision_interval": 1.2,
	"attack_cooldown": 999.0
}

var enemy_database: Dictionary = {}
var npc_database: Dictionary = {}
var active_actors: Dictionary = {}  # spawn_id -> Node3D
var active_npc_actors: Dictionary = {}  # npc_id -> Node3D
var active_npc_trade_components: Dictionary = {}  # npc_id -> NPCTradeComponent

func _ready() -> void:
	if current and current != self:
		push_warning("[AIManager] Multiple instances detected; replacing AIManager.current")
	current = self
	_load_enemy_database()
	_load_npc_database()

func _exit_tree() -> void:
	if current == self:
		current = null

func _load_enemy_database() -> void:
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager:
		enemy_database = data_manager.get_data("enemies")
	if enemy_database.is_empty() and EnemyDatabase and EnemyDatabase.has_method("get_all_enemy_ids"):
		for enemy_id in EnemyDatabase.get_all_enemy_ids():
			enemy_database[enemy_id] = EnemyDatabase.get_enemy(enemy_id)

func _load_npc_database() -> void:
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager:
		var data = data_manager.get_data("npcs")
		if data is Dictionary and not data.is_empty():
			npc_database = data
			return
	_load_default_npcs()

func _load_default_npcs() -> void:
	var trader_data := NPCData.new()
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

	trader_data.trade_data.inventory = [
		{"id": "medkit", "count": 3, "price": 50},
		{"id": "bandage", "count": 10, "price": 10},
		{"id": "ammo_pistol", "count": 50, "price": 5},
		{"id": "food_canned", "count": 5, "price": 15}
	]
	trader_data.trade_data.buy_price_modifier = 1.2
	trader_data.trade_data.sell_price_modifier = 0.8

	trader_data.recruitment.min_charisma = 10
	trader_data.recruitment.min_friendliness = 80
	trader_data.recruitment.cost_items = [{"id": "food_canned", "count": 20}]

	npc_database[trader_data.id] = trader_data

func spawn_actor(role_kind: String, character_id: String, world_pos: Vector3, context: Dictionary = {}) -> Node3D:
	var normalized_kind := role_kind.to_lower()
	if character_id.is_empty():
		return null

	var spawn_id: String = str(context.get("spawn_id", "%s_%d" % [normalized_kind, Time.get_ticks_msec()]))
	if active_actors.has(spawn_id):
		var existing: Node3D = active_actors[spawn_id]
		if existing and is_instance_valid(existing):
			return existing
		active_actors.erase(spawn_id)

	var actor: Node3D = null
	match normalized_kind:
		"enemy":
			actor = _spawn_enemy(character_id, world_pos, spawn_id)
		"npc":
			actor = _spawn_npc(character_id, world_pos, spawn_id)
		_:
			push_warning("[AIManager] Unknown role_kind '%s'" % normalized_kind)
			return null

	if not actor:
		return null

	active_actors[spawn_id] = actor
	actor.tree_exited.connect(_on_actor_tree_exited.bind(spawn_id), CONNECT_ONE_SHOT)
	actor_spawned.emit(spawn_id, actor)
	return actor

func is_character_id_valid_for_kind(role_kind: String, character_id: String) -> bool:
	if character_id.is_empty():
		return false
	match role_kind.to_lower():
		"npc":
			return get_runtime_npc_data(character_id) != null
		"enemy":
			return enemy_database.has(character_id)
		_:
			return false

func despawn_actor(spawn_id: String) -> void:
	if not active_actors.has(spawn_id):
		return

	var actor: Node3D = active_actors[spawn_id]
	active_actors.erase(spawn_id)

	if actor and is_instance_valid(actor):
		var role_kind := str(actor.get_meta("role_kind", ""))
		if role_kind == "npc":
			var npc_id := str(actor.get_meta("npc_id", ""))
			if not npc_id.is_empty():
				unregister_npc_actor(npc_id)
		actor.queue_free()

	actor_despawned.emit(spawn_id)
	if actor and is_instance_valid(actor) and actor.has_meta("enemy_id"):
		enemy_despawned.emit(spawn_id)

func _spawn_enemy(enemy_id: String, world_pos: Vector3, spawn_id: String) -> Node3D:
	var enemy_data: Dictionary = enemy_database.get(enemy_id, {})
	if enemy_data.is_empty():
		push_warning("[AIManager] Enemy data not found: %s" % enemy_id)
		return null

	var actor := CharacterActorScript.new()
	actor.name = "Enemy_%s" % spawn_id
	actor.position = world_pos
	actor.set_placeholder_colors(Color(1.0, 0.75, 0.75, 1.0), Color(0.80, 0.25, 0.25, 1.0))
	actor.collision_layer = 1 << 2
	actor.collision_mask = 1
	actor.set_meta("enemy_id", enemy_id)
	actor.set_meta("role_kind", "enemy")
	actor.set_meta("spawn_id", spawn_id)
	actor.set_meta("enemy_data", enemy_data.duplicate(true))
	actor.add_to_group("enemy")

	var collision_shape := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.0
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, 1.0, 0.0)
	actor.add_child(collision_shape)

	var name_label := Label3D.new()
	name_label.text = str(enemy_data.get("name", enemy_id))
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 28
	name_label.position = Vector3(0.0, 2.2, 0.0)
	actor.add_child(name_label)

	var movement_component := MovementComponent.new()
	actor.add_child(movement_component)
	if GridMovementSystem and GridMovementSystem.grid_world:
		movement_component.initialize(actor, GridMovementSystem.grid_world)

	var vision_system := VisionSystemScript.new()
	vision_system.name = "VisionSystem"
	actor.add_child(vision_system)
	vision_system.vision_radius = 10
	vision_system.initialize(
		actor,
		Callable(GridMovementSystem, "world_to_grid"),
		Callable(GridMovementSystem, "grid_to_world"),
		Callable(self, "_get_blocker_cells")
	)
	vision_system.bind_to_movement_component(movement_component)
	vision_system.update_from_grid(GridMovementSystem.world_to_grid(world_pos))

	var ai_config := _build_enemy_ai_config(enemy_data)
	var ai_controller := AIController.new()
	actor.add_child(ai_controller)
	ai_controller.initialize(actor, movement_component, world_pos, "enemy", enemy_id, ai_config)

	enemy_spawned.emit(enemy_id, actor)
	return actor

func _spawn_npc(npc_id: String, world_pos: Vector3, spawn_id: String) -> Node3D:
	var npc_data: NPCData = get_runtime_npc_data(npc_id)
	if not npc_data:
		push_warning("[AIManager] NPC data not found: %s" % npc_id)
		return null

	var actor := CharacterActorScript.new()
	actor.name = "NPC_%s" % npc_id
	actor.position = world_pos
	var npc_body_color := get_npc_color(npc_data)
	actor.set_placeholder_colors(npc_body_color.lightened(0.20), npc_body_color)
	actor.collision_layer = 1 << 1
	actor.collision_mask = 0
	actor.set_meta("npc_id", npc_id)
	actor.set_meta("role_kind", "npc")
	actor.set_meta("spawn_id", spawn_id)
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

	var vision_system := VisionSystemScript.new()
	vision_system.name = "VisionSystem"
	actor.add_child(vision_system)
	vision_system.vision_radius = 10
	vision_system.initialize(
		actor,
		Callable(GridMovementSystem, "world_to_grid"),
		Callable(GridMovementSystem, "grid_to_world"),
		Callable(self, "_get_blocker_cells")
	)
	vision_system.bind_to_movement_component(movement_component)
	vision_system.update_from_grid(GridMovementSystem.world_to_grid(world_pos))

	var ai_controller := AIController.new()
	actor.add_child(ai_controller)
	ai_controller.initialize(actor, movement_component, world_pos, "npc", npc_id, DEFAULT_NPC_AI)

	var interactable := Interactable.new()
	interactable.name = "Interactable"
	interactable.set_meta("npc_id", npc_id)
	var npc_option := NPCInteractionOption.new()
	interactable.set_options([npc_option])
	actor.add_child(interactable)

	var trade_component: NPCTradeComponent = null
	if npc_data.can_trade:
		trade_component = GameWorldMerchantTradeComponent.new()
		actor.add_child(trade_component)
		trade_component.initialize_with_data(npc_data)

	register_npc_actor(npc_id, actor, trade_component)
	return actor

func register_npc_actor(npc_id: String, actor: Node3D, trade_component: NPCTradeComponent = null) -> void:
	if npc_id.is_empty() or not actor:
		return
	active_npc_actors[npc_id] = actor
	if trade_component:
		active_npc_trade_components[npc_id] = trade_component
	npc_spawned.emit(npc_id, actor)

func unregister_npc_actor(npc_id: String) -> void:
	if npc_id.is_empty():
		return
	active_npc_actors.erase(npc_id)
	active_npc_trade_components.erase(npc_id)
	npc_despawned.emit(npc_id)

func get_npc_data(npc_id: String) -> NPCData:
	return _build_runtime_npc_data(npc_id)

func get_runtime_npc_data(npc_id: String) -> NPCData:
	return _build_runtime_npc_data(npc_id)

func get_npc_color(npc_data: NPCData) -> Color:
	if not npc_data:
		return Color(0.58, 0.72, 0.88, 1.0)
	if npc_data.can_trade:
		return Color(0.86, 0.73, 0.33, 1.0)
	if npc_data.npc_type == NPCData.Type.HOSTILE:
		return Color(0.78, 0.28, 0.28, 1.0)
	return Color(0.58, 0.72, 0.88, 1.0)

func start_npc_interaction(npc_id: String) -> bool:
	var npc_data: NPCData = _build_runtime_npc_data(npc_id)
	if not npc_data:
		return false
	if not DialogModule:
		push_warning("[AIManager] DialogModule unavailable; cannot start interaction: %s" % npc_id)
		return false

	var speaker: String = npc_data.name if not npc_data.name.is_empty() else npc_id
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

func register_npc(npc_data: NPCData) -> void:
	if not npc_data or npc_data.id.is_empty():
		return
	npc_database[npc_data.id] = npc_data

func serialize_all_npc_data() -> Dictionary:
	var result: Dictionary = {}
	for npc_id in npc_database.keys():
		var npc_data: NPCData = _build_runtime_npc_data(str(npc_id))
		if npc_data:
			result[npc_id] = npc_data.serialize()
	return result

func deserialize_all_npc_data(data: Dictionary) -> void:
	for npc_id in data.keys():
		var raw = data[npc_id]
		if not (raw is Dictionary):
			continue
		var npc_data := NPCData.new()
		npc_data.deserialize(raw)
		npc_data.id = str(raw.get("id", str(npc_id)))
		npc_database[npc_data.id] = npc_data

func reset_all_npcs() -> void:
	for npc_data in npc_database.values():
		var runtime_data: NPCData = npc_data as NPCData
		if not runtime_data:
			continue
		runtime_data.state.is_alive = true
		runtime_data.state.is_recruited = false
		runtime_data.state.is_hostile = false
		runtime_data.state.is_busy = false
		runtime_data.memory.met_player = false
		runtime_data.memory.interaction_count = 0
		runtime_data.memory.player_actions.clear()
		runtime_data.mood.friendliness = 50
		runtime_data.mood.trust = 30
		runtime_data.mood.fear = 0
		runtime_data.mood.anger = 0

	for npc_id in active_npc_actors.keys():
		unregister_npc_actor(str(npc_id))

func _build_runtime_npc_data(npc_id: String) -> NPCData:
	var record = npc_database.get(npc_id, null)
	if not record:
		return null

	if record is NPCData:
		return record as NPCData

	if not (record is Dictionary):
		return null

	var npc_data := NPCData.new()
	npc_data.deserialize(record)
	npc_data.id = str(record.get("id", npc_id))
	npc_data.name = str(record.get("name", npc_data.name))
	if npc_data.default_location.is_empty():
		npc_data.default_location = str(record.get("default_location", ""))
	if npc_data.current_location.is_empty():
		npc_data.current_location = npc_data.default_location
	npc_database[npc_id] = npc_data
	return npc_data

func _build_enemy_ai_config(enemy_data: Dictionary) -> Dictionary:
	var behavior := str(enemy_data.get("behavior", "passive"))
	var config := {}
	if DEFAULT_AI_BY_BEHAVIOR.has(behavior):
		config = DEFAULT_AI_BY_BEHAVIOR[behavior].duplicate(true)
	else:
		config = DEFAULT_AI_BY_BEHAVIOR.passive.duplicate(true)

	if enemy_data.has("ai") and enemy_data.ai is Dictionary:
		config.merge(enemy_data.ai, true)

	return config

func _get_blocker_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var nodes := get_tree().get_nodes_in_group("vision_blocker")
	for node in nodes:
		if node is Node3D:
			var world_pos: Vector3 = node.global_position
			cells.append(GridMovementSystem.world_to_grid(world_pos))
	return cells

func _on_actor_tree_exited(spawn_id: String) -> void:
	if not active_actors.has(spawn_id):
		return

	var actor: Node3D = active_actors[spawn_id]
	active_actors.erase(spawn_id)

	if actor:
		var role_kind := str(actor.get_meta("role_kind", ""))
		if role_kind == "npc":
			var npc_id := str(actor.get_meta("npc_id", ""))
			if not npc_id.is_empty():
				unregister_npc_actor(npc_id)

	actor_despawned.emit(spawn_id)
	if actor and actor.has_meta("enemy_id"):
		enemy_despawned.emit(spawn_id)
