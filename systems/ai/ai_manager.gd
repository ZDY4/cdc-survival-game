extends Node
## AIManager - Unified runtime actor provider with character_data.

class_name AIManager

const MovementComponent = preload("res://systems/movement_component.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")
const AIController = preload("res://systems/ai/ai_controller.gd")
const CharacterRelationResolver = preload("res://systems/character_relation_resolver.gd")
const GameWorldMerchantTradeComponent = preload("res://modules/npc/components/game_world_merchant_trade_component.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")
const Interactable = preload("res://modules/interaction/interactable.gd")
const NPCInteractionOption = preload("res://modules/interaction/options/npc_interaction_option.gd")
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
	},
	"neutral": {
		"aggro_range": 0.0,
		"attack_range": 1.2,
		"wander_radius": 3.0,
		"leash_distance": 5.0,
		"decision_interval": 1.2,
		"attack_cooldown": 999.0
	}
}

var character_database: Dictionary = {}
var active_actors: Dictionary = {}  # spawn_id -> Node3D
var active_npc_actors: Dictionary = {}  # character_id -> Node3D
var active_npc_trade_components: Dictionary = {}  # character_id -> NPCTradeComponent

var _relation_resolver: CharacterRelationResolver = CharacterRelationResolver.new()

func _ready() -> void:
	if current and current != self:
		push_warning("[AIManager] Multiple instances detected; replacing AIManager.current")
	current = self
	_load_character_database()

func _exit_tree() -> void:
	if current == self:
		current = null

func _load_character_database() -> void:
	character_database.clear()
	var data_manager := get_node_or_null("/root/DataManager")
	if data_manager and data_manager.has_method("get_all_characters"):
		var loaded: Variant = data_manager.get_all_characters()
		if loaded is Dictionary:
			character_database = loaded.duplicate(true)

func spawn_actor(character_id: String, world_pos: Vector3, context: Dictionary = {}) -> Node3D:
	var resolved_id: String = character_id.strip_edges()
	if resolved_id.is_empty():
		return null
	if not character_database.has(resolved_id):
		push_warning("[AIManager] Character data not found: %s" % resolved_id)
		return null

	var spawn_id: String = str(context.get("spawn_id", "%s_%d" % [resolved_id, Time.get_ticks_msec()]))
	if active_actors.has(spawn_id):
		var existing: Node3D = active_actors[spawn_id]
		if existing and is_instance_valid(existing):
			return existing
		active_actors.erase(spawn_id)

	var character_data: Dictionary = _get_character_data_internal(resolved_id)
	var relation_result: Dictionary = _relation_resolver.resolve_for_player(resolved_id, character_data)
	var actor: Node3D = _spawn_character_actor(resolved_id, character_data, relation_result, world_pos, spawn_id)
	if not actor:
		return null

	active_actors[spawn_id] = actor
	actor.tree_exited.connect(_on_actor_tree_exited.bind(spawn_id), CONNECT_ONE_SHOT)
	actor_spawned.emit(spawn_id, actor)
	return actor

func is_character_id_valid(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	return character_database.has(character_id)

func despawn_actor(spawn_id: String) -> void:
	if not active_actors.has(spawn_id):
		return

	var actor: Node3D = active_actors[spawn_id]
	active_actors.erase(spawn_id)

	if actor and is_instance_valid(actor):
		var character_id: String = str(actor.get_meta("character_id", ""))
		if not character_id.is_empty():
			unregister_npc_actor(character_id)
		actor.queue_free()

	actor_despawned.emit(spawn_id)
	if actor and is_instance_valid(actor) and bool(actor.get_meta("allow_attack", false)):
		enemy_despawned.emit(spawn_id)

func _spawn_character_actor(
	character_id: String,
	character_data: Dictionary,
	relation_result: Dictionary,
	world_pos: Vector3,
	spawn_id: String
) -> Node3D:
	var actor := CharacterActorScript.new()
	actor.name = "Character_%s" % character_id
	actor.position = world_pos
	actor.initialize_from_character_data(character_id, character_data, relation_result, {"spawn_id": spawn_id})

	var allow_attack: bool = bool(relation_result.get("allow_attack", false))
	var allow_interaction: bool = bool(relation_result.get("allow_interaction", false))
	var allow_trade: bool = bool(relation_result.get("allow_trade", false))

	actor.set_meta("allow_attack", allow_attack)
	actor.set_meta("allow_interaction", allow_interaction)
	actor.set_meta("allow_trade", allow_trade)
	actor.set_meta("spawn_id", spawn_id)

	if allow_attack:
		actor.collision_layer = 1 << 2
		actor.collision_mask = 1
		actor.add_to_group("enemy")
		actor.set_meta("enemy_id", character_id)
		enemy_spawned.emit(character_id, actor)
	else:
		actor.collision_layer = 1 << 1
		actor.collision_mask = 0
		actor.add_to_group("npc")
		actor.set_meta("npc_id", character_id)
		npc_spawned.emit(character_id, actor)

	_add_common_actor_nodes(actor, character_data)

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

	var ai_config: Dictionary = _build_ai_config(character_data, relation_result)
	var ai_controller := AIController.new()
	actor.add_child(ai_controller)
	ai_controller.initialize(actor, movement_component, world_pos, character_id, ai_config)

	if allow_interaction:
		var interactable := Interactable.new()
		interactable.name = "Interactable"
		interactable.set_meta("npc_id", character_id)
		var npc_option := NPCInteractionOption.new()
		interactable.set_options([npc_option])
		actor.add_child(interactable)

	var trade_component: NPCTradeComponent = null
	if allow_trade:
		trade_component = GameWorldMerchantTradeComponent.new()
		actor.add_child(trade_component)
		trade_component.initialize_with_data(character_data)

	if allow_interaction:
		register_npc_actor(character_id, actor, trade_component)

	return actor

func _add_common_actor_nodes(actor: Node3D, character_data: Dictionary) -> void:
	var collision_shape := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.0
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, 1.0, 0.0)
	actor.add_child(collision_shape)

	var display_name: String = _resolve_character_display_name(character_data)
	var name_label := Label3D.new()
	name_label.text = display_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 30
	name_label.position = Vector3(0.0, 2.2, 0.0)
	actor.add_child(name_label)

