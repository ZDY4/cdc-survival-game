extends Node
## AIManager - Unified runtime actor provider with character_data.
## LEGACY AUTHORITY BOUNDARY:
## This manager still assembles AI-related runtime pieces inside Godot. Do not
## grow it into a long-term authority for NPC decision logic. Future ownership
## belongs in Rust/Bevy, while Godot remains responsible for visual actor
## assembly, hit mapping, and presentation bridging.

class_name AIManager

const MovementComponentScript = preload("res://systems/movement_component.gd")
const CharacterActorScript = preload("res://systems/character_actor.gd")
const CharacterSkillRuntimeScript = preload("res://systems/character_skill_runtime.gd")
const AIControllerScript = preload("res://systems/ai/ai_controller.gd")
const CharacterRelationResolverScript = preload("res://systems/character_relation_resolver.gd")
const VisionSystemScript = preload("res://systems/vision_system.gd")
const InteractableScript = preload("res://modules/interaction/interactable.gd")
const TalkInteractionOptionScript = preload("res://modules/interaction/options/talk_interaction_option.gd")
const AttackInteractionOptionScript = preload("res://modules/interaction/options/attack_interaction_option.gd")

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

var _relation_resolver = CharacterRelationResolverScript.new()

func _ready() -> void:
	if current and current != self:
		push_warning("[AIManager] Multiple instances detected; replacing AIManager.current")
	current = self
	_load_character_database()
	_connect_relationship_signals()

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

	var spawn_world_pos: Vector3 = _snap_world_pos_to_grid(world_pos)
	var character_data: Dictionary = _get_character_data_internal(resolved_id)
	var relation_result: Dictionary = _relation_resolver.resolve_for_player(resolved_id, character_data)
	var actor: Node3D = _spawn_character_actor(
		resolved_id,
		character_data,
		relation_result,
		spawn_world_pos,
		spawn_id
	)
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

func find_active_actor_by_character_id(character_id: String) -> Node3D:
	if character_id.is_empty():
		return null
	for actor_variant in active_actors.values():
		var actor := actor_variant as Node3D
		if actor == null or not is_instance_valid(actor):
			continue
		if str(actor.get_meta("character_id", "")) == character_id:
			return actor
	return null

func despawn_actor(spawn_id: String) -> void:
	if not active_actors.has(spawn_id):
		return

	var actor: Node3D = active_actors[spawn_id]
	active_actors.erase(spawn_id)

	if actor and is_instance_valid(actor):
		var character_id: String = str(actor.get_meta("character_id", ""))
		if not character_id.is_empty() and not bool(actor.get_meta("allow_attack", false)):
			npc_despawned.emit(character_id)
		if TurnSystem:
			TurnSystem.unregister_actor(actor)
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

	_add_common_actor_nodes(actor, character_data)

	var movement_component := MovementComponentScript.new()
	movement_component.name = "MovementComponent"
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

	var skill_runtime := CharacterSkillRuntimeScript.new()
	skill_runtime.name = "CharacterSkillRuntime"
	actor.add_child(skill_runtime)
	skill_runtime.initialize(
		actor,
		spawn_id,
		character_data.get("skills", {}),
		get_node_or_null("/root/SkillModule"),
		get_node_or_null("/root/EffectSystem")
	)

	var ai_config: Dictionary = _build_ai_config(character_data, relation_result)
	var ai_controller := AIControllerScript.new()
	ai_controller.name = "AIController"
	actor.add_child(ai_controller)
	ai_controller.initialize(actor, movement_component, world_pos, character_id, ai_config, skill_runtime)

	var interactable := _ensure_interactable(actor)
	_apply_actor_relation_state(actor, interactable, character_id, character_data, relation_result, spawn_id)
	_register_actor_with_turn_system(actor, relation_result, spawn_id)
	_emit_actor_spawn_signal(character_id, actor, relation_result)

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
	if actor.has_method("get_visual_root"):
		var visual_root: Variant = actor.call("get_visual_root")
		if visual_root is Node3D:
			(visual_root as Node3D).add_child(name_label)
			return
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

