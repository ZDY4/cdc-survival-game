extends Node
## AIManager - Unified runtime actor provider (enemy/npc) for 3D scenes.

class_name AIManager

const MovementComponent = preload("res://systems/movement_component.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")
const AIController = preload("res://systems/ai/ai_controller.gd")
const GameWorldMerchantTradeComponent = preload("res://modules/npc/components/game_world_merchant_trade_component.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")

signal actor_spawned(spawn_id: String, actor: Node3D)
signal actor_despawned(spawn_id: String)
signal enemy_spawned(enemy_id: String, enemy_instance: Node3D)
signal enemy_despawned(spawn_id: String)

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
var active_actors: Dictionary = {}  # spawn_id -> Node3D

func _ready() -> void:
	_load_enemy_database()

func _load_enemy_database() -> void:
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager:
		enemy_database = data_manager.get_data("enemies")
	if enemy_database.is_empty() and EnemyDatabase and EnemyDatabase.has_method("get_all_enemy_ids"):
		for enemy_id in EnemyDatabase.get_all_enemy_ids():
			enemy_database[enemy_id] = EnemyDatabase.get_enemy(enemy_id)

func spawn_actor(role_kind: String, role_id: String, world_pos: Vector3, context: Dictionary = {}) -> Node3D:
	var normalized_kind := role_kind.to_lower()
	if role_id.is_empty():
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
			actor = _spawn_enemy(role_id, world_pos, spawn_id)
		"npc":
			actor = _spawn_npc(role_id, world_pos, spawn_id)
		_:
			push_warning("[AIManager] Unknown role_kind '%s'" % normalized_kind)
			return null

	if not actor:
		return null

	active_actors[spawn_id] = actor
	actor.tree_exited.connect(_on_actor_tree_exited.bind(spawn_id), CONNECT_ONE_SHOT)
	actor_spawned.emit(spawn_id, actor)
	return actor

func despawn_actor(spawn_id: String) -> void:
	if not active_actors.has(spawn_id):
		return

	var actor: Node3D = active_actors[spawn_id]
	active_actors.erase(spawn_id)

	if actor and is_instance_valid(actor):
		var role_kind := str(actor.get_meta("role_kind", ""))
		if role_kind == "npc" and NPCModule:
			var npc_id := str(actor.get_meta("npc_id", ""))
			if not npc_id.is_empty() and NPCModule.has_method("unregister_npc_actor"):
				NPCModule.unregister_npc_actor(npc_id)
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
	if not NPCModule:
		push_warning("[AIManager] NPCModule unavailable; cannot spawn NPC: %s" % npc_id)
		return null

	var npc_data = null
	if NPCModule.has_method("get_runtime_npc_data"):
		npc_data = NPCModule.get_runtime_npc_data(npc_id)
	else:
		npc_data = NPCModule.get_npc_data(npc_id)

	if not npc_data:
		push_warning("[AIManager] NPC data not found: %s" % npc_id)
		return null

	var actor := CharacterActorScript.new()
	actor.name = "NPC_%s" % npc_id
	actor.position = world_pos
	var npc_body_color := _resolve_npc_color(npc_data)
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
	if npc_data is Dictionary:
		name_label.text = str(npc_data.get("name", npc_id))
	else:
		name_label.text = npc_data.get_display_name() if npc_data.has_method("get_display_name") else str(npc_id)
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

	var trade_component: Node = null
	if not (npc_data is Dictionary) and npc_data.can_trade:
		trade_component = GameWorldMerchantTradeComponent.new()
		actor.add_child(trade_component)
		trade_component.initialize_with_data(npc_data)

	if NPCModule.has_method("register_npc_actor"):
		NPCModule.register_npc_actor(npc_id, actor, trade_component)

	return actor

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

func _resolve_npc_color(npc_data) -> Color:
	if NPCModule and NPCModule.has_method("get_npc_color"):
		return NPCModule.get_npc_color(npc_data)
	if npc_data:
		if npc_data is Dictionary:
			if npc_data.get("can_trade", false):
				return Color(0.86, 0.73, 0.33, 1.0)
			if int(npc_data.get("npc_type", -1)) == 2:
				return Color(0.78, 0.28, 0.28, 1.0)
		else:
			if npc_data.can_trade:
				return Color(0.86, 0.73, 0.33, 1.0)
			if int(npc_data.npc_type) == 2:
				return Color(0.78, 0.28, 0.28, 1.0)
	return Color(0.58, 0.72, 0.88, 1.0)

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

	if actor and is_instance_valid(actor):
		var role_kind := str(actor.get_meta("role_kind", ""))
		if role_kind == "npc" and NPCModule and NPCModule.has_method("unregister_npc_actor"):
			var npc_id := str(actor.get_meta("npc_id", ""))
			if not npc_id.is_empty():
				NPCModule.unregister_npc_actor(npc_id)

	actor_despawned.emit(spawn_id)
	if actor and is_instance_valid(actor) and actor.has_meta("enemy_id"):
		enemy_despawned.emit(spawn_id)