func _resolve_character_display_name(character_data: Dictionary) -> String:
	var social: Dictionary = character_data.get("social", {})
	var title: String = str(social.get("title", ""))
	var base_name: String = str(character_data.get("name", character_data.get("id", "角色")))
	if title.is_empty():
		return base_name
	return "%s·%s" % [title, base_name]

func _build_ai_config(character_data: Dictionary, relation_result: Dictionary) -> Dictionary:
	var allow_attack: bool = bool(relation_result.get("allow_attack", false))
	var combat: Dictionary = character_data.get("combat", {})
	var behavior: String = str(combat.get("behavior", "neutral")).to_lower()

	var config: Dictionary = DEFAULT_AI_BY_BEHAVIOR.neutral.duplicate(true)
	if allow_attack:
		if DEFAULT_AI_BY_BEHAVIOR.has(behavior):
			config = DEFAULT_AI_BY_BEHAVIOR[behavior].duplicate(true)
		else:
			config = DEFAULT_AI_BY_BEHAVIOR.aggressive.duplicate(true)

	var ai_data: Dictionary = combat.get("ai", {})
	config.merge(ai_data, true)
	config["allow_attack"] = allow_attack
	return config

func register_npc_actor(character_id: String, actor: Node3D, trade_component: NPCTradeComponent = null) -> void:
	if character_id.is_empty() or not actor:
		return
	active_npc_actors[character_id] = actor
	if trade_component:
		active_npc_trade_components[character_id] = trade_component

func unregister_npc_actor(character_id: String) -> void:
	if character_id.is_empty():
		return
	active_npc_actors.erase(character_id)
	active_npc_trade_components.erase(character_id)
	npc_despawned.emit(character_id)

func get_character_data(character_id: String) -> Dictionary:
	return _get_character_data_internal(character_id)

func start_npc_interaction(character_id: String) -> bool:
	var data: Dictionary = _get_character_data_internal(character_id)
	if data.is_empty():
		return false
	if not DialogModule:
		push_warning("[AIManager] DialogModule unavailable; cannot start interaction: %s" % character_id)
		return false

	var relation_result: Dictionary = _relation_resolver.resolve_for_player(character_id, data)
	if not bool(relation_result.get("allow_interaction", false)):
		DialogModule.show_dialog("对方对你充满敌意，不愿交谈。", str(data.get("name", "陌生人")))
		await DialogModule.dialog_finished
		return false

	var speaker: String = str(data.get("name", character_id))
	var greeting := "你好，我是%s。" % speaker
	if bool(relation_result.get("allow_trade", false)):
		greeting = "需要补给吗？我这里还能交易。"
	DialogModule.show_dialog(greeting, speaker)
	await DialogModule.dialog_finished

	if bool(relation_result.get("allow_trade", false)):
		var choice: int = await DialogModule.show_choices(["交易", "闲聊", "离开"])
		match choice:
			0:
				var trade_component: NPCTradeComponent = active_npc_trade_components.get(character_id, null)
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
		DialogModule.show_dialog("别走太远，外面很危险。", speaker)
		await DialogModule.dialog_finished

	return true

func _get_character_data_internal(character_id: String) -> Dictionary:
	var resolved_id: String = character_id.strip_edges()
	if resolved_id.is_empty():
		return {}
	var data: Variant = character_database.get(resolved_id, {})
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return {}

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
		var character_id: String = str(actor.get_meta("character_id", ""))
		if not character_id.is_empty():
			unregister_npc_actor(character_id)

	actor_despawned.emit(spawn_id)
	if actor and bool(actor.get_meta("allow_attack", false)):
		enemy_despawned.emit(spawn_id)