func _connect_relationship_signals() -> void:
	if GameStateManager == null or not GameStateManager.has_signal("relationship_changed"):
		return
	if GameStateManager.relationship_changed.is_connected(_on_relationship_changed):
		return
	GameStateManager.relationship_changed.connect(_on_relationship_changed)

func get_character_data(character_id: String) -> Dictionary:
	return _get_character_data_internal(character_id)

func _get_character_data_internal(character_id: String) -> Dictionary:
	var resolved_id: String = character_id.strip_edges()
	if resolved_id.is_empty():
		return {}
	var data: Variant = character_database.get(resolved_id, {})
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return {}

func _snap_world_pos_to_grid(world_pos: Vector3) -> Vector3:
	if not GridMovementSystem or not GridMovementSystem.has_method("snap_to_grid"):
		return world_pos

	var snapped_world_pos: Vector3 = GridMovementSystem.snap_to_grid(world_pos)
	snapped_world_pos.y = world_pos.y
	return snapped_world_pos

func _get_blocker_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var nodes := get_tree().get_nodes_in_group("vision_blocker")
	for node in nodes:
		if node is Node3D:
			var world_pos: Vector3 = node.global_position
			cells.append(GridMovementSystem.world_to_grid(world_pos))
	return cells

func _ensure_interactable(actor: Node3D) -> Node:
	var existing := actor.get_node_or_null("Interactable")
	if existing and existing is InteractableScript:
		return existing as Node

	var interactable := InteractableScript.new()
	interactable.name = "Interactable"
	actor.add_child(interactable)
	return interactable

func _build_interaction_options(
	character_id: String,
	character_data: Dictionary,
	relation_result: Dictionary
) -> Array:
	var options: Array = []
	var visual: Dictionary = character_data.get("visual", {})
	var social: Dictionary = character_data.get("social", {})

	if bool(relation_result.get("allow_interaction", false)):
		var talk_option := TalkInteractionOptionScript.new()
		talk_option.dialog_id = str(social.get("dialog_id", ""))
		talk_option.speaker_name = str(character_data.get("name", character_id))
		talk_option.portrait_path = str(visual.get("portrait_path", ""))
		options.append(talk_option)

	var attack_option := AttackInteractionOptionScript.new()
	attack_option.enemy_id = character_id
	attack_option.enemy_name = str(character_data.get("name", character_id))
	options.append(attack_option)

	return options

func _apply_actor_relation_state(
	actor: Node3D,
	interactable: Node,
	character_id: String,
	character_data: Dictionary,
	relation_result: Dictionary,
	spawn_id: String
) -> void:
	var allow_attack: bool = bool(relation_result.get("allow_attack", false))
	var allow_interaction: bool = bool(relation_result.get("allow_interaction", false))
	var allow_trade: bool = bool(relation_result.get("allow_trade", false))

	actor.set_meta("allow_attack", allow_attack)
	actor.set_meta("allow_interaction", allow_interaction)
	actor.set_meta("allow_trade", allow_trade)
	actor.set_meta("spawn_id", spawn_id)
	actor.set_meta("character_id", character_id)
	actor.set_meta("character_data", character_data.duplicate(true))
	actor.set_meta("relation_result", relation_result.duplicate(true))
	actor.set_meta("resolved_attitude", str(relation_result.get("resolved_attitude", "neutral")))
	if actor.has_method("refresh_relation_state"):
		actor.refresh_relation_state(relation_result)

	interactable.set_meta("character_id", character_id)
	interactable.set_meta("relation_result", relation_result.duplicate(true))
	interactable.set_meta("resolved_attitude", str(relation_result.get("resolved_attitude", "neutral")))
	if allow_attack:
		actor.collision_layer = 1 << 2
		actor.collision_mask = 1
		actor.remove_from_group("npc")
		if not actor.is_in_group("enemy"):
			actor.add_to_group("enemy")
		actor.set_meta("enemy_id", character_id)
		actor.remove_meta("npc_id")
		interactable.set_meta("enemy_id", character_id)
		interactable.remove_meta("npc_id")
	else:
		actor.collision_layer = 1 << 1
		actor.collision_mask = 0
		actor.remove_from_group("enemy")
		if not actor.is_in_group("npc"):
			actor.add_to_group("npc")
		actor.set_meta("npc_id", character_id)
		actor.remove_meta("enemy_id")
		interactable.set_meta("npc_id", character_id)
		interactable.remove_meta("enemy_id")

	interactable.set_options(_build_interaction_options(character_id, character_data, relation_result))
	_register_actor_with_turn_system(actor, relation_result, spawn_id)

func _refresh_actor_relation(actor: Node3D, character_id: String, spawn_id: String) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var current_data_variant: Variant = actor.get_meta("character_data", {})
	var character_data: Dictionary = {}
	if current_data_variant is Dictionary and not (current_data_variant as Dictionary).is_empty():
		character_data = (current_data_variant as Dictionary).duplicate(true)
	else:
		character_data = _get_character_data_internal(character_id)
	if character_data.is_empty():
		return

	var relation_result: Dictionary = _relation_resolver.resolve_for_player(character_id, character_data)
	var interactable := _ensure_interactable(actor)
	_apply_actor_relation_state(actor, interactable, character_id, character_data, relation_result, spawn_id)

	var ai_controller := actor.get_node_or_null("AIController")
	if ai_controller and ai_controller.has_method("refresh_runtime_config"):
		var ai_config: Dictionary = _build_ai_config(character_data, relation_result)
		ai_controller.refresh_runtime_config(ai_config)

	var trade_component: Variant = actor.get_meta("bound_trade_component", null)
	actor.set_meta("has_bound_trade_component", trade_component != null)

func _emit_actor_spawn_signal(character_id: String, actor: Node3D, relation_result: Dictionary) -> void:
	if bool(relation_result.get("allow_attack", false)):
		enemy_spawned.emit(character_id, actor)
		return
	npc_spawned.emit(character_id, actor)

func _on_relationship_changed(npc_id: String, _new_value: int, _change: int) -> void:
	if npc_id.is_empty():
		return
	for spawn_id in active_actors.keys():
		var actor: Node3D = active_actors[spawn_id]
		if actor == null or not is_instance_valid(actor):
			continue
		if str(actor.get_meta("character_id", "")) != npc_id:
			continue
		_refresh_actor_relation(actor, npc_id, str(spawn_id))

func _on_actor_tree_exited(spawn_id: String) -> void:
	if not active_actors.has(spawn_id):
		return

	var actor: Node3D = active_actors[spawn_id]
	active_actors.erase(spawn_id)

	if actor:
		var character_id: String = str(actor.get_meta("character_id", ""))
		if not character_id.is_empty() and not bool(actor.get_meta("allow_attack", false)):
			npc_despawned.emit(character_id)
		if TurnSystem:
			TurnSystem.unregister_actor(actor)

	actor_despawned.emit(spawn_id)
	if actor and bool(actor.get_meta("allow_attack", false)):
		enemy_despawned.emit(spawn_id)

func _register_actor_with_turn_system(actor: Node3D, relation_result: Dictionary, spawn_id: String) -> void:
	if TurnSystem == null or actor == null or not is_instance_valid(actor):
		return
	var allow_attack: bool = bool(relation_result.get("allow_attack", false))
	var group_id := "friendly"
	var group_order := int(TurnSystem.DEFAULT_GROUP_ORDERS.get("friendly", 10))
	var side := "friendly"
	if allow_attack:
		group_id = "hostile:%s" % spawn_id
		group_order = 100 + int(actor.get_meta("turn_group_order", active_actors.size()))
		side = "hostile"
	TurnSystem.register_group(group_id, group_order)
	TurnSystem.register_actor(actor, group_id, side)
